import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kori/app.dart';

/// Runs against the real on-device database, so it covers what widget tests
/// cannot: opening SQLite through path_provider on the actual platform.
///
/// Names are unique per run because the database persists between runs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records an expense against the real database', (tester) async {
    final suffix = DateTime.now().millisecondsSinceEpoch % 100000;
    final walletName = 'Test $suffix';

    await tester.pumpWidget(const ProviderScope(child: KoriApp()));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Kori'), findsOneWidget);

    // The toolbar action exists whether or not wallets already exist.
    await tester.tap(find.byTooltip('Add wallet'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      walletName,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Opening balance'),
      '1000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text(walletName), findsWidgets);

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    // Pick the wallet explicitly. The screen prefills the last one used, so on a
    // device with existing wallets the expense would otherwise land elsewhere.
    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(walletName).last);
    await tester.pumpAndSettle();

    for (final digit in ['2', '5', '0']) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilterChip, 'Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // 1000 - 250, read back through the balance view.
    expect(find.textContaining('750'), findsWidgets);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Food & Dining'), findsWidgets);
    expect(find.text('Today'), findsWidgets);

    // Leave the database as it was found. Deleting the wallet cascades its
    // transactions away, so the expense goes with it.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(walletName).first);
    await tester.pumpAndSettle();

    // Destructive actions sit below the fold in the sheet, by design.
    final delete = find.widgetWithText(TextButton, 'Delete');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text(walletName), findsNothing);
  });
}
