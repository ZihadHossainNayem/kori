import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/app.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/providers.dart';

/// Pumps the app against a throwaway in-memory database, runs [body], then
/// tears the tree down inside the test.
///
/// The teardown matters: cancelling drift's last stream subscription schedules a
/// zero-duration cleanup timer, and disposing at the end of the test instead of
/// during the framework's teardown lets that timer fire before it checks for
/// pending timers.
void appTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = KoriDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
        ],
        child: const KoriApp(),
      ),
    );
    await tester.pumpAndSettle();

    await body(tester);

    await tester.pumpWidget(const SizedBox());
    // A bare pump() does not advance fake time, so the zero-duration timer
    // would still be pending.
    await tester.pump(const Duration(milliseconds: 10));
  });
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
    await tester.tap(find.widgetWithText(FilledButton, 'Add wallet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Pocket');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Opening balance'),
      '1200.50',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Pocket'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    // With no transactions, the opening balance is the balance.
    expect(find.textContaining('1,200.50'), findsWidgets);
  });

  appTest('a wallet without a name is rejected', (tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Add wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Give the wallet a name'), findsOneWidget);
  });

  appTest('every tab is reachable', (tester) async {
    for (final tab in ['History', 'Insights', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(tab), findsWidgets);
    }
  });

  appTest('the add button opens the entry screen', (tester) async {
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsWidgets);
  });
}
