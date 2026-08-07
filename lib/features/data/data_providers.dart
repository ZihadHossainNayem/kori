import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/io/backup_service.dart';
import '../../data/io/export_service.dart';
import '../../data/io/file_transfer.dart';
import '../../data/io/import_service.dart';
import '../../data/providers.dart';

final fileTransferProvider = Provider<FileTransfer>((ref) => const FileTransfer());
final backupServiceProvider = Provider<BackupService>((ref) => const BackupService());

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(databaseProvider)),
);
final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(ref.watch(databaseProvider)),
);

/// The database as bytes. The checkpoint matters — recent writes live in the
/// -wal sidecar, and a copy without them silently misses the newest rows.
Future<Uint8List> readDatabaseBytes(KoriDatabase database) async {
  await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  return File(await FileTransfer.databasePath()).readAsBytes();
}

/// Replaces the database file and reopens it.
///
/// The database must be closed before the file is overwritten, so this owns the
/// order: close, write, invalidate so the next read opens the restored file.
class RestoreController {
  const RestoreController(this._ref);

  final Ref _ref;

  Future<void> restore(Uint8List database) async {
    if (!BackupService.looksLikeSqlite(database)) {
      throw const BackupException(
        BackupProblem.notABackup,
        'That file is not a database.',
      );
    }

    final path = await FileTransfer.databasePath();
    await _ref.read(databaseProvider).close();
    await _ref.read(backupServiceProvider).writeDatabaseFile(path, database);
    _ref.invalidate(databaseProvider);
  }
}

final restoreControllerProvider =
    Provider<RestoreController>(RestoreController.new);
