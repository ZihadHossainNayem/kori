import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/icons.dart';
import '../../core/money.dart';
import '../../data/daos/settings_dao.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../settings/settings_providers.dart';

/// Three screens: what this is, which currency, and a first wallet.
///
/// No account step, because there is no account — and the first screen says so
/// rather than leaving the user waiting for a sign-up.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _walletName = TextEditingController(text: 'Cash');
  final _openingBalance = TextEditingController();

  late String _currency = deviceDefaultCurrency();
  int _page = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _walletName.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _walletName.text.trim();
    final opening =
        Money.tryParse(_openingBalance.text, _currency) ??
        Money.zero(_currency);

    await ref
        .read(settingsDaoProvider)
        .write(PreferenceKeys.displayCurrency, _currency);

    if (name.isNotEmpty) {
      await ref
          .read(walletsDaoProvider)
          .createWallet(
            WalletsCompanion.insert(
              name: name,
              currency: _currency,
              color: palette.first,
              initialBalanceMinor: Value(opening.minor),
            ),
          );
    }

    // Written last: if anything above fails, onboarding runs again rather than
    // dropping the user into an app with no wallet.
    await ref.finishOnboarding();
  }

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  const _WelcomePage(),
                  _CurrencyPage(
                    currency: _currency,
                    onChanged: (code) => setState(() => _currency = code),
                  ),
                  _WalletPage(
                    currency: _currency,
                    name: _walletName,
                    openingBalance: _openingBalance,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < 3; index++)
                        Container(
                          width: index == _page ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: index == _page
                                ? scheme.primary
                                : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _next,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(_page < 2 ? 'Next' : 'Start'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 56, color: scheme.primary),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (child case final widget?) ...[const SizedBox(height: 32), widget],
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      icon: Icons.lock_outline,
      title: 'Kori',
      body:
          'Track where your money goes. There is no account to make and '
          'nothing to pay for — everything stays on this phone, and works with '
          'no signal.',
    );
  }
}

class _CurrencyPage extends StatelessWidget {
  const _CurrencyPage({required this.currency, required this.onChanged});

  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.language,
      title: 'Which currency?',
      body: 'Totals are shown in this one. Individual wallets can use others.',
      child: Column(
        children: [
          RadioGroup<String>(
            groupValue: currency,
            onChanged: (value) => onChanged(value ?? currency),
            child: Column(
              children: [
                for (final option in currencies.take(6))
                  RadioListTile<String>(
                    value: option.code,
                    title: Text('${option.code} · ${option.name}'),
                  ),
              ],
            ),
          ),
          ListTile(
            title: Text(
              currencies.take(6).any((o) => o.code == currency)
                  ? 'Something else'
                  : '$currency · ${currencyName(currency)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _CurrencySheet(current: currency),
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ],
      ),
    );
  }
}

class _CurrencySheet extends StatelessWidget {
  const _CurrencySheet({required this.current});

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

class _WalletPage extends StatelessWidget {
  const _WalletPage({
    required this.currency,
    required this.name,
    required this.openingBalance,
  });

  final String currency;
  final TextEditingController name;
  final TextEditingController openingBalance;

  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Where do you spend from?',
      body: 'One wallet is enough to start. Add more whenever you like.',
      child: Column(
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Wallet name',
              hintText: 'Cash, bKash, Salary account',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: openingBalance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'How much is in it?',
              prefixText: '$currency ',
              helperText: 'Leave blank to start from zero',
            ),
          ),
        ],
      ),
    );
  }
}
