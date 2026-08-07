import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/app.dart';

void main() {
  testWidgets('the app opens straight into the wallet tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoriApp()));
    await tester.pumpAndSettle();

    // No login wall: the first screen is the app itself.
    expect(find.text('Kori'), findsOneWidget);
    for (final tab in ['Home', 'History', 'Insights', 'Settings']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  testWidgets('every tab is reachable', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoriApp()));
    await tester.pumpAndSettle();

    for (final tab in ['History', 'Insights', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(tab), findsWidgets);
    }
  });

  testWidgets('the add button opens the entry screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoriApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsWidgets);
  });
}
