import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

/// Why a backup could not be read.
enum BackupProblem {
  notABackup,
  wrongPassphrase,
  needsPassphrase,
  unexpectedPassphrase,
  newerApp,
}

class BackupException implements Exception {
  const BackupException(this.problem, this.message);

  final BackupProblem problem;
  final String message;

  @override
  String toString() => message;
}

/// What a backup file says about itself before it is opened.
class BackupInfo {
  const BackupInfo({required this.encrypted, required this.schemaVersion});

  final bool encrypted;
  final int schemaVersion;
}

/// A backup is the SQLite database verbatim behind a short header, so any SQLite
/// tool can open it.
///
/// Encrypted with AES-GCM over a PBKDF2 key. GCM is authenticated, so a wrong
/// passphrase fails loudly rather than restoring garbage.
class BackupService {
  const BackupService();

  static const _magic = [0x4B, 0x4F, 0x52, 0x49, 0x42, 0x41, 0x4B]; // KORIBAK
  static const _formatVersion = 1;
  static const _saltLength = 16;
  static const _iterations = 210000;

  /// Header is magic(7) + format(1) + encrypted(1) + schemaVersion(2).
  static const _headerLength = 11;

  static const extensionPlain = 'kori.db';
  static const extensionEncrypted = 'kori.enc';

  /// Wraps [database] bytes, encrypting when a passphrase is given.
  Future<Uint8List> pack({
    required Uint8List database,
    required int schemaVersion,
    String? passphrase,
  }) async {
    final header = _header(
      encrypted: passphrase != null,
      schemaVersion: schemaVersion,
    );

    if (passphrase == null) {
      return Uint8List.fromList([...header, ...database]);
    }

    final salt = _randomBytes(_saltLength);
    final algorithm = AesGcm.with256bits();
    final key = await _deriveKey(passphrase, salt);
    final box = await algorithm.encrypt(database, secretKey: key);

    // salt, then nonce, then mac, then ciphertext — all fixed-length but the last.
    return Uint8List.fromList([
      ...header,
      ...salt,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  /// Reads the header without needing the passphrase, so the UI can ask for one
  /// only when the file actually wants it.
  BackupInfo inspect(Uint8List bytes) {
    if (bytes.length < _headerLength ||
        !_startsWithMagic(bytes)) {
      throw const BackupException(
        BackupProblem.notABackup,
        'This is not a Kori backup file.',
      );
    }
    if (bytes[7] > _formatVersion) {
      throw const BackupException(
        BackupProblem.newerApp,
        'This backup was made by a newer version of Kori.',
      );
    }
    return BackupInfo(
      encrypted: bytes[8] == 1,
      schemaVersion: bytes[9] << 8 | bytes[10],
    );
  }

  /// Returns the database bytes, decrypting when needed.
  Future<Uint8List> unpack(
    Uint8List bytes, {
    String? passphrase,
    required int supportedSchemaVersion,
  }) async {
    final info = inspect(bytes);

    if (info.schemaVersion > supportedSchemaVersion) {
      throw const BackupException(
        BackupProblem.newerApp,
        'This backup needs a newer version of Kori to open.',
      );
    }
    if (info.encrypted && passphrase == null) {
      throw const BackupException(
        BackupProblem.needsPassphrase,
        'This backup is encrypted. Enter its passphrase.',
      );
    }
    if (!info.encrypted && passphrase != null) {
      throw const BackupException(
        BackupProblem.unexpectedPassphrase,
        'This backup is not encrypted, so it needs no passphrase.',
      );
    }

    final body = bytes.sublist(_headerLength);
    if (!info.encrypted) return Uint8List.fromList(body);

    final algorithm = AesGcm.with256bits();
    final nonceLength = AesGcm.defaultNonceLength;
    const macLength = 16;
    if (body.length < _saltLength + nonceLength + macLength) {
      throw const BackupException(
        BackupProblem.notABackup,
        'This backup file is truncated.',
      );
    }

    final salt = body.sublist(0, _saltLength);
    final nonce = body.sublist(_saltLength, _saltLength + nonceLength);
    final mac = body.sublist(
      _saltLength + nonceLength,
      _saltLength + nonceLength + macLength,
    );
    final cipherText = body.sublist(_saltLength + nonceLength + macLength);

    final key = await _deriveKey(passphrase!, salt);
    try {
      final clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      // GCM caught it: wrong passphrase, or the file was tampered with.
      throw const BackupException(
        BackupProblem.wrongPassphrase,
        'That passphrase does not open this backup.',
      );
    }
  }

  /// Overwrites the database at [path]. The caller closes the database first and
  /// reopens after; SQLite must not be holding the file.
  Future<void> writeDatabaseFile(String path, Uint8List database) async {
    final file = File(path);
    // Written beside the target then renamed, so an interrupted restore cannot
    // leave a half-written database in place.
    final staging = File('$path.restoring');
    await staging.writeAsBytes(database, flush: true);
    if (file.existsSync()) await file.delete();
    await staging.rename(path);

    // SQLite's sidecar files describe the database we just replaced.
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$path$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }
  }

  /// Rejects anything that is not a SQLite database, so a mistyped file cannot
  /// be written over someone's data.
  static bool looksLikeSqlite(Uint8List bytes) {
    const header = 'SQLite format 3';
    if (bytes.length < header.length) return false;
    for (final (index, code) in header.codeUnits.indexed) {
      if (bytes[index] != code) return false;
    }
    return true;
  }

  static String fileName({required bool encrypted, DateTime? now}) {
    final date = now ?? DateTime.now();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final extension = encrypted ? extensionEncrypted : extensionPlain;
    return 'kori-backup-${date.year}-$month-$day.$extension';
  }

  List<int> _header({required bool encrypted, required int schemaVersion}) => [
        ..._magic,
        _formatVersion,
        encrypted ? 1 : 0,
        (schemaVersion >> 8) & 0xFF,
        schemaVersion & 0xFF,
      ];

  bool _startsWithMagic(Uint8List bytes) {
    for (final (index, byte) in _magic.indexed) {
      if (bytes[index] != byte) return false;
    }
    return true;
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final pbkdf2 = Pbkdf2.hmacSha256(iterations: _iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      [for (var index = 0; index < length; index++) random.nextInt(256)],
    );
  }
}
