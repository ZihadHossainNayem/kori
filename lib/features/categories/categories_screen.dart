import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chart_palette.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';
import 'category_form_sheet.dart';

/// Categories the user can actually change, rather than the sixteen we shipped.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryType _type = CategoryType.expense;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final categories =
        ref
            .watch(
              manageableCategoriesProvider((
                type: _type,
                includeArchived: _showArchived,
              )),
            )
            .value ??
        const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(
              _showArchived ? Icons.visibility_off : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCategoryForm(context, type: _type),
        tooltip: 'Add category',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(
                  value: CategoryType.expense,
                  label: Text('Spending'),
                ),
                ButtonSegment(
                  value: CategoryType.income,
                  label: Text('Income'),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
          ),
          Expanded(
            child: categories.isEmpty
                ? _Empty(type: _type)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 140),
                    itemCount: categories.length,
                    // onReorderItem, not onReorder: it hands back an index
                    // already adjusted for the removed row.
                    onReorderItem: (from, to) {
                      HapticFeedback.mediumImpact();
                      final ids = [for (final c in categories) c.id];
                      ids.insert(to, ids.removeAt(from));
                      ref.read(categoriesDaoProvider).reorder(ids);
                    },
                    proxyDecorator: (child, index, animation) =>
                        AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final t = Curves.easeOut.transform(animation.value);
                            return Transform.scale(
                              scale: 1 + 0.03 * t,
                              child: Material(
                                elevation: 6 * t,
                                borderRadius: BorderRadius.circular(
                                  KoriRadius.small,
                                ),
                                child: child,
                              ),
                            );
                          },
                        ),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _CategoryTile(
                        key: ValueKey(category.id),
                        category: category,
                        index: index,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.index, super.key});

  final Category category;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colour = context.chartColorFor(category.color);
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: () =>
          showCategoryForm(context, type: category.type, existing: category),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: category.archived ? 0.06 : 0.16),
          borderRadius: BorderRadius.circular(KoriRadius.small),
        ),
        child: Icon(
          iconFor(category.icon),
          size: 20,
          color: category.archived ? scheme.outline : colour,
        ),
      ),
      title: Text(
        category.name,
        style: TextStyle(
          decoration: category.archived ? TextDecoration.lineThrough : null,
          color: category.archived ? scheme.outline : null,
        ),
      ),
      subtitle: category.archived ? const Text('Archived') : null,
      trailing: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_handle, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.type});

  final CategoryType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_outline, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              type == CategoryType.expense
                  ? 'No spending categories'
                  : 'No income categories',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add one, and it appears on the entry keypad straight away.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
