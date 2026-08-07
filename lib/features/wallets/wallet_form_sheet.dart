import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/icons.dart';
import '../../core/money.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/tables/wallets.dart';

/// Creates a wallet, or edits [wallet] when given one.
Future<void> showWalletForm(BuildContext context, {Wallet? wallet}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Without the root navigator the sheet opens inside the tab's navigator,
    // which sits within the shell Scaffold — leaving the FAB painted on top of
    // the sheet's own save button.
    useRootNavigator: true,
    builder: (_) => _WalletForm(wallet: wallet),
  );
}

class _WalletForm extends ConsumerStatefulWidget {
  const _WalletForm({this.wallet});

  final Wallet? wallet;

  @override
  ConsumerState<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends ConsumerState<_WalletForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _openingBalance;

  late String _currency;
  late WalletType _type;
  late int _color;
  late String _icon;

  /// Null until counted; the currency field stays locked until we know.
  int? _existingTransactions;

  bool get _isEditing => widget.wallet != null;
  bool get _currencyLocked => (_existingTransactions ?? 1) > 0 && _isEditing;

  @override
  void initState() {
    super.initState();
    final wallet = widget.wallet;
    _name = TextEditingController(text: wallet?.name ?? '');
    _currency = wallet?.currency ?? ref.read(displayCurrencyProvider).value ?? 'USD';
    _openingBalance = TextEditingController(
      text: wallet == null
          ? ''
          : Money(wallet.initialBalanceMinor, wallet.currency).toPlainString(),
    );
    _type = wallet?.type ?? WalletType.cash;
    _color = wallet?.color ?? palette.first;
    _icon = wallet?.icon ?? 'wallet';

    if (wallet != null) {
      _countTransactions(wallet.id);
    } else {
      _existingTransactions = 0;
    }
  }

  Future<void> _countTransactions(int walletId) async {
    final count = await ref.read(walletsDaoProvider).transactionCount(walletId);
    if (mounted) setState(() => _existingTransactions = count);
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final opening =
        Money.tryParse(_openingBalance.text, _currency) ?? Money.zero(_currency);
    final dao = ref.read(walletsDaoProvider);
    final wallet = widget.wallet;

    if (wallet == null) {
      await dao.createWallet(
        WalletsCompanion.insert(
          name: _name.text.trim(),
          currency: _currency,
          color: _color,
          type: Value(_type),
          icon: Value(_icon),
          initialBalanceMinor: Value(opening.minor),
        ),
      );
    } else {
      await dao.updateWallet(
        wallet.copyWith(
          name: _name.text.trim(),
          currency: _currency,
          color: _color,
          type: _type,
          icon: _icon,
          initialBalanceMinor: opening.minor,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final wallet = widget.wallet!;
    final count = _existingTransactions ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${wallet.name}?'),
        content: Text(
          count == 0
              ? 'This wallet has no transactions.'
              : 'This also deletes $count transaction${count == 1 ? '' : 's'} '
                  'recorded in it. Archiving keeps the history instead.',
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
    await ref.read(walletsDaoProvider).deleteWallet(wallet.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleArchived() async {
    final wallet = widget.wallet!;
    await ref
        .read(walletsDaoProvider)
        .setArchived(wallet.id, archived: !wallet.archived);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    // Fields scroll; the save action stays pinned to the bottom. On a long form
    // the primary action must not sit below the fold.
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _isEditing ? 'Edit wallet' : 'New wallet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        autofocus: !_isEditing,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'Cash, bKash, Salary account',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Give the wallet a name'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<WalletType>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: [
                          for (final type in WalletType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(_typeLabel(type)),
                            ),
                        ],
                        onChanged: (type) =>
                            setState(() => _type = type ?? _type),
                      ),
                      const SizedBox(height: 16),
                      _CurrencyField(
                        currency: _currency,
                        locked: _currencyLocked,
                        onChanged: (code) => setState(() => _currency = code),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _openingBalance,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Opening balance',
                          hintText: '0',
                          helperText: 'What is in the wallet right now',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          return Money.tryParse(value, _currency) == null
                              ? 'Not a number'
                              : null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Colour',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _ColorPicker(
                        selected: _color,
                        onSelected: (color) => setState(() => _color = color),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Icon',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _IconPicker(
                        names: walletIconNames,
                        selected: _icon,
                        color: Color(_color),
                        onSelected: (icon) => setState(() => _icon = icon),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        TextButton.icon(
                          onPressed: _toggleArchived,
                          icon: Icon(
                            widget.wallet!.archived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                          ),
                          label: Text(
                            widget.wallet!.archived ? 'Unarchive' : 'Archive',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _confirmDelete,
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
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
                child: Text(_isEditing ? 'Save' : 'Create wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _typeLabel(WalletType type) => switch (type) {
      WalletType.cash => 'Cash',
      WalletType.bank => 'Bank account',
      WalletType.mobile => 'Mobile money',
      WalletType.card => 'Card',
      WalletType.savings => 'Savings',
      WalletType.other => 'Other',
    };

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.currency,
    required this.locked,
    required this.onChanged,
  });

  final String currency;
  final bool locked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Currency',
        helperText: locked
            ? 'Locked: this wallet already has transactions'
            : null,
      ),
      child: InkWell(
        onTap: locked
            ? null
            : () async {
                final picked = await _showCurrencyPicker(context, currency);
                if (picked != null) onChanged(picked);
              },
        child: Row(
          children: [
            Expanded(
              child: Text('$currency · ${currencyName(currency)}'),
            ),
            Icon(
              locked ? Icons.lock_outline : Icons.expand_more,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showCurrencyPicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _CurrencyPicker(current: current),
  );
}

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker({required this.current});

  final String current;

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches =
        currencies.where((option) => option.matches(_query)).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search currency',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final option = matches[index];
                return ListTile(
                  title: Text(option.name),
                  leading: SizedBox(
                    width: 44,
                    child: Text(
                      option.code,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  trailing: option.code == widget.current
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(option.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in palette)
          Semantics(
            selected: color == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(color),
              customBorder: const CircleBorder(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: color == selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: color == selected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.names,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final List<String> names;
  final String selected;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final name in names)
          Semantics(
            selected: name == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(name),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: name == selected
                      ? color.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: name == selected
                      ? Border.all(color: color, width: 2)
                      : null,
                ),
                child: Icon(
                  iconFor(name),
                  size: 22,
                  color: name == selected ? color : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
