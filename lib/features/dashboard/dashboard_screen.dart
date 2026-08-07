import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chart_palette.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/currency_converter.dart';
import '../../data/daos/wallets_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/wallets.dart';
import '../budgets/budget_bar.dart';
import '../wallets/wallet_form_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kori'),
        actions: [
          IconButton(
            onPressed: () => showWalletForm(context),
            tooltip: 'Add wallet',
            icon: const Icon(Icons.add_card),
          ),
        ],
      ),
      body: switch (wallets) {
        AsyncError(:final error) => _ErrorState(error: error),
        AsyncData(:final value) when value.isEmpty => const _EmptyState(),
        AsyncData(:final value) => _WalletList(wallets: value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _WalletList extends ConsumerWidget {
  const _WalletList({required this.wallets});

  final List<WalletWithBalance> wallets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayCurrency = ref.watch(displayCurrencyProvider).value;
    final converter =
        ref.watch(exchangeRatesProvider).value ??
        const CurrencyConverter.empty();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (displayCurrency != null)
          _TotalCard(
            wallets: wallets,
            converter: converter,
            displayCurrency: displayCurrency,
          ),
        const SizedBox(height: 20),
        Text(
          'Wallets',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in wallets) ...[
          _WalletCard(entry: entry),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        const _BudgetSummary(),
      ],
    );
  }
}

/// This month's budgets, capped at three. The rest live behind "See all", so the
/// dashboard stays a glance rather than a report.
class _BudgetSummary extends ConsumerWidget {
  const _BudgetSummary();

  static const _visible = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = monthKey(DateTime.now());
    final budgets = ref.watch(budgetsForMonthProvider(month)).value ?? const [];

    if (budgets.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Set a budget'),
          subtitle: const Text('Get a warning before the money runs out'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/budgets'),
        ),
      );
    }

    final shown = budgets.take(_visible).toList();
    final hidden = budgets.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Budgets',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/budgets'),
              child: Text(hidden > 0 ? 'See all ($hidden more)' : 'See all'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                for (final budget in shown)
                  BudgetBar(
                    budget: budget,
                    onTap: () => context.push('/budgets'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.wallets,
    required this.converter,
    required this.displayCurrency,
  });

  final List<WalletWithBalance> wallets;
  final CurrencyConverter converter;
  final String displayCurrency;

  @override
  Widget build(BuildContext context) {
    final result = converter.total(
      wallets.map((w) => w.balance),
      displayCurrency,
    );
    final scheme = Theme.of(context).colorScheme;
    final mixedCurrencies =
        wallets.map((w) => w.balance.currency).toSet().length > 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mixedCurrencies ? 'Total, converted' : 'Total',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              result.total.format(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: result.total.isNegative
                    ? context.money.expense
                    : scheme.onSurface,
              ),
            ),
            if (result.unconvertible > 0) ...[
              const SizedBox(height: 10),
              // Never quietly drop a wallet from the total — say which are
              // missing and why, so the number is not silently wrong.
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${result.unconvertible} wallet'
                      '${result.unconvertible == 1 ? '' : 's'} not included — '
                      'no exchange rate set',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.entry});

  final WalletWithBalance entry;

  @override
  Widget build(BuildContext context) {
    final wallet = entry.wallet;
    final color = context.chartColorFor(wallet.color);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: () => showWalletForm(context, wallet: wallet),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconFor(wallet.icon), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wallet.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_typeLabel(wallet.type)} · ${wallet.currency}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.balance.format(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: entry.balance.isNegative
                      ? context.money.expense
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _typeLabel(WalletType type) => switch (type) {
  WalletType.cash => 'Cash',
  WalletType.bank => 'Bank',
  WalletType.mobile => 'Mobile money',
  WalletType.card => 'Card',
  WalletType.savings => 'Savings',
  WalletType.other => 'Other',
};

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Start with a wallet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Cash in your pocket, a bank account, a mobile money balance — '
              'whatever you spend from.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showWalletForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add wallet'),
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing leaves your phone.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not read your wallets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
