import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/space_theme.dart';
import '../../../domain/vr_space.dart';

class SpaceMinimapStyle {
  const SpaceMinimapStyle({
    required this.background,
    required this.grid,
    required this.line,
    required this.node,
    required this.nodeText,
    required this.active,
    required this.activeText,
    required this.label,
  });

  final Color background;
  final Color grid;
  final Color line;
  final Color node;
  final Color nodeText;
  final Color active;
  final Color activeText;
  final Color label;

  static const light = SpaceMinimapStyle(
    background: SpaceColors.surfaceAlt,
    grid: Color(0xFFECEEF2),
    line: Color(0xFFC9CDD5),
    node: Colors.white,
    nodeText: SpaceColors.ink,
    active: SpaceColors.accent,
    activeText: Colors.white,
    label: SpaceColors.inkSecondary,
  );

  static const dark = SpaceMinimapStyle(
    background: Color(0xCC111317),
    grid: Color(0x14FFFFFF),
    line: Color(0x55FFFFFF),
    node: Color(0x33FFFFFF),
    nodeText: Colors.white,
    active: SpaceColors.accent,
    activeText: Colors.white,
    label: Color(0xCCFFFFFF),
  );
}

class SpaceMinimap extends StatelessWidget {
  const SpaceMinimap({
    super.key,
    required this.space,
    this.currentPointId,
    this.height = 160,
    this.dark = false,
    this.showLabels = true,
    this.onTapPoint,
    this.viewWorldYawDeg,
  });

  final VrSpace space;
  final String? currentPointId;
  final double height;
  final bool dark;
  final bool showLabels;
  final ValueChanged<VrPoint>? onTapPoint;
  final double? viewWorldYawDeg;

  @override
  Widget build(BuildContext context) {
    final style = dark ? SpaceMinimapStyle.dark : SpaceMinimapStyle.light;
    if (space.points.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? Colors.white12 : SpaceColors.line),
        ),
        alignment: Alignment.center,
        child: Text(
          '还没有点位',
          style: TextStyle(
            color: dark ? Colors.white60 : SpaceColors.inkMuted,
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? Colors.white12 : SpaceColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final layout = _MapLayout(space.points, size);
          final active = space.pointById(currentPointId);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapPainter(
                    layout: layout,
                    style: style,
                    currentPointId: currentPointId,
                    viewWorldYawDeg: viewWorldYawDeg,
                    showLabels: showLabels,
                  ),
                ),
              ),
              for (final entry in layout.positions.entries)
                Positioned(
                  left: entry.value.dx - 18,
                  top: entry.value.dy - 18,
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTapPoint == null
                        ? null
                        : () {
                            final point = space.pointById(entry.key);
                            if (point != null) onTapPoint!(point);
                          },
                    child: Semantics(
                      label:
                          '点位 ${space.indexOfPoint(entry.key) + 1} ${space.pointById(entry.key)?.name ?? ''}',
                      button: onTapPoint != null,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              if (active == null && space.points.isNotEmpty)
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: Text(
                    '空间位置示意',
                    style: TextStyle(
                      color: dark ? Colors.white38 : SpaceColors.inkMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MapLayout {
  _MapLayout(this.points, this.size) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in points) {
      minX = math.min(minX, point.mapX);
      maxX = math.max(maxX, point.mapX);
      minY = math.min(minY, point.mapY);
      maxY = math.max(maxY, point.mapY);
    }
    final spanX = math.max(maxX - minX, 4.0);
    final spanY = math.max(maxY - minY, 4.0);
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    const padding = 34.0;
    final usableW = math.max(20.0, size.width - padding * 2);
    final usableH = math.max(20.0, size.height - padding * 2);
    _scale =
        math.min(usableW / spanX, usableH / spanY).clamp(8.0, 80.0).toDouble();
    _centerX = centerX;
    _centerY = centerY;
  }

  final List<VrPoint> points;
  final Size size;
  late final double _scale;
  late final double _centerX;
  late final double _centerY;

  Map<String, Offset> get positions => {
        for (final point in points) point.id: project(point),
      };

  Offset project(VrPoint point) {
    return Offset(
      size.width / 2 + (point.mapX - _centerX) * _scale,
      size.height / 2 - (point.mapY - _centerY) * _scale,
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.layout,
    required this.style,
    required this.currentPointId,
    required this.viewWorldYawDeg,
    required this.showLabels,
  });

  final _MapLayout layout;
  final SpaceMinimapStyle style;
  final String? currentPointId;
  final double? viewWorldYawDeg;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final positions = layout.positions;
    final pathPaint = Paint()
      ..color = style.line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < layout.points.length - 1; i++) {
      final a = positions[layout.points[i].id];
      final b = positions[layout.points[i + 1].id];
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, pathPaint);
    }

    for (var i = 0; i < layout.points.length; i++) {
      final point = layout.points[i];
      final center = positions[point.id];
      if (center == null) continue;
      final active = point.id == currentPointId;
      final radius = active ? 12.0 : 9.0;
      if (active) {
        canvas.drawCircle(
          center,
          radius + 6,
          Paint()..color = style.active.withValues(alpha: 0.18),
        );
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = active ? style.active : style.node,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2 : 1.2
          ..color = active ? style.active : style.line,
      );
      final number = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: active ? style.activeText : style.nodeText,
            fontSize: active ? 10 : 8,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      number.paint(
        canvas,
        center - Offset(number.width / 2, number.height / 2),
      );

      if (showLabels && (active || layout.points.length <= 8)) {
        final label = TextPainter(
          text: TextSpan(
            text: point.name,
            style: TextStyle(
              color: active ? style.label : style.label.withValues(alpha: 0.72),
              fontSize: 9,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              shadows: const [
                Shadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 84);
        label.paint(canvas, center + Offset(radius + 4, -label.height / 2));
      }

      if (active && viewWorldYawDeg != null) {
        final rad = (viewWorldYawDeg! - 90) * math.pi / 180;
        final tip = center + Offset(math.cos(rad), math.sin(rad)) * 30;
        final left = center +
            Offset(
                  math.cos(rad - 0.32),
                  math.sin(rad - 0.32),
                ) *
                18;
        final right = center +
            Offset(
                  math.cos(rad + 0.32),
                  math.sin(rad + 0.32),
                ) *
                18;
        final cone = Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(left.dx, left.dy)
          ..close()
          ..moveTo(center.dx, center.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(right.dx, right.dy)
          ..close();
        canvas.drawPath(
          cone,
          Paint()..color = style.active.withValues(alpha: 0.3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.currentPointId != currentPointId ||
        oldDelegate.viewWorldYawDeg != viewWorldYawDeg ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.style != style;
  }
}