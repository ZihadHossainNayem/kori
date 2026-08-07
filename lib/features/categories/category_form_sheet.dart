import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chart_palette.dart';
import '../../core/icons.dart';
import '../../core/widgets/pickers.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';

Future<void> showCategoryForm(
  BuildContext context, {
  required CategoryType type,
  Category? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _CategoryForm(type: type, existing: existing),
  );
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({required this.type, this.existing});

  final CategoryType type;
  final Category? existing;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );

  late int _color = widget.existing?.color ?? palette.first;
  late String _icon = widget.existing?.icon ?? 'tag';

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final dao = ref.read(categoriesDaoProvider);
    final existing = widget.existing;

    if (existing == null) {
      await dao.createCategory(
        CategoriesCompanion.insert(
          name: _name.text.trim(),
          type: widget.type,
          color: _color,
          icon: Value(_icon),
          // New ones land at the end rather than jumping the order.
          sortOrder: const Value(500),
        ),
      );
    } else {
      await dao.updateCategory(
        existing.copyWith(name: _name.text.trim(), color: _color, icon: _icon),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleArchived() async {
    final existing = widget.existing!;
    await ref
        .read(categoriesDaoProvider)
        .setArchived(existing.id, archived: !existing.archived);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${existing.name}?'),
        content: const Text(
          'Transactions in it are kept, but lose their category and will show as '
          'Uncategorised. Any budget for it is deleted. Archiving keeps '
          'everything and just hides it from the keypad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(categoriesDaoProvider).deleteCategory(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colour = context.chartColorFor(_color);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(iconFor(_icon), color: colour, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit category' : 'New category',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        autofocus: !_isEditing,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          hintText: widget.type == CategoryType.expense
                              ? 'Coffee, school fees, medicine'
                              : 'Bonus, rent from tenant',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Give the category a name'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Colour',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ColorPicker(
                        selected: _color,
                        onSelected: (color) => setState(() => _color = color),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Icon',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      IconPicker(
                        names: categoryIconNames,
                        selected: _icon,
                        color: colour,
                        onSelected: (icon) => setState(() => _icon = icon),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        TextButton.icon(
                          onPressed: _toggleArchived,
                          icon: Icon(
                            widget.existing!.archived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                          ),
                          label: Text(
                            widget.existing!.archived
                                ? 'Unarchive'
                                : 'Archive — keeps history, hides from keypad',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _confirmDelete,
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _save,
                child: Text(_isEditing ? 'Save' : 'Add category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
