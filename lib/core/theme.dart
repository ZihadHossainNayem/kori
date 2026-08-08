import 'package:flutter/material.dart';

/// Semantic colours a Material scheme has no opinion about.
///
/// A theme extension rather than constants at call sites, so the same red never
/// means "error" in one place and "expense" in another.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.overBudget,
  });

  final Color income;
  final Color expense;
  final Color transfer;
  final Color overBudget;

  static const light = MoneyColors(
    income: Color(0xFF15803D),
    expense: Color(0xFFB91C1C),
    transfer: Color(0xFF4B5563),
    overBudget: Color(0xFFC2410C),
  );

  /// Lifted for contrast — the light values are illegible on near-black.
  static const dark = MoneyColors(
    income: Color(0xFF4ADE80),
    expense: Color(0xFFF87171),
    transfer: Color(0xFF9CA3AF),
    overBudget: Color(0xFFFB923C),
  );

  @override
  MoneyColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? overBudget,
  }) {
    return MoneyColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      overBudget: overBudget ?? this.overBudget,
    );
  }

  @override
  MoneyColors lerp(covariant MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      overBudget: Color.lerp(overBudget, other.overBudget, t)!,
    );
  }
}

/// `context.money.expense`
extension MoneyColorsAccess on BuildContext {
  MoneyColors get money => Theme.of(this).extension<MoneyColors>()!;
}

/// `style.tabular` — digits hold a fixed width, so an amount that ticks up or
/// down does not reflow the text around it. Every `Text` showing a [Money]
/// value should use it, including while the user is still typing one.
extension TabularFigures on TextStyle {
  TextStyle get tabular => copyWith(
    fontFeatures: [...?fontFeatures, const FontFeature.tabularFigures()],
  );
}

/// The three corner radii every shape in the app draws from. Distinct steps
/// stop cards, icon tiles and sheets each acquiring their own accidental
/// roundness over time.
abstract final class KoriRadius {
  static const double small = 12; // icon tiles, chips, inputs, row ripples
  static const double medium = 20; // cards
  static const double large = 28; // bottom sheets, dialogs
}

abstract final class KoriTheme {
  /// Deep teal, for the cowrie shell the app is named after — and a step away
  /// from default fintech blue.
  static const Color seed = Color(0xFF0F766E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      // Manrope's geometric, slightly condensed numerals are why it was
      // chosen over the Material default — amounts are most of what this app
      // displays.
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: scheme.surface,
      extensions: [
        brightness == Brightness.light ? MoneyColors.light : MoneyColors.dark,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoriRadius.medium),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoriRadius.small),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoriRadius.small),
        ),
      ),
      // Tonal fill carries these already — a separate drop shadow doubled up
      // on top of it, which is what made the bar read heavier than the rest.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoriRadius.large),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoriRadius.large),
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
