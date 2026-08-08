import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/chart_palette.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/animated_money.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/currency_converter.dart';
import '../../data/daos/transactions_dao.dart';
import '../../data/daos/wallets_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/transactions.dart';
import '../../data/tables/wallets.dart';
import '../budgets/budget_bar.dart';
import '../transactions/add_transaction_screen.dart';
import '../wallets/wallet_form_sheet.dart';

// Hoisted: DateFormat parses its pattern on construction.
final _todayTitle = DateFormat('EEEE, d MMMM');
final _recentDate = DateFormat('d MMM');

/// Five is a glance; the rest live behind "See all" on History.
final _recentEntriesProvider = StreamProvider<List<TransactionEntry>>(
  (ref) => ref.watch(transactionsDaoProvider).watchEntries(limit: 5),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider);

    // No AppBar: this is the one screen people open dozens of times a week,
    // and it had nothing worth the space — a wordmark they already know and
    // an "add wallet" action they need maybe twice a year. The balance is the
    // header now.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (wallets) {
          AsyncError(:final error) => _ErrorState(error: error),
          AsyncData(:final value) when value.isEmpty => const _EmptyState(),
          AsyncData(:final value) => _WalletList(wallets: value),
          _ => const LoadingSkeleton(),
        },
      ),
    );
  }
}

String _greeting() => switch (DateTime.now().hour) {
  < 12 => 'Good morning',
  < 17 => 'Good afternoon',
  _ => 'Good evening',
};

class _WalletList extends ConsumerWidget {
  const _WalletList({required this.wallets});

  final List<WalletWithBalance> wallets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayCurrency = ref.watch(displayCurrencyProvider).value;
    final converter =
        ref.watch(exchangeRatesProvider).value ??
        const CurrencyConverter.empty();

    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        Text(
          _greeting(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          _todayTitle.format(DateTime.now()),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        if (displayCurrency != null)
          _TotalCard(
            wallets: wallets,
            converter: converter,
            displayCurrency: displayCurrency,
          ),
        const SizedBox(height: 24),
        Text(
          'Wallets',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final entry in wallets) ...[
          _WalletCard(entry: entry),
          const SizedBox(height: 10),
        ],
        const _AddWalletTile(),
        const SizedBox(height: 20),
        const _BudgetSummary(),
        const SizedBox(height: 20),
        const _RecentActivity(),
      ],
    );
  }
}

/// The last few transactions, so recording one closes its own feedback loop
/// without a trip to History. Capped at five; nothing shown at all once there
/// is nothing yet to report.
class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_recentEntriesProvider).value ?? const [];
    if (entries.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/transactions'),
              child: const Text('See all'),
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              for (final (index, entry) in entries.indexed) ...[
                _RecentActivityRow(entry: entry),
                if (index != entries.length - 1)
                  Divider(height: 1, indent: 66, color: scheme.outlineVariant),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.entry});

  final TransactionEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transaction = entry.transaction;
    final isTransfer = transaction.type == TransactionType.transfer;

    final colour = switch (transaction.type) {
      TransactionType.income => context.money.income,
      TransactionType.expense => context.money.expense,
      TransactionType.transfer => context.money.transfer,
    };
    final iconColour = isTransfer
        ? colour
        : Color(entry.category?.color ?? scheme.outline.toARGB32());
    final icon = isTransfer
        ? Icons.swap_horiz
        : iconFor(entry.category?.icon ?? 'tag');

    final title = isTransfer
        ? '${entry.wallet.name} → ${entry.destination?.name ?? '—'}'
        : entry.category?.name ?? 'Uncategorised';

    return ListTile(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => AddTransactionScreen(entry: entry),
        ),
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColour.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(KoriRadius.small),
        ),
        child: Icon(icon, size: 20, color: iconColour),
      ),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _recentDate.format(parseDayKey(transaction.date)),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        isTransfer
            ? entry.amount.format()
            : entry.signedAmount.isNegative
            ? entry.signedAmount.format()
            : '+${entry.signedAmount.format()}',
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: colour, fontWeight: FontWeight.w600)
            .tabular,
      ),
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
            AnimatedMoneyText(
              amount: result.total,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
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
        borderRadius: BorderRadius.circular(KoriRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(KoriRadius.small),
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
              AnimatedMoneyText(
                amount: entry.balance,
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

/// A quiet, outlined tile at the end of the list rather than a top-bar icon —
/// this is a rare action, not one that deserves prime real estate on the
/// screen people open the most.
class _AddWalletTile extends StatelessWidget {
  const _AddWalletTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => showWalletForm(context),
      borderRadius: BorderRadius.circular(KoriRadius.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KoriRadius.medium),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Add wallet',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
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
