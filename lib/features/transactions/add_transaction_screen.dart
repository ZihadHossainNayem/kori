import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/daos/settings_dao.dart';
import '../../data/daos/transactions_dao.dart';
import '../../data/daos/wallets_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';
import '../../data/tables/transactions.dart';
import '../budgets/budget_providers.dart';
import '../wallets/wallet_picker_sheet.dart';

/// Records a transaction, or edits [entry] when given one.
///
/// Keypad is up from the first frame and wallet and date arrive prefilled, so a
/// typical expense is amount, category, save.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.entry});

  final TransactionEntry? entry;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TransactionType _type;
  late String _digits;
  late String _date;

  int? _walletId;
  int? _destinationWalletId;
  int? _categoryId;
  final _note = TextEditingController();

  bool _saving = false;
  bool _prefilled = false;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _type = entry?.transaction.type ?? TransactionType.expense;
    _date = entry?.transaction.date ?? todayKey();
    _walletId = entry?.wallet.id;
    _destinationWalletId = entry?.destination?.id;
    _categoryId = entry?.transaction.categoryId;
    _note.text = entry?.transaction.note ?? '';
    _digits = entry == null
        ? ''
        : Money(
            entry.transaction.amountMinor,
            entry.transaction.currency,
          ).toPlainString();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Fills the wallet from last use once wallets have loaded.
  void _prefillWallet(List<WalletWithBalance> wallets) {
    if (_prefilled || wallets.isEmpty) return;
    _prefilled = true;
    if (_walletId != null) return;

    final lastUsed = ref
        .read(settingsDaoProvider)
        .read(PreferenceKeys.lastWalletId);
    lastUsed.then((value) {
      final id = int.tryParse(value ?? '');
      final exists = wallets.any((w) => w.wallet.id == id);
      if (mounted) {
        setState(() => _walletId = exists ? id : wallets.first.wallet.id);
      }
    });
  }

  String get _currency {
    final wallets = ref.read(walletsProvider).value ?? const [];
    final wallet = wallets.where((w) => w.wallet.id == _walletId).firstOrNull;
    return wallet?.wallet.currency ??
        ref.read(displayCurrencyProvider).value ??
        'USD';
  }

  Money get _amount =>
      Money.tryParse(_digits.isEmpty ? '0' : _digits, _currency) ??
      Money.zero(_currency);

  bool get _canSave =>
      !_saving &&
      _amount.minor > 0 &&
      _walletId != null &&
      (_type != TransactionType.transfer || _destinationWalletId != null);

  void _tapDigit(String key) {
    final decimals = Money.decimalsFor(_currency);
    setState(() {
      switch (key) {
        case '⌫':
          if (_digits.isNotEmpty) {
            _digits = _digits.substring(0, _digits.length - 1);
          }
        case '.':
          if (decimals > 0 && !_digits.contains('.')) {
            _digits = _digits.isEmpty ? '0.' : '$_digits.';
          }
        default:
          final dot = _digits.indexOf('.');
          // Refuse digits the currency would round away on save.
          if (dot >= 0 && _digits.length - dot - 1 >= decimals) return;
          if (_digits.replaceAll('.', '').length >= 12) return;
          _digits = _digits == '0' ? key : '$_digits$key';
      }
    });
  }

  Future<void> _pickDate() async {
    final current = parseDayKey(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 10),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = dayKey(picked));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final dao = ref.read(transactionsDaoProvider);
    final settings = ref.read(settingsDaoProvider);
    final isTransfer = _type == TransactionType.transfer;

    try {
      final entry = widget.entry;
      if (entry == null) {
        await dao.addTransaction(
          walletId: _walletId!,
          type: _type,
          amount: _amount,
          date: _date,
          categoryId: isTransfer ? null : _categoryId,
          note: _note.text,
          transferToWalletId: isTransfer ? _destinationWalletId : null,
        );
      } else {
        await dao.updateTransaction(
          entry.transaction.copyWith(
            walletId: _walletId!,
            type: _type,
            amountMinor: _amount.minor,
            currency: _amount.currency,
            date: _date,
            categoryId: Value(isTransfer ? null : _categoryId),
            transferToWalletId: Value(isTransfer ? _destinationWalletId : null),
            note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
          ),
        );
      }

      await settings.write(PreferenceKeys.lastWalletId, '$_walletId');
      // Budget alerts ride the write path; there is no background job.
      await ref.read(budgetAlertsProvider).evaluate(monthOfDayKey(_date));
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).value ?? const [];
    _prefillWallet(wallets);

    final wallet = wallets.where((w) => w.wallet.id == _walletId).firstOrNull;
    final destination = wallets
        .where((w) => w.wallet.id == _destinationWalletId)
        .firstOrNull;

    if (wallets.isEmpty) return const _NoWalletsYet();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
        title: Text(_isEditing ? 'Edit transaction' : 'Add transaction'),
      ),
      body: Column(
        children: [
          _TypeSelector(
            type: _type,
            onChanged: (type) => setState(() {
              _type = type;
              if (type == TransactionType.transfer) _categoryId = null;
            }),
          ),
          _AmountDisplay(amount: _amount, type: _type, empty: _digits.isEmpty),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _RowChips(
                  children: [
                    _MetaChip(
                      icon: iconFor(wallet?.wallet.icon ?? 'wallet'),
                      label: wallet?.wallet.name ?? 'Wallet',
                      onTap: () async {
                        final picked = await showWalletPicker(
                          context,
                          selectedId: _walletId,
                          title: 'Pay from',
                        );
                        if (picked != null) setState(() => _walletId = picked);
                      },
                    ),
                    if (_type == TransactionType.transfer)
                      _MetaChip(
                        icon: Icons.arrow_forward,
                        label: destination?.wallet.name ?? 'To wallet',
                        highlight: destination == null,
                        onTap: () async {
                          final picked = await showWalletPicker(
                            context,
                            selectedId: _destinationWalletId,
                            excludeId: _walletId,
                            title: 'Transfer to',
                          );
                          if (picked != null) {
                            setState(() => _destinationWalletId = picked);
                          }
                        },
                      ),
                    _MetaChip(
                      icon: Icons.event,
                      label: _dateLabel(_date),
                      onTap: _pickDate,
                    ),
                  ],
                ),
                if (_type != TransactionType.transfer) ...[
                  const SizedBox(height: 8),
                  _CategoryPicker(
                    type: _type == TransactionType.income
                        ? CategoryType.income
                        : CategoryType.expense,
                    selectedId: _categoryId,
                    onSelected: (id) => setState(
                      () => _categoryId = _categoryId == id ? null : id,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Note (optional)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _Keypad(
            showDecimal: Money.decimalsFor(_currency) > 0,
            onKey: _tapDigit,
            onSave: _canSave ? _save : null,
            saving: _saving,
            saveLabel: _isEditing ? 'Save changes' : 'Save',
          ),
        ],
      ),
    );
  }
}

