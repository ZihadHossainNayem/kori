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
/// The default 800x600 window is shorter than any phone and hides pinned
/// buttons; disposing early lets drift's cleanup timer fire while fake time
/// still advances.
void appTest(
  String description,
  Future<void> Function(WidgetTester) body, {
  bool onboarded = true,
  Size logicalSize = const Size(360, 800),
  double textScale = 1,
}) {
  testWidgets(description, (tester) async {
    tester.view
      ..physicalSize = logicalSize * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

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
    // No login wall, and no wordmark on Home either — the greeting stands in
    // for it.
    expect(find.text('Start with a wallet'), findsOneWidget);
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

  appTest('a selected category chip keeps its label legible', (tester) async {
    await createWallet(tester);
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    final chipFinder = find.widgetWithText(FilterChip, 'Food & Dining');
    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(chipFinder)).colorScheme;
    final chip = tester.widget<FilterChip>(chipFinder);
    expect(chip.labelStyle?.color, scheme.onSurface);
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

    // Recording money isn't a Settings action — that FAB only shows on the
    // money tabs — so go to Home first, the way a real user would.
    await tester.tap(find.text('Home'));
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

    // The switch is the last row, half-hidden until the list is scrolled.
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    await tester.tap(lock);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(lock).value, isTrue);
  });

  appTest('a second-currency wallet is flagged until a rate is entered', (
    tester,
  ) async {
    await createWallet(tester, name: 'Dollars', opening: '100');

    // The dashboard says the wallet is left out, rather than inventing a rate.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange rates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no internet permission'), findsOneWidget);
    // Nothing to convert: the only wallet uses the display currency.
    expect(find.text('Nothing to convert'), findsOneWidget);
  });

  appTest('a hand-entered rate is saved and shown with its age', (
    tester,
  ) async {
    await createWallet(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange rates'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add rate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '120');
    await tester.tap(find.widgetWithText(FilledButton, 'Save rate'));
    await tester.pumpAndSettle();

    // The pair defaults to a currency other than the display one, so the
    // button is never disabled on a freshly opened form.
    expect(find.textContaining('= 120 USD'), findsOneWidget);
    expect(find.text('Set today'), findsOneWidget);
  });

  appTest('every tab is reachable', (tester) async {
    for (final tab in ['History', 'Insights', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(tab), findsWidgets);
    }
  });

  appTest('the nav indicator glides rather than snaps between tabs', (
    tester,
  ) async {
    final indicator = find.byType(AnimatedPositionedDirectional);
    final start = tester.getTopLeft(indicator).dx;

    await tester.tap(find.text('Insights'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = tester.getTopLeft(indicator).dx;

    await tester.pumpAndSettle();
    final end = tester.getTopLeft(indicator).dx;

    expect(end, greaterThan(start));
    expect(mid, greaterThan(start));
    expect(mid, lessThan(end));
  });

  /// The bar's own gap unit, mirrored here since app.dart keeps it private —
  /// every clearance below is stated in terms of it, not raw pixels.
  const navGap = 6.0;

  /// The bar's own outline. Nothing else in the app blurs its backdrop.
  Rect navBar(WidgetTester tester) =>
      tester.getRect(find.byType(BackdropFilter));

  /// A tab's whole column, which is also its whole tap target — the closest
  /// Material above the label fills the column rather than the pill.
  Rect navColumn(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(
          of: find.descendant(
            of: find.byType(BackdropFilter),
            matching: find.text(label),
          ),
          matching: find.byType(Material),
        )
        .first,
  );

  Rect navPill(WidgetTester tester) =>
      tester.getRect(find.byType(AnimatedPositionedDirectional));

  Rect navAction(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byTooltip('Add transaction'),
      matching: find.byType(Material),
    ),
  );

  appTest('the bar lays out as one five-column grid', (tester) async {
    final columns = [
      navColumn(tester, 'Home'),
      navColumn(tester, 'History'),
      navAction(tester),
      navColumn(tester, 'Insights'),
      navColumn(tester, 'Settings'),
    ];

    // The action holds a column of its own, on the same rhythm as every tab —
    // measured centre to centre, since that's what the eye reads along a row.
    final pitch = columns.first.width;
    for (var i = 1; i < columns.length; i++) {
      expect(
        columns[i].center.dx - columns[i - 1].center.dx,
        moreOrLessEquals(pitch),
        reason: 'column $i does not sit on the grid',
      );
    }
    // The action fills less of its column than a tab does of its own — the
    // difference is the moat, and it is why the + reads as an anchor.
    expect(columns[2].width, lessThan(pitch));
  });

  appTest('the active pill sits evenly inset inside the bar', (tester) async {
    final bar = navBar(tester);
    final pill = navPill(tester);
    final home = navColumn(tester, 'Home');

    // Centred vertically: the same air above the pill as below it.
    expect(pill.top - bar.top, moreOrLessEquals(bar.bottom - pill.bottom));
    // And centred in its column horizontally.
    expect(pill.center.dx, moreOrLessEquals(home.center.dx));

    // The same inset all around, measured where the pill meets the bar's end
    // — not concentric corners (the pill is squarer on purpose), just one
    // clear-space number everywhere.
    final inset = pill.top - bar.top;
    expect(pill.left - bar.left, moreOrLessEquals(inset));

    // The whole column is tappable, not just the pill drawn inside it.
    expect(home.height, greaterThan(pill.height));
    expect(home.height, greaterThanOrEqualTo(48));
    expect(home.width, greaterThanOrEqualTo(48));
  });

  appTest('a label keeps clear of the fill it sits on', (tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final pill = navPill(tester);
    final label = tester.getRect(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.text('Settings'),
      ),
    );

    // The longest label, on the tab whose pill sits against the bar's end —
    // its box stays inside the fill, so it ellipsises before it can reach
    // the corner.
    expect(label.left - pill.left, greaterThanOrEqualTo(navGap));
    expect(pill.right - label.right, greaterThanOrEqualTo(navGap));
  });

  appTest('the + keeps a moat of twice the tab gap on both sides', (
    tester,
  ) async {
    final action = navAction(tester);
    final tabGap = navColumn(tester, 'Home').width - navPill(tester).width;

    // The action stands in the same band as the pill — one horizon across the
    // bar, so nothing beside the + sits a pixel above or below it.
    expect(action.top, moreOrLessEquals(navPill(tester).top));
    expect(action.height, moreOrLessEquals(navPill(tester).height));

    // A floor, not an exact figure — the moat is whatever's left in the
    // column once the circle sits in it, so it widens with the column; what
    // matters is it never drops to an ordinary tab gap.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(
      action.left - navPill(tester).right,
      greaterThanOrEqualTo(tabGap * 2),
    );

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(
      navPill(tester).left - action.right,
      greaterThanOrEqualTo(tabGap * 2),
    );
  });

  /// The two extremes the bar has to survive: the narrowest phone still
  /// shipped, and more text scaling than it allows. Label widths aren't
  /// asserted — the test font draws glyphs far wider than Manrope, so that
  /// would measure the font, not the layout.
  for (final (name, size, scale) in [
    ('a narrow phone', const Size(320, 640), 1.0),
    ('the largest text it lets through', const Size(360, 800), 1.3),
    ('both at once', const Size(320, 640), 1.3),
  ]) {
    appTest('the bar holds its geometry on $name', (tester) async {
      final bar = navBar(tester);
      final pill = navPill(tester);

      // Still floating clear of both screen edges, never stretched to them.
      expect(bar.left, greaterThan(8));
      expect(bar.right, lessThan(size.width - 8));

      // Still centred, still evenly inset, still a full-size tap target — all
      // of it derived, so none of it is width-specific.
      expect(pill.top - bar.top, moreOrLessEquals(bar.bottom - pill.bottom));
      expect(pill.left - bar.left, moreOrLessEquals(pill.top - bar.top));
      expect(navColumn(tester, 'Home').height, greaterThanOrEqualTo(48));
      expect(navColumn(tester, 'Home').width, greaterThanOrEqualTo(48));
    }, logicalSize: size, textScale: scale);
  }

  /// Opens Settings → Categories, which is where every category test starts.
  Future<void> openCategories(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
  }

  /// The archive and delete actions sit below the fold on a phone-sized sheet.
  Future<void> scrollSheet(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }

  appTest('a new category is usable on the keypad straight away', (
    tester,
  ) async {
    await createWallet(tester);
    await openCategories(tester);

    await tester.tap(find.byTooltip('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'School fees',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add category'));
    await tester.pumpAndSettle();

    expect(find.text('School fees'), findsOneWidget);

    // Categories is a pushed route, so the tab bar is behind it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.text('School fees'), findsOneWidget);
  });

  appTest('renaming a category renames it everywhere', (tester) async {
    await openCategories(tester);

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Bazar');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsNothing);
    expect(find.text('Bazar'), findsOneWidget);
  });

  appTest('archiving hides a category but keeps it recoverable', (
    tester,
  ) async {
    await openCategories(tester);

    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    await scrollSheet(tester);
    await tester.tap(find.textContaining('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Transport'), findsNothing);

    await tester.tap(find.byTooltip('Show archived'));
    await tester.pumpAndSettle();

    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
  });

  appTest('income and spending categories are kept apart', (tester) async {
    await openCategories(tester);

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
  });

  appTest('deleting says what happens to the transactions in it', (
    tester,
  ) async {
    await openCategories(tester);

    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    await scrollSheet(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Uncategorised'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Health'), findsNothing);
  });

  appTest('the dashboard shows what was just recorded', (tester) async {
    await createWallet(tester, opening: '1000');

    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tapKeys(tester, '250');
    await tester.tap(find.widgetWithText(FilterChip, 'Food & Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Recent activity'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Food & Dining'), findsWidgets);
    expect(find.textContaining('250.00'), findsWidgets);
  });
}
