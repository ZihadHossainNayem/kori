import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/daos/recurring_dao.dart';
import '../../data/providers.dart';
import 'recurring_form_sheet.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Repeating')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showRecurringForm(context),
        tooltip: 'Add repeat',
        child: const Icon(Icons.add),
      ),
      body: switch (rules) {
        AsyncError(:final error) => Center(child: Text('$error')),
        AsyncData(:final value) when value.isEmpty => const _EmptyRules(),
        AsyncData(:final value) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _RuleTile(details: value[index]),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.details});

  final RecurringRuleDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = details.rule;
    final scheme = Theme.of(context).colorScheme;
    final isIncome = rule.type == 'income';
    final colour = isIncome ? context.money.income : context.money.expense;
    final iconColour = Color(
      details.category?.color ?? scheme.outline.toARGB32(),
    );

    return ListTile(
      onTap: () => showRecurringForm(context, existing: details),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (rule.active ? iconColour : scheme.outline).withValues(
            alpha: 0.16,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          iconFor(details.category?.icon ?? 'tag'),
          size: 20,
          color: rule.active ? iconColour : scheme.outline,
        ),
      ),
      title: Text(
        rule.note?.isNotEmpty == true
            ? rule.note!
            : details.category?.name ?? (isIncome ? 'Income' : 'Expense'),
        style: TextStyle(
          decoration: rule.active ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        rule.active
            ? '${frequencyLabel(rule.frequency)} · next ${rule.nextDate} · '
                  '${details.wallet.name}'
            : 'Paused · ${details.wallet.name}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isIncome
                ? '+${details.amount.format()}'
                : '-${details.amount.format()}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: rule.active ? colour : scheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          Switch(
            value: rule.active,
            onChanged: (value) => ref
                .read(recurringDaoProvider)
                .setActive(rule.id, active: value),
          ),
        ],
      ),
    );
  }
}

class _EmptyRules extends StatelessWidget {
  const _EmptyRules();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.autorenew, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Nothing repeating yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Rent, salary, subscriptions — record them once and Kori enters '
              'them for you, even if the phone was off.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showRecurringForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add a repeat'),
            ),
          ],
        ),
      ),
    );
  }
}
