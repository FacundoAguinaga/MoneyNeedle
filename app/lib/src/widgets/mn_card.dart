import 'package:flutter/material.dart';

/// Card estandarizada del Design System de MoneyNeedle.
class MnCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;

  const MnCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final border = BorderSide(
      color: borderColor ?? colorScheme.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: border,
    );

    final cardColor = backgroundColor ?? colorScheme.surface;

    Widget content = Material(
      color: cardColor,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              child: Padding(
                padding: padding,
                child: child,
              ),
            )
          : Padding(
              padding: padding,
              child: child,
            ),
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}
