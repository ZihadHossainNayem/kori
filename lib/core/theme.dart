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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 3,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
