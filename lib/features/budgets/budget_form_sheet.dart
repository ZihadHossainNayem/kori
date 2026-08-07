import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/money.dart';
import '../../data/daos/budgets_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';

/// Sets a budget for [monthKey], or edits [existing].
Future<void> showBudgetForm(
  BuildContext context, {
  required String monthKey,
  BudgetProgress? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _BudgetForm(monthKey: monthKey, existing: existing),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.monthKey, this.existing});

  final String monthKey;
  final BudgetProgress? existing;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late int? _categoryId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
    _amount = TextEditingController(
      text: widget.existing?.limit.toPlainString() ?? '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String get _currency =>
      widget.existing?.limit.currency ??
      ref.read(displayCurrencyProvider).value ??
      'USD';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final limit = Money.tryParse(_amount.text, _currency)!;

    await ref
        .read(budgetsDaoProvider)
        .setBudget(
          monthKey: widget.monthKey,
          limit: limit,
          categoryId: _categoryId,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(budgetsDaoProvider).deleteBudget(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final expenses =
        ref.watch(categoriesProvider(CategoryType.expense)).value ?? const [];

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
              child: Text(
                _isEditing ? 'Edit budget' : 'New budget',
                style: Theme.of(context).textTheme.titleLarge,
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
                        controller: _amount,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Monthly limit',
                          prefixText: '$_currency ',
                        ),
                        validator: (value) {
                          final parsed = Money.tryParse(value ?? '', _currency);
                          if (parsed == null) return 'Enter an amount';
                          if (parsed.minor <= 0) {
                            return 'Must be more than zero';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Applies to',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            avatar: const Icon(Icons.all_inclusive, size: 18),
                            label: const Text('Everything'),
                            selected: _categoryId == null,
                            showCheckmark: false,
                            // Locked while editing: moving a budget between
                            // categories would collide with an existing one.
                            onSelected: _isEditing
                                ? null
                                : (_) => setState(() => _categoryId = null),
                          ),
                          for (final category in expenses)
                            FilterChip(
                              avatar: Icon(
                                iconFor(category.icon),
                                size: 18,
                                color: Color(category.color),
                              ),
                              label: Text(category.name),
                              selected: _categoryId == category.id,
                              showCheckmark: false,
                              onSelected: _isEditing
                                  ? null
                                  : (_) => setState(
                                      () => _categoryId = category.id,
                                    ),
                            ),
                        ],
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        TextButton.icon(
                          onPressed: _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove budget'),
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
                child: Text(_isEditing ? 'Save' : 'Set budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
