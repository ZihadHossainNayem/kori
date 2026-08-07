import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../data/currency_converter.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// A pair the totals need but cannot resolve.
class MissingPair {
  const MissingPair({required this.from, required this.to});

  final String from;
  final String to;
}

final ratesProvider = StreamProvider<List<ExchangeRate>>(
  (ref) => ref.watch(settingsDaoProvider).watchRates(),
);

/// Pairs implied by the user's own wallets, which the converter cannot yet do.
///
/// Asking for exactly these is the difference between a rates screen that helps
/// and one that expects the user to work out what is missing.
final missingPairsProvider = Provider<List<MissingPair>>((ref) {
  final display = ref.watch(displayCurrencyProvider).value;
  final wallets = ref.watch(walletsProvider).value ?? const [];
  final converter =
      ref.watch(exchangeRatesProvider).value ?? const CurrencyConverter.empty();
  if (display == null) return const [];

  final needed = <String>{for (final wallet in wallets) wallet.wallet.currency}
    ..remove(display);

  return [
    for (final currency in needed)
      if (converter.rate(currency, display) == null)
        MissingPair(from: currency, to: display),
  ];
});

class RatesScreen extends ConsumerWidget {
  const RatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = ref.watch(ratesProvider).value ?? const [];
    final missing = ref.watch(missingPairsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Exchange rates')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showRateForm(context),
        tooltip: 'Add rate',
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Kori has no internet permission, so rates are the ones you enter. '
              'Nothing is fetched and nothing is sent.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (missing.isNotEmpty) ...[
            const _SectionLabel('Your totals need these'),
            for (final pair in missing)
              ListTile(
                leading: Icon(
                  Icons.warning_amber_outlined,
                  color: scheme.error,
                ),
                title: Text('1 ${pair.from} = ? ${pair.to}'),
                subtitle: Text(
                  'Without it, ${pair.from} wallets are left out of the total',
                ),
                trailing: const Icon(Icons.add),
                onTap: () =>
                    showRateForm(context, from: pair.from, to: pair.to),
              ),
          ],
          if (rates.isEmpty && missing.isEmpty)
            const _NoRatesNeeded()
          else if (rates.isNotEmpty) ...[
            const _SectionLabel('Rates you have set'),
            for (final rate in rates) _RateTile(rate: rate),
          ],
        ],
      ),
    );
  }
}

class _RateTile extends ConsumerWidget {
  const _RateTile({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final age = _age(rate.fetchedAt);
    final stale = _isStale(rate.fetchedAt);

    return ListTile(
      title: Text('1 ${rate.base} = ${_trim(rate.rate)} ${rate.quote}'),
      subtitle: Text(
        age == null ? 'Entered by hand' : 'Set $age',
        style: stale ? TextStyle(color: scheme.error) : null,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Remove',
        onPressed: () =>
            ref.read(settingsDaoProvider).deleteRate(rate.base, rate.quote),
      ),
      onTap: () => showRateForm(
        context,
        from: rate.base,
        to: rate.quote,
        existing: rate.rate,
      ),
    );
  }
}

class _NoRatesNeeded extends StatelessWidget {
  const _NoRatesNeeded();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Nothing to convert',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Every wallet already uses your display currency. Add a rate here if '
            'you start keeping money in another one.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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

/// Rates entered by hand drift out of date, so every one shows its age and says
/// so once it is old enough to mislead.
String? _age(DateTime? recorded) {
  if (recorded == null) return null;
  final days = DateTime.now().difference(recorded).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  final months = (days / 30).floor();
  return months == 1 ? 'a month ago' : '$months months ago';
}

bool _isStale(DateTime? recorded) =>
    recorded != null && DateTime.now().difference(recorded).inDays >= 90;

String _trim(double rate) {
  final text = rate.toStringAsFixed(6);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

Future<void> showRateForm(
  BuildContext context, {
  String? from,
  String? to,
  double? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _RateForm(from: from, to: to, existing: existing),
  );
}

class _RateForm extends ConsumerStatefulWidget {
  const _RateForm({this.from, this.to, this.existing});

  final String? from;
  final String? to;
  final double? existing;

  @override
  ConsumerState<_RateForm> createState() => _RateFormState();
}

class _RateFormState extends ConsumerState<_RateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rate = TextEditingController(
    text: widget.existing == null ? '' : _trim(widget.existing!),
  );

  late final String _display =
      widget.to ?? ref.read(displayCurrencyProvider).value ?? 'USD';
  late String _to = _display;

  /// Defaults to a currency the user actually holds, and never to the display
  /// currency — a pair with the same code on both sides can never be saved.
  late String _from = widget.from ?? _firstOtherCurrency();

  String _firstOtherCurrency() {
    final wallets = ref.read(walletsProvider).value ?? const [];
    for (final wallet in wallets) {
      if (wallet.wallet.currency != _display) return wallet.wallet.currency;
    }
    return currencies.firstWhere((option) => option.code != _display).code;
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(settingsDaoProvider)
        .upsertRate(
          base: _from,
          quote: _to,
          rate: double.parse(_rate.text.trim()),
          // Recorded, not fetched — but the date is what tells the user it is stale.
          fetchedAt: DateTime.now(),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CurrencyList(current: isFrom ? _from : _to),
    );
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
  }

  @override
  Widget build(BuildContext context) {
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
                'Exchange rate',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('1 '),
                      ActionChip(
                        label: Text(_from),
                        onPressed: () => _pick(isFrom: true),
                      ),
                      const Text('  =  '),
                      Expanded(
                        child: TextFormField(
                          controller: _rate,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(hintText: '120.00'),
                          validator: (value) {
                            final parsed = double.tryParse(
                              (value ?? '').trim(),
                            );
                            if (parsed == null) return 'Enter a number';
                            if (parsed <= 0) return 'Must be above zero';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(_to),
                        onPressed: () => _pick(isFrom: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The reverse direction is worked out from this, so one entry '
                    'per pair is enough.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: FilledButton(
                onPressed: _from == _to ? null : _save,
                child: Text(_from == _to ? 'Pick two currencies' : 'Save rate'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyList extends StatelessWidget {
  const _CurrencyList({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.builder(
        itemCount: currencies.length,
        itemBuilder: (context, index) {
          final option = currencies[index];
          return ListTile(
            leading: SizedBox(
              width: 44,
              child: Text(
                option.code,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            title: Text(option.name),
            trailing: option.code == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(option.code),
          );
        },
      ),
    );
  }
}
