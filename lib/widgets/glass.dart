import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/pano_colors.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.opacity = 0.82,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: PanoColors.bgPanel.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: PanoColors.borderSubtle),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? PanoColors.bgPill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor ?? PanoColors.borderSubtle),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
