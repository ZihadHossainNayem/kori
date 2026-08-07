import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currencies.dart';
import '../../data/daos/settings_dao.dart';
import '../../data/providers.dart';
import '../budgets/budget_providers.dart';
import '../rates/rates_screen.dart';
import 'settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayCurrency = ref.watch(displayCurrencyProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _SectionLabel('Money'),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Budgets'),
            subtitle: const Text('Monthly caps, per category or overall'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/budgets'),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Repeating'),
            subtitle: const Text('Rent, salary, subscriptions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/recurring'),
          ),
          const _RatesTile(),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Display currency'),
            subtitle: Text(
              displayCurrency == null
                  ? 'Loading'
                  : '$displayCurrency · ${currencyName(displayCurrency)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickDisplayCurrency(context, ref),
          ),
          const _SectionLabel('This phone'),
          const _ThemeTile(),
          const _AppLockTile(),
          const _SectionLabel('Alerts'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Allow budget alerts'),
            subtitle: const Text(
              'Warns at 80% and again when a budget is spent',
            ),
            onTap: () async {
              final granted = await ref
                  .read(budgetAlertsProvider)
                  .requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    granted
                        ? 'Budget alerts are on'
                        : 'Alerts declined. Budgets still work, quietly.',
                  ),
                ),
              );
            },
          ),
          const _SectionLabel('Your data'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export and backup'),
            subtitle: const Text('Spreadsheet, CSV, or one encrypted file'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/data'),
          ),
          const _SectionLabel('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Nothing leaves your phone'),
            subtitle: Text(
              'No account, no server, no tracking. Kori has no internet '
              'permission at all, so it cannot send or fetch anything.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDisplayCurrency(BuildContext context, WidgetRef ref) async {
    final current = ref.read(displayCurrencyProvider).value ?? 'USD';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _CurrencyList(current: current),
    );
    if (picked == null) return;
    await ref
        .read(settingsDaoProvider)
        .write(PreferenceKeys.displayCurrency, picked);
  }
}

class _RatesTile extends ConsumerWidget {
  const _RatesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingPairsProvider).length;

    return ListTile(
      leading: const Icon(Icons.currency_exchange),
      title: const Text('Exchange rates'),
      subtitle: Text(
        missing == 0
            ? 'For wallets in another currency'
            : '$missing needed for your totals',
      ),
      trailing: missing == 0
          ? const Icon(Icons.chevron_right)
          : Badge(label: Text('$missing')),
      onTap: () => context.push('/rates'),
    );
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Appearance'),
      subtitle: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => ref.setThemeMode(selection.first),
      ),
    );
  }
}

class _AppLockTile extends ConsumerWidget {
  const _AppLockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(appLockEnabledProvider).value ?? false;

    return SwitchListTile(
      value: enabled,
      onChanged: (value) => ref.setAppLock(enabled: value),
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Lock the app'),
      subtitle: const Text('Ask for your fingerprint or face on opening'),
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
