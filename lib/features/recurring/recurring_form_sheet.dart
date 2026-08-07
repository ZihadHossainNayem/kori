import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chart_palette.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/money.dart';
import '../../core/recurrence.dart';
import '../../data/daos/recurring_dao.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';
import '../wallets/wallet_picker_sheet.dart';

/// Creates a recurring rule, or edits [existing].
Future<void> showRecurringForm(
  BuildContext context, {
  RecurringRuleDetails? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _RecurringForm(existing: existing),
  );
}

class _RecurringForm extends ConsumerStatefulWidget {
  const _RecurringForm({this.existing});

  final RecurringRuleDetails? existing;

  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late String _type;
  late RecurrenceFrequency _frequency;
  late String _nextDate;
  int? _walletId;
  int? _categoryId;
  String? _endDate;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.rule.type ?? 'expense';
    _frequency = existing?.rule.frequency ?? RecurrenceFrequency.monthly;
    _nextDate = existing?.rule.nextDate ?? todayKey();
    _walletId = existing?.wallet.id;
    _categoryId = existing?.rule.categoryId;
    _endDate = existing?.rule.endDate;
    _amount = TextEditingController(
      text: existing == null ? '' : existing.amount.toPlainString(),
    );
    _note = TextEditingController(text: existing?.rule.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _currency {
    final wallets = ref.read(walletsProvider).value ?? const [];
    final wallet = wallets.where((w) => w.wallet.id == _walletId).firstOrNull;
    return wallet?.wallet.currency ??
        ref.read(displayCurrencyProvider).value ??
        'USD';
  }

  Future<void> _pickDate({required bool isEnd}) async {
    final initial = parseDayKey(isEnd ? (_endDate ?? _nextDate) : _nextDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(DateTime.now().year + 20),
    );
    if (picked == null) return;
    setState(() {
      if (isEnd) {
        _endDate = dayKey(picked);
      } else {
        _nextDate = dayKey(picked);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_walletId == null) return;

    final amount = Money.tryParse(_amount.text, _currency)!;
    final note = _note.text.trim();
    final dao = ref.read(recurringDaoProvider);
    // The anchor is the day of the first occurrence, reapplied every period.
    final anchorDay = parseDayKey(_nextDate).day;

    if (_isEditing) {
      await dao.updateRule(
        widget.existing!.rule.copyWith(
          walletId: _walletId!,
          categoryId: Value(_categoryId),
          type: _type,
          amountMinor: amount.minor,
          currency: amount.currency,
          note: Value(note.isEmpty ? null : note),
          frequency: _frequency,
          anchorDay: anchorDay,
          nextDate: _nextDate,
          endDate: Value(_endDate),
        ),
      );
    } else {
      await dao.createRule(
        RecurringRulesCompanion.insert(
          walletId: _walletId!,
          type: _type,
          amountMinor: amount.minor,
          currency: amount.currency,
          frequency: _frequency,
          nextDate: _nextDate,
          categoryId: Value(_categoryId),
          note: Value(note.isEmpty ? null : note),
          anchorDay: Value(anchorDay),
          endDate: Value(_endDate),
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(recurringDaoProvider).deleteRule(widget.existing!.rule.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).value ?? const [];
    _walletId ??= wallets.firstOrNull?.wallet.id;
    final wallet = wallets.where((w) => w.wallet.id == _walletId).firstOrNull;

    final categories =
        ref
            .watch(
              categoriesProvider(
                _type == 'income' ? CategoryType.income : CategoryType.expense,
              ),
            )
            .value ??
        const [];

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
                _isEditing ? 'Edit repeat' : 'New repeat',
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
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'expense',
                            label: Text('Expense'),
                          ),
                          ButtonSegment(value: 'income', label: Text('Income')),
                        ],
                        selected: {_type},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) => setState(() {
                          _type = selection.first;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
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
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          hintText: 'Rent, salary, Netflix',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<RecurrenceFrequency>(
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: 'Repeats'),
                        items: [
                          for (final frequency in RecurrenceFrequency.values)
                            DropdownMenuItem(
                              value: frequency,
                              child: Text(frequencyLabel(frequency)),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _frequency = value ?? _frequency),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: Icon(
                              iconFor(wallet?.wallet.icon ?? 'wallet'),
                              size: 18,
                            ),
                            label: Text(wallet?.wallet.name ?? 'Wallet'),
                            onPressed: () async {
                              final picked = await showWalletPicker(
                                context,
                                selectedId: _walletId,
                              );
                              if (picked != null) {
                                setState(() => _walletId = picked);
                              }
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.event, size: 18),
                            label: Text('Starts $_nextDate'),
                            onPressed: () => _pickDate(isEnd: false),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.event_busy, size: 18),
                            label: Text(_endDate ?? 'No end date'),
                            onPressed: () => _pickDate(isEnd: true),
                          ),
                          if (_endDate != null)
                            ActionChip(
                              avatar: const Icon(Icons.clear, size: 18),
                              label: const Text('Clear end'),
                              onPressed: () => setState(() => _endDate = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Category',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categories)
                            FilterChip(
                              avatar: Icon(
                                iconFor(category.icon),
                                size: 18,
                                color: context.chartColorFor(category.color),
                              ),
                              label: Text(category.name),
                              selected: _categoryId == category.id,
                              showCheckmark: false,
                              onSelected: (selected) => setState(
                                () =>
                                    _categoryId = selected ? category.id : null,
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
                          label: const Text('Delete repeat'),
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
                onPressed: wallets.isEmpty ? null : _save,
                child: Text(_isEditing ? 'Save' : 'Create repeat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String frequencyLabel(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.daily => 'Every day',
  RecurrenceFrequency.weekly => 'Every week',
  RecurrenceFrequency.monthly => 'Every month',
  RecurrenceFrequency.yearly => 'Every year',
};
