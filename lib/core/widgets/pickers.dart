import 'package:flutter/material.dart';

import '../chart_palette.dart';
import '../icons.dart';
import '../theme.dart';

/// Colour swatches from the validated palette.
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in palette)
          Semantics(
            selected: color == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(color),
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.chartColorFor(color),
                  shape: BoxShape.circle,
                  border: color == selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: color == selected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class IconPicker extends StatelessWidget {
  const IconPicker({
    required this.names,
    required this.selected,
    required this.color,
    required this.onSelected,
    super.key,
  });

  final List<String> names;
  final String selected;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final name in names)
          Semantics(
            selected: name == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelected(name),
              borderRadius: BorderRadius.circular(KoriRadius.small),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: name == selected
                      ? color.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(KoriRadius.small),
                  border: name == selected
                      ? Border.all(color: color, width: 2)
                      : null,
                ),
                child: Icon(
                  iconFor(name),
                  size: 22,
                  color: name == selected ? color : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
