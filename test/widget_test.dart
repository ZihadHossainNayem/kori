import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/app.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/providers.dart';
import 'package:kori/features/settings/settings_providers.dart';

/// Pumps the app on a phone-sized surface against a throwaway in-memory
/// database, runs [body], then disposes the tree inside the test.
///
/// The default 800x600 window is shorter than any phone and pushed pinned
/// buttons off screen, where taps silently missed. Disposing early lets drift's
/// zero-duration stream cleanup timer fire while fake time still advances.
void appTest(
  String description,
  Future<void> Function(WidgetTester) body, {
  bool onboarded = true,
}) {
  testWidgets(description, (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = KoriDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          // A fresh database has never seen onboarding, so tests of the app
          // itself say they are past it.
          if (onboarded)
            onboardingSeenProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: const KoriApp(),
      ),
    );
    await tester.pumpAndSettle();

    await body(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// Creates a wallet through the UI, the way a new user would.
Future<void> createWallet(
  WidgetTester tester, {
  String name = 'Cash',
  String opening = '1000',
}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Add wallet'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Name'), name);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Opening balance'),
    opening,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Create wallet'));
  await tester.pumpAndSettle();
}

Future<void> tapKeys(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.widgetWithText(TextButton, digit));
    await tester.pump();
  }
}

void main() {
  appTest('opens straight into the wallet tab', (tester) async {
    // No login wall: the first screen is the app itself.
    expect(find.text('Kori'), findsOneWidget);
    for (final tab in ['Home', 'History', 'Insights', 'Settings']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  appTest('a fresh install invites you to add a wallet', (tester) async {
    expect(find.text('Start with a wallet'), findsOneWidget);
    expect(find.text('Nothing leaves your phone.'), findsOneWidget);
  });

  appTest('creating a wallet shows it with its balance', (tester) async {
    await createWallet(tester, name: 'Pocket', opening: '1200.50');

    expect(find.text('Pocket'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.textContaining('1,200.50'), findsWidgets);
  });

  appTest('a wallet without a name is rejected', (tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Add wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Give the wallet a name'), findsOneWidget);
  });

  appTest('recording an expense updates the balance and history', (
    tester,
  ) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    await tapKeys(tester, '250');
    await tester.tap(find.widgetWithText(FilterChip, 'Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Back on the dashboard, 1000 - 250.
    expect(find.textContaining('750.00'), findsWidgets);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('250.00'), findsWidgets);
  });

  appTest('income adds to the balance', (tester) async {
    await createWallet(tester, opening: '100');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '400');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('500.00'), findsWidgets);
  });

  appTest('saving is blocked until the amount is more than zero', (
    tester,
  ) async {
    await createWallet(tester);

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);

    await tapKeys(tester, '5');
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  appTest('a transfer needs a destination before it can be saved', (
    tester,
  ) async {
    await createWallet(tester, name: 'Cash', opening: '500');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '100');

    // Amount alone is not enough for a transfer.
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(find.text('To wallet'), findsOneWidget);
  });

  appTest('the entry screen asks for a wallet first when there are none', (
    tester,
  ) async {
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Add a wallet first'), findsOneWidget);
  });

  appTest('history offers to clear a filter that matches nothing', (
    tester,
  ) async {
    await createWallet(tester);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches'), findsOneWidget);
  });

  appTest('a budget appears on the dashboard and tracks spending', (
    tester,
  ) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();

    expect(find.text('No budgets this month'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Set a budget'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly limit'),
      '200',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Set budget'));
    await tester.pumpAndSettle();

    // Nothing spent yet.
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('200.00'), findsWidgets);
  });

  appTest('spending moves the budget bar and flags an overspend', (
    tester,
  ) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Set a budget'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly limit'),
      '100',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Set budget'));
    await tester.pumpAndSettle();

    // Back out of the pushed budgets screen: its FAB adds budgets, not money.
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '150');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    // The dashboard summary reflects it without being asked to refresh.
    expect(find.text('150%'), findsOneWidget);
    expect(find.textContaining('over by'), findsOneWidget);
  });

  appTest('a repeating rule can be created and paused', (tester) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeating'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing repeating yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add a repeat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '900');
    await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'Rent');
    await tester.tap(find.widgetWithText(FilledButton, 'Create repeat'));
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsOneWidget);
    expect(find.textContaining('Every month'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paused'), findsOneWidget);
  });

  appTest('insights says so when there is nothing to chart', (tester) async {
    await createWallet(tester);

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to show yet'), findsOneWidget);
    // The range picker is still usable with no data.
    for (final preset in ['This month', 'Last month', '3 months']) {
      expect(find.text(preset), findsOneWidget);
    }
  });

  appTest('insights summarises spending and names the categories', (
    tester,
  ) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '250');
    await tester.tap(find.widgetWithText(FilterChip, 'Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Where it went'), findsOneWidget);
    // Identity comes from the legend, never colour alone.
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.textContaining('250.00'), findsWidgets);
  });

  appTest('switching the range re-reads the figures', (tester) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '250');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Where it went'), findsOneWidget);

    // Today's spending is not in last month.
    await tester.tap(find.text('Last month'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to show yet'), findsOneWidget);
  });

  appTest(
    'a fresh install starts in onboarding, not on an empty dashboard',
    (tester) async {
      expect(find.text('Kori'), findsWidgets);
      expect(find.textContaining('no account to make'), findsOneWidget);
      // No tab bar yet: onboarding is not the app.
      expect(find.text('History'), findsNothing);
    },
    onboarded: false,
  );

  appTest('onboarding creates the first wallet and does not run again', (
    tester,
  ) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Wallet name'),
      'Pocket',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'How much is in it?'),
      '500',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();

    // Straight into the app, with the wallet already there.
    expect(find.text('Pocket'), findsOneWidget);
    expect(find.textContaining('500.00'), findsWidgets);
    expect(find.text('History'), findsOneWidget);
  }, onboarded: false);

  appTest('appearance can be switched to dark', (tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  appTest('the app lock switch is off until turned on', (tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final lock = find.widgetWithText(SwitchListTile, 'Lock the app');
    expect(tester.widget<SwitchListTile>(lock).value, isFalse);

    await tester.tap(lock);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(lock).value, isTrue);
  });

  appTest('every tab is reachable', (tester) async {
    for (final tab in ['History', 'Insights', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(tab), findsWidgets);
    }
  });
}
