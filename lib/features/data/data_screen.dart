import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/io/backup_service.dart';
import '../../data/io/export_service.dart';
import '../../data/io/import_service.dart';
import '../../data/providers.dart';
import 'data_providers.dart';
import 'import_preview_screen.dart';

/// Export, import, backup and restore.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      _say('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export({required bool asXlsx}) async {
    final exporter = ref.read(exportServiceProvider);
    final bytes = asXlsx ? await exporter.toXlsx() : await exporter.toCsv();
    await ref
        .read(fileTransferProvider)
        .share(
          bytes,
          fileName: ExportService.fileName(asXlsx ? 'xlsx' : 'csv'),
          subject: 'Kori export',
        );
  }

  Future<void> _import() async {
    final picked = await ref
        .read(fileTransferProvider)
        .pick(extensions: ['csv', 'xlsx']);
    if (picked == null) return;

    final preview = ImportService.preview(picked.bytes, fileName: picked.name);
    if (!mounted) return;

    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) =>
            ImportPreviewScreen(fileName: picked.name, preview: preview),
      ),
    );
    if (imported != null && imported > 0) {
      _say('Imported $imported transaction${imported == 1 ? '' : 's'}');
    }
  }

  Future<void> _backup() async {
    final passphrase = await _askPassphrase(
      title: 'Encrypt this backup?',
      message:
          'A passphrase keeps the file unreadable if it ends up somewhere '
          'it should not. Without one, anyone who opens the file sees '
          'everything.',
      confirmLabel: 'Back up',
      allowEmpty: true,
    );
    if (passphrase == null) return;

    final database = ref.read(databaseProvider);
    final bytes = await ref
        .read(backupServiceProvider)
        .pack(
          database: await readDatabaseBytes(database),
          schemaVersion: database.schemaVersion,
          passphrase: passphrase.isEmpty ? null : passphrase,
        );

    await ref
        .read(fileTransferProvider)
        .share(
          bytes,
          fileName: BackupService.fileName(encrypted: passphrase.isNotEmpty),
          subject: 'Kori backup',
        );
  }

  Future<void> _restore() async {
    final picked = await ref
        .read(fileTransferProvider)
        .pick(extensions: ['db', 'enc', 'sqlite']);
    if (picked == null) return;

    final backup = ref.read(backupServiceProvider);
    final info = backup.inspect(picked.bytes);

    String? passphrase;
    if (info.encrypted) {
      if (!mounted) return;
      passphrase = await _askPassphrase(
        title: 'Passphrase',
        message: 'This backup is encrypted.',
        confirmLabel: 'Restore',
        allowEmpty: false,
      );
      if (passphrase == null) return;
    }

    final database = await backup.unpack(
      picked.bytes,
      passphrase: passphrase,
      supportedSchemaVersion: ref.read(databaseProvider).schemaVersion,
    );

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
          'Restoring overwrites the wallets, transactions and budgets on this '
          'phone. Back up first if you are not sure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(restoreControllerProvider).restore(database);
    _say('Restored');
  }

  /// Empty string means "no passphrase" when [allowEmpty]; null means cancelled.
  Future<String?> _askPassphrase({
    required String title,
    required String message,
    required String confirmLabel,
    required bool allowEmpty,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                labelText: allowEmpty ? 'Passphrase (optional)' : 'Passphrase',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              if (!allowEmpty && value.isEmpty) return;
              Navigator.of(context).pop(value);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your data'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionLabel('Take it with you'),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export spreadsheet'),
            subtitle: const Text(
              'Everything, as .xlsx — opens in any spreadsheet',
            ),
            onTap: _busy ? null : () => _run(() => _export(asXlsx: true)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Export CSV'),
            subtitle: const Text('Transactions only, as plain text'),
            onTap: _busy ? null : () => _run(() => _export(asXlsx: false)),
          ),
          const _SectionLabel('Bring data in'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import'),
            subtitle: const Text(
              'From a CSV or spreadsheet — you see what will happen first',
            ),
            onTap: _busy ? null : () => _run(_import),
          ),
          const _SectionLabel('Backup'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Back up'),
            subtitle: const Text(
              'One file holding everything, optionally encrypted',
            ),
            onTap: _busy ? null : () => _run(_backup),
          ),
          ListTile(
            leading: Icon(Icons.restore, color: scheme.error),
            title: const Text('Restore from backup'),
            subtitle: const Text('Replaces everything on this phone'),
            onTap: _busy ? null : () => _run(_restore),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Files go out through the share sheet, so you choose where they '
              'land. Kori uploads nothing.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
