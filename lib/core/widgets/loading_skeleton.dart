import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme.dart';

/// Rounded bars shaped like the rows a screen is about to show, shimmering
/// while its first query resolves.
///
/// Drift queries answer in milliseconds on-device, so a spinner here mostly
/// just flashes — this reads as "the content is arriving" rather than "wait."
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({this.rows = 4, this.rowHeight = 72, super.key});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerLowest,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, _) => Container(
          height: rowHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(KoriRadius.medium),
          ),
        ),
      ),
    );
  }
}
