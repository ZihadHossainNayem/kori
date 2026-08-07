import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user chose.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Files move in and out through the system share sheet, so the user picks
/// where they land and no cloud account is involved.
class FileTransfer {
  const FileTransfer();

  /// Where drift_flutter keeps the database. Derived the same way, so the two
  /// cannot drift apart.
  static Future<String> databasePath({String name = 'kori'}) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$name.sqlite';
  }

  Future<void> share(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async {
    // Staged in the cache so the share sheet has a real file to hand over; the
    // OS cleans this up.
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [fileName],
        subject: subject,
      ),
    );
  }

  /// Null when the user cancels.
  Future<PickedFile?> pick({required List<String> extensions}) async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: 'Kori', extensions: extensions)],
    );
    if (file == null) return null;

    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }
}
