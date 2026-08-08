import 'package:flutter/material.dart';

import '../money.dart';
import '../theme.dart';

/// A [Money] amount that counts to its new value instead of snapping.
///
/// Only the digits tween — currency, sign and formatting all come from
/// [Money.format] on every frame, so locale and minor-unit rules never drift
/// from the non-animated call sites.
class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText({
    required this.amount,
    this.style,
    this.duration = const Duration(milliseconds: 500),
    super.key,
  });

  final Money amount;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: amount.minor),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, minor, _) =>
          Text(Money(minor, amount.currency).format(), style: style?.tabular),
    );
  }
}
