import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/io/import_service.dart';
import '../../data/providers.dart';
import 'data_providers.dart';

/// Shows what an import will do, and lets the user fix the column mapping first.
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({
    required this.fileName,
    required this.preview,
    super.key,
  });

  final String fileName;
  final ImportPreview preview;

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  late Map<ImportField, int> _mapping;
  ImportPlan? _plan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mapping = Map.of(widget.preview.mapping);
    _replan();
  }

  ImportPreview get _current => ImportPreview(
    headers: widget.preview.headers,
    rows: widget.preview.rows,
    mapping: _mapping,
  );

  Future<void> _replan() async {
    final wallets = ref.read(walletsProvider).value ?? const [];
    final plan = await ref
        .read(importServiceProvider)
        .plan(
          _current,
          fallbackWallet: wallets.firstOrNull?.wallet.name,
          fallbackCurrency: ref.read(displayCurrencyProvider).value ?? 'USD',
        );
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _commit() async {
    final plan = _plan;
    if (plan == null || _busy) return;
    setState(() => _busy = true);

    try {
      final imported = await ref
          .read(importServiceProvider)
          .commit(
            plan,
            fallbackCurrency: ref.read(displayCurrencyProvider).value ?? 'USD',
          );
      if (mounted) Navigator.of(context).pop(imported);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nothing imported: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;
    final valid = plan?.valid.length ?? 0;
    final invalid = plan?.invalid.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Check the import')),
      body: plan == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 140),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    widget.fileName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _Summary(valid: valid, invalid: invalid),
                if (plan.newWallets.isNotEmpty || plan.newCategories.isNotEmpty)
                  _WillCreate(
                    wallets: plan.newWallets,
                    categories: plan.newCategories,
                  ),
                const _SectionLabel('Columns'),
                for (final field in ImportField.values)
                  _MappingRow(
                    field: field,
                    headers: widget.preview.headers,
                    selected: _mapping[field],
                    onChanged: (column) {
                      setState(() {
                        if (column == null) {
                          _mapping.remove(field);
                        } else {
                          _mapping[field] = column;
                        }
                      });
                      _replan();
                    },
                  ),
                if (invalid > 0) ...[
                  const _SectionLabel('Rows that will be skipped'),
                  for (final row in plan.invalid.take(10))
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.error_outline,
                        size: 20,
                        color: scheme.error,
                      ),
                      title: Text('Line ${row.line}'),
                      subtitle: Text(row.problem ?? ''),
                    ),
                  if (invalid > 10)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'and ${invalid - 10} more',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: plan == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: valid == 0 || _busy ? null : _commit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(
                    valid == 0
                        ? 'Nothing to import'
                        : 'Import $valid transaction${valid == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.valid, required this.invalid});

  final int valid;
  final int invalid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$valid',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'will import',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (invalid > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$invalid',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: scheme.error),
                      ),
                      Text(
                        'skipped',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WillCreate extends StatelessWidget {
  const _WillCreate({required this.wallets, required this.categories});

  final Set<String> wallets;
  final Set<String> categories;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (wallets.isNotEmpty)
        '${wallets.length} wallet${wallets.length == 1 ? '' : 's'} '
            '(${wallets.join(', ')})',
      if (categories.isNotEmpty)
        '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'} '
            '(${categories.join(', ')})',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Will also create ${parts.join(' and ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.field,
    required this.headers,
    required this.selected,
    required this.onChanged,
  });

  final ImportField field;
  final List<String> headers;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(field.label + (field.required ? ' *' : '')),
      trailing: DropdownButton<int?>(
        value: selected,
        hint: const Text('Not used'),
        items: [
          const DropdownMenuItem(child: Text('Not used')),
          for (final (index, header) in headers.indexed)
            DropdownMenuItem(
              value: index,
              child: Text(header.isEmpty ? 'Column ${index + 1}' : header),
            ),
        ],
        onChanged: onChanged,
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