String _dateLabel(String key) {
  final today = todayKey();
  if (key == today) return 'Today';
  final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
  if (key == yesterday) return 'Yesterday';
  return key;
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.type, required this.onChanged});

  final TransactionType type;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<TransactionType>(
        segments: const [
          ButtonSegment(
            value: TransactionType.expense,
            label: Text('Expense'),
            icon: Icon(Icons.south_west),
          ),
          ButtonSegment(
            value: TransactionType.income,
            label: Text('Income'),
            icon: Icon(Icons.north_east),
          ),
          ButtonSegment(
            value: TransactionType.transfer,
            label: Text('Move'),
            icon: Icon(Icons.swap_horiz),
          ),
        ],
        selected: {type},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.amount,
    required this.type,
    required this.empty,
  });

  final Money amount;
  final TransactionType type;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final colour = switch (type) {
      TransactionType.income => context.money.income,
      TransactionType.expense => context.money.expense,
      TransactionType.transfer => context.money.transfer,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            amount.format(),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: empty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : colour,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowChips extends StatelessWidget {
  const _RowChips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final child in children) ...[child, const SizedBox(width: 8)],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Flags something still required, like an unset transfer destination.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 18, color: highlight ? scheme.error : null),
      label: Text(label),
      side: highlight ? BorderSide(color: scheme.error) : null,
    );
  }
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.type,
    required this.selectedId,
    required this.onSelected,
  });

  final CategoryType type;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(type)).value ?? const [];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in categories)
          _CategoryChip(
            label: category.name,
            icon: iconFor(category.icon),
            colour: Color(category.color),
            selected: category.id == selectedId,
            onTap: () => onSelected(category.id),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 18, color: selected ? colour : null),
      label: Text(label),
      showCheckmark: false,
      selectedColor: colour.withValues(alpha: 0.18),
      side: selected ? BorderSide(color: colour) : null,
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.showDecimal,
    required this.onKey,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
  });

  final bool showDecimal;
  final ValueChanged<String> onKey;
  final VoidCallback? onSave;
  final bool saving;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            for (final row in rows)
              Row(
                children: [
                  for (final key in row) _KeypadKey(label: key, onTap: onKey),
                ],
              ),
            Row(
              children: [
                _KeypadKey(label: '.', onTap: onKey, enabled: showDecimal),
                _KeypadKey(label: '0', onTap: onKey),
                _KeypadKey(label: '⌫', onTap: onKey),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(saveLabel),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final ValueChanged<String> onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 56,
          child: TextButton(
            onPressed: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap(label);
                  }
                : null,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
            child: Text(label, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
      ),
    );
  }
}

class _NoWalletsYet extends StatelessWidget {
  const _NoWalletsYet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: const Text('Add transaction'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Add a wallet first',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Money has to come from somewhere before it can be recorded.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
