import 'package:flutter/material.dart';

/// Categorical colours for wallets, categories and charts. Validated, not picked
/// by eye — lightness band, chroma floor, colour-blind separation and contrast.
///
/// Dark is its own selected step per slot, not a brightened copy: five light
/// steps sit outside the band a dark surface needs. Five also fall under 3:1 on
/// light, allowed only because every chart names its series in a legend or axis.
const List<int> chartPaletteLight = [
  0xFF0D9488, // teal
  0xFFEF4444, // red
  0xFF3B82F6, // blue
  0xFFF59E0B, // amber
  0xFFA855F7, // purple
  0xFF22C55E, // green
  0xFF0EA5E9, // sky
  0xFFF97316, // orange
  0xFFEC4899, // pink
  0xFF6366F1, // indigo
  0xFF84CC16, // lime
];

const List<int> chartPaletteDark = [
  0xFF0D9488,
  0xFFEF4444,
  0xFF3B82F6,
  0xFFD97706,
  0xFFA855F7,
  0xFF16A34A,
  0xFF0284C7,
  0xFFEA580C,
  0xFFEC4899,
  0xFF6366F1,
  0xFF65A30D,
];

/// Colours from earlier builds, mapped onto the nearest validated slot so a
/// wallet chosen before this palette existed still renders safely.
const Map<int, int> _legacy = {
  0xFF14B8A6: 0xFF0D9488, // teal-500 → teal-600
  0xFF8B5CF6: 0xFFA855F7, // the confusable violet → purple
  0xFF10B981: 0xFF22C55E, // emerald → green
  0xFF059669: 0xFF22C55E,
  0xFFF472B6: 0xFFEC4899, // light pink → pink
  0xFF475569: 0xFF6366F1, // slate read as gray → indigo
  0xFF6B7280: 0xFF6366F1,
  0xFF0F766E: 0xFF0D9488,
};

/// The step to draw [stored] with under [brightness].
///
/// Values are kept as the user picked them; only the rendering step changes, so
/// switching theme never rewrites anyone's data.
Color chartColor(int stored, Brightness brightness) {
  // A colour with no alpha renders as nothing, which an import or a restored
  // backup can easily produce. Nobody ever means an invisible category.
  final opaque = (stored & 0xFF000000) == 0 ? stored | 0xFF000000 : stored;
  final canonical = _legacy[opaque] ?? opaque;
  if (brightness == Brightness.light) return Color(canonical);

  final index = chartPaletteLight.indexOf(canonical);
  return Color(index == -1 ? canonical : chartPaletteDark[index]);
}

/// `context.chartColor(category.color)`
extension ChartColorAccess on BuildContext {
  Color chartColorFor(int stored) =>
      chartColor(stored, Theme.of(this).brightness);
}
