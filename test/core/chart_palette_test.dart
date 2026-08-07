import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/chart_palette.dart';

void main() {
  test('light and dark sets have the same slots', () {
    expect(chartPaletteDark, hasLength(chartPaletteLight.length));
  });

  test('dark mode uses its own step, not the light one', () {
    // Amber is one of the five light steps too pale for a dark surface.
    const amber = 0xFFF59E0B;
    expect(chartColor(amber, Brightness.light), const Color(amber));
    expect(
      chartColor(amber, Brightness.dark),
      isNot(const Color(amber)),
      reason: 'a brightened copy is not a validated dark step',
    );
  });

  test('a colour with no alpha still renders', () {
    // What a bad import or a backup from another tool can produce.
    const noAlpha = 0x000D9488;
    expect(chartColor(noAlpha, Brightness.light).a, 1.0);
  });

  test('colours from earlier builds map onto a validated slot', () {
    // The confusable violet that failed the colour audit.
    const removedViolet = 0xFF8B5CF6;
    expect(
      chartColor(removedViolet, Brightness.light),
      const Color(0xFFA855F7),
    );
  });

  test('an unknown colour is left as the user chose it', () {
    const custom = 0xFF123456;
    expect(chartColor(custom, Brightness.light), const Color(custom));
  });
}
