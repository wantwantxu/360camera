import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/space_theme.dart';
import '../../../domain/vr_space.dart';

IconData spaceCategoryIcon(SpaceCategory category) {
  return switch (category) {
    SpaceCategory.residence => Icons.home_rounded,
    SpaceCategory.apartment => Icons.apartment_rounded,
    SpaceCategory.shop => Icons.storefront_rounded,
    SpaceCategory.office => Icons.business_center_rounded,
    SpaceCategory.exhibition => Icons.museum_rounded,
    SpaceCategory.other => Icons.view_in_ar_rounded,
  };
}

class SpaceCover extends StatelessWidget {
  const SpaceCover({
    super.key,
    required this.point,
    this.borderRadius = 16,
    this.showPlay = false,
  });

  final VrPoint? point;
  final double borderRadius;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final file = point == null ? null : File(point!.thumbPath);
    final exists = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (exists)
            Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _CoverFallback(),
            )
          else
            const _CoverFallback(),
          if (showPlay && exists)
            Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2E36), Color(0xFF16181D)],
        ),
      ),
      child: CustomPaint(painter: _CoverLinesPainter()),
    );
  }
}

class _CoverLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.22, paint);
    for (var i = 0; i < 8; i++) {
      final angle = i * 45 * 3.1415926 / 180;
      final a = center + Offset.fromDirection(angle, 24);
      final b = center + Offset.fromDirection(angle, size.width * 0.38);
      canvas.drawLine(a, b, paint);
    }
    final icon = Icons.view_in_ar_rounded;
    final text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          fontSize: 34,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SpaceCategoryBadge extends StatelessWidget {
  const SpaceCategoryBadge({
    super.key,
    required this.category,
    this.light = false,
  });

  final SpaceCategory category;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: light
            ? Colors.black.withValues(alpha: 0.42)
            : SpaceColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: light ? Border.all(color: Colors.white24) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            spaceCategoryIcon(category),
            size: 12,
            color: light ? Colors.white : SpaceColors.accentDark,
          ),
          const SizedBox(width: 4),
          Text(
            category.label,
            style: TextStyle(
              color: light ? Colors.white : SpaceColors.accentDark,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SpaceSectionHeader extends StatelessWidget {
  const SpaceSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpaceColors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class SpaceEmptyPanel extends StatelessWidget {
  const SpaceEmptyPanel({
    super.key,
    required this.onCreate,
    required this.onGuide,
  });

  final VoidCallback onCreate;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: SpaceColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.camera_rounded,
              color: SpaceColors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '创建你的第一个空间',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '在房间内拍摄若干点位，自动拼接成可穿行的 VR 空间。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: SpaceColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: SpaceColors.accent,
              ),
              child: const Text('开始拍摄'),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onGuide,
            child: const Text(
              '先看看怎么拍',
              style: TextStyle(color: SpaceColors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class PointSourceBadge extends StatelessWidget {
  const PointSourceBadge({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      'capture' || 'camera' => ('实拍', SpaceColors.accent),
      'import' => ('导入', const Color(0xFF0E9384)),
      _ => ('演示', SpaceColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}