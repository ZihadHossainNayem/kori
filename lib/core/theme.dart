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
    income: _Ramp.green500,
    expense: _Ramp.red600,
    transfer: _Ramp.mono700,
    overBudget: _Ramp.orange600,
  );

  /// Lifted for contrast on true black. expense uses red400, not
  /// colorScheme.error's red300, so tuning one never shifts the other.
  static const dark = MoneyColors(
    income: _Ramp.green300,
    expense: _Ramp.red400,
    transfer: _Ramp.mono600,
    overBudget: _Ramp.orange300,
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

/// The corner radii every shape draws from. Tighter than Material's defaults —
/// squarer corners are what keep a monochrome UI reading as engineered.
abstract final class KoriRadius {
  static const double small = 8; // icon tiles, chips, inputs, row ripples
  static const double medium = 12; // cards
  static const double large = 16; // bottom sheets, dialogs
}

/// The 4px spacing scale. Named steps, so padding is chosen from a scale rather
/// than typed as a number that happens to look right. Steps are added as they
/// earn a second use, not defined up front.
abstract final class KoriSpace {
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// The raw ramps every role in [KoriTheme] is picked from. Not seed-derived —
/// `ColorScheme.fromSeed` documents itself as building "pastel palettes with a
/// low chroma", which read washed out under every seed tried.
///
/// Neutrals are Base ramp verbatim (MIT); accents start from Base and are
/// darkened or lifted only where a step had to clear 4.5:1 as text.
abstract final class _Ramp {
  // Neutral — true grey, no hue tint. Base's `mono` ramp.
  static const mono100 = Color(0xFFFFFFFF);
  static const mono200 = Color(0xFFF6F6F6);
  static const mono300 = Color(0xFFEEEEEE);
  static const mono400 = Color(0xFFE2E2E2);
  static const mono500 = Color(0xFFCBCBCB);
  static const mono600 = Color(0xFFAFAFAF);
  static const mono700 = Color(0xFF757575);
  static const mono800 = Color(0xFF545454);
  static const mono900 = Color(0xFF333333);
  static const mono1000 = Color(0xFF000000);

  // Dark-mode elevation. Page is  off-black, not true #000 — true
  // black next to white text reads as a dead OLED cutout, not a surface.
  static const elev000 = Color(0xFF161616);
  static const elev100 = Color(0xFF1F1F1F);
  static const elev200 = Color(0xFF282828);
  static const elev300 = Color(0xFF323232);
  static const elev400 = Color(0xFF3D3D3D);

  // Green — money in. green500 is Base's `positive` darkened for 4.5:1 on
  // white; green300 is repicked in-band so dark mode doesn't read pastel.
  static const green300 = Color(0xFF16A34A);
  static const green500 = Color(0xFF05874A);

  // Red — errors, and (red400 only) money out. red300/red600 are Base's own
  // steps, tuned for colorScheme.error; red400 is dedicated to money.expense
  // on dark so the two can move independently.
  static const red100 = Color(0xFFFFEFED);
  static const red300 = Color(0xFFFF7A6B);
  static const red400 = Color(0xFFEF4444);
  static const red600 = Color(0xFFE11900);
  static const red700 = Color(0xFFAB1300);
  static const red900 = Color(0xFF5A0A00);

  // Orange — approaching or over budget. Repicked further into amber; the
  // old steps measured too close to red for colour-blind and normal vision.
  static const orange300 = Color(0xFFFBBF24);
  static const orange600 = Color(0xFFCB8500);
}

abstract final class KoriTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Black is the action colour and green is reserved for money, so an amount
  /// is never mistaken for a control and a control is never read as a total.
  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: _Ramp.mono1000,
    onPrimary: _Ramp.mono100,
    primaryContainer: _Ramp.mono300,
    onPrimaryContainer: _Ramp.mono1000,
    primaryFixed: _Ramp.mono300,
    primaryFixedDim: _Ramp.mono400,
    onPrimaryFixed: _Ramp.mono1000,
    onPrimaryFixedVariant: _Ramp.mono800,
    secondary: _Ramp.mono800,
    onSecondary: _Ramp.mono100,
    secondaryContainer: _Ramp.mono300,
    onSecondaryContainer: _Ramp.mono900,
    secondaryFixed: _Ramp.mono300,
    secondaryFixedDim: _Ramp.mono400,
    onSecondaryFixed: _Ramp.mono1000,
    onSecondaryFixedVariant: _Ramp.mono800,
    tertiary: _Ramp.mono700,
    onTertiary: _Ramp.mono100,
    tertiaryContainer: _Ramp.mono300,
    onTertiaryContainer: _Ramp.mono900,
    tertiaryFixed: _Ramp.mono300,
    tertiaryFixedDim: _Ramp.mono400,
    onTertiaryFixed: _Ramp.mono1000,
    onTertiaryFixedVariant: _Ramp.mono800,
    error: _Ramp.red600,
    onError: _Ramp.mono100,
    errorContainer: _Ramp.red100,
    onErrorContainer: _Ramp.red900,
    // True white against true black text — the two ends of the contrast range
    // everything else sits inside.
    surface: _Ramp.mono100,
    onSurface: _Ramp.mono1000,
    surfaceDim: _Ramp.mono300,
    surfaceBright: _Ramp.mono100,
    surfaceContainerLowest: _Ramp.mono100,
    surfaceContainerLow: _Ramp.mono200,
    surfaceContainer: _Ramp.mono300,
    surfaceContainerHigh: _Ramp.mono400,
    surfaceContainerHighest: _Ramp.mono500,
    onSurfaceVariant: _Ramp.mono700,
    outline: _Ramp.mono600,
    outlineVariant: _Ramp.mono400,
    shadow: _Ramp.mono1000,
    scrim: _Ramp.mono1000,
    inverseSurface: _Ramp.mono1000,
    onInverseSurface: _Ramp.mono100,
    inversePrimary: _Ramp.mono100,
    surfaceTint: Colors.transparent,
  );

  /// `primary` inverts to white: a black button on a black page is invisible.
  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: _Ramp.mono100,
    onPrimary: _Ramp.mono1000,
    primaryContainer: _Ramp.elev300,
    onPrimaryContainer: _Ramp.mono100,
    primaryFixed: _Ramp.mono300,
    primaryFixedDim: _Ramp.mono400,
    onPrimaryFixed: _Ramp.mono1000,
    onPrimaryFixedVariant: _Ramp.mono800,
    secondary: _Ramp.mono500,
    onSecondary: _Ramp.mono1000,
    secondaryContainer: _Ramp.mono900,
    onSecondaryContainer: _Ramp.mono200,
    secondaryFixed: _Ramp.mono300,
    secondaryFixedDim: _Ramp.mono400,
    onSecondaryFixed: _Ramp.mono1000,
    onSecondaryFixedVariant: _Ramp.mono800,
    tertiary: _Ramp.mono600,
    onTertiary: _Ramp.mono1000,
    tertiaryContainer: _Ramp.mono900,
    onTertiaryContainer: _Ramp.mono200,
    tertiaryFixed: _Ramp.mono300,
    tertiaryFixedDim: _Ramp.mono400,
    onTertiaryFixed: _Ramp.mono1000,
    onTertiaryFixedVariant: _Ramp.mono800,
    error: _Ramp.red300,
    onError: _Ramp.red900,
    errorContainer: _Ramp.red700,
    onErrorContainer: _Ramp.red100,
    surface: _Ramp.elev000,
    onSurface: _Ramp.mono100,
    surfaceDim: _Ramp.elev000,
    surfaceBright: _Ramp.elev400,
    surfaceContainerLowest: _Ramp.elev000,
    surfaceContainerLow: _Ramp.elev100,
    surfaceContainer: _Ramp.elev200,
    surfaceContainerHigh: _Ramp.elev300,
    surfaceContainerHighest: _Ramp.elev400,
    onSurfaceVariant: _Ramp.mono600,
    outline: _Ramp.mono800,
    outlineVariant: _Ramp.mono900,
    shadow: _Ramp.mono1000,
    scrim: _Ramp.mono1000,
    inverseSurface: _Ramp.mono100,
    onInverseSurface: _Ramp.mono1000,
    inversePrimary: _Ramp.mono1000,
    surfaceTint: Colors.transparent,
  );

  /// Roles, not sizes. Headings run heavy and tightly tracked; labels carry the
  /// controls; body stays regular so a dense list is still readable.
  static const _text = TextTheme(
    displayLarge: TextStyle(
      fontSize: 52,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.6,
      height: 1.08,
    ),
    displayMedium: TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.3,
      height: 1.1,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.12,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.16,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.22,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.35,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.2,
    ),
  );

  static ThemeData _build(Brightness brightness) {
    final scheme = brightness == Brightness.light ? _light : _dark;
    final radiusSmall = BorderRadius.circular(KoriRadius.small);

    // Controls stand 48 tall and share one corner — the single most visible
    // thing that makes a set of screens read as one app.
    final buttonShape = RoundedRectangleBorder(borderRadius: radiusSmall);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: KoriSpace.xl,
      vertical: KoriSpace.md,
    );
    const buttonSize = Size(64, 48);

    return ThemeData(
      colorScheme: scheme,
      // Manrope's geometric, slightly condensed numerals are why it was chosen
      // over the Material default — amounts are most of what this app displays.
      fontFamily: 'Manrope',
      textTheme: _text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [
        brightness == Brightness.light ? MoneyColors.light : MoneyColors.dark,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: _text.titleLarge?.copyWith(
          fontFamily: 'Manrope',
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoriRadius.medium),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonSize,
          textStyle: _text.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonSize,
          textStyle: _text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonSize,
          textStyle: _text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: buttonShape,
          textStyle: _text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: KoriSpace.lg),
        minVerticalPadding: KoriSpace.md,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KoriSpace.lg,
          vertical: KoriSpace.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        // Focus is a dark ring rather than a colour change — the accent is
        // spent on money, not on which field has the caret.
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: scheme.onSurface, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
        backgroundColor: scheme.surfaceContainerLow,
        // Inverted, not tinted, so "selected" reads the same as the nav bar's
        // active tab.
        selectedColor: scheme.inverseSurface,
        // A labelStyle with no colour made Chip skip its own per-state default
        // and inherit the ambient DefaultTextStyle instead, which read
        // illegibly on some backgrounds — so colour is set explicitly here.
        labelStyle: _text.labelMedium?.copyWith(
          fontFamily: 'Manrope',
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onInverseSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoriRadius.large),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoriRadius.large),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: _text.bodyMedium?.copyWith(
          fontFamily: 'Manrope',
          color: scheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
      ),
      // A plain ripple, not M3's sparkle — the sparkle draws attention to the
      // chrome, which is the opposite of what a monochrome system is for.
      splashFactory: InkRipple.splashFactory,
    );
  }
}
