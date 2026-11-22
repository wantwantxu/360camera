import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/angle_utils.dart';
import '../../../domain/capture_point.dart';
import '../../../widgets/glass.dart';

class CaptureProgressCard extends StatelessWidget {
  const CaptureProgressCard({
    super.key,
    required this.upper,
    required this.mid,
    required this.lower,
    required this.total,
  });

  final int upper;
  final int mid;
  final int lower;
  final int total;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ring(PanoColors.cyan, '仰拍', '$upper/3'),
              const SizedBox(width: 10),
              _ring(PanoColors.amber, '水平', '$mid/8'),
              const SizedBox(width: 10),
              _ring(PanoColors.emerald, '俯拍', '$lower/3'),
              const Spacer(),
              Text(
                '$total/14',
                style: const TextStyle(
                  color: PanoColors.amber,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total / PanoConstants.maxCapturePoints,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(PanoColors.amber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(Color c, String label, String val) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: PanoColors.textSecondary, fontSize: 11)),
        const SizedBox(width: 4),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
      ],
    );
  }
}

class CenterReticle extends StatelessWidget {
  const CenterReticle({
    super.key,
    required this.roll,
    required this.lockProgress,
    required this.statusText,
    required this.warn,
  });

  final double roll;
  final double lockProgress;
  final String statusText;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final tilted = roll.abs() > PanoConstants.rollWarnDeg;
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: _LockRingPainter(progress: lockProgress),
                ),
              ),
              Transform.rotate(
                angle: degToRad(roll),
                child: SizedBox(
                  width: 164,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _wing(tilted),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                      ),
                      _wing(tilted),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ColoredBox(
                      color: Colors.white.withValues(alpha: 0.9),
                      child: const SizedBox(width: 28, height: 1.5),
                    ),
                    ColoredBox(
                      color: Colors.white.withValues(alpha: 0.9),
                      child: const SizedBox(width: 1.5, height: 28),
                    ),
                    const ColoredBox(
                      color: PanoColors.amber,
                      child: SizedBox(width: 6, height: 6),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                child: GlassPill(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  borderColor: warn ? PanoColors.rose.withValues(alpha: 0.55) : PanoColors.borderSubtle,
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: warn ? const Color(0xFFFDA4AF) : PanoColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wing(bool tilted) {
    return Container(
      width: 42,
      height: 2,
      decoration: BoxDecoration(
        color: tilted ? PanoColors.rose : PanoColors.emerald,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: (tilted ? PanoColors.rose : PanoColors.emerald).withValues(alpha: 0.6),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _LockRingPainter extends CustomPainter {
  _LockRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final bg = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..color = PanoColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _LockRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class ArTargetsOverlay extends StatelessWidget {
  const ArTargetsOverlay({
    super.key,
    required this.points,
    required this.yaw,
    required this.pitch,
    required this.fov,
    required this.lockedId,
  });

  final List<CapturePoint> points;
  final double yaw;
  final double pitch;
  final double fov;
  final String? lockedId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final children = <Widget>[];
        for (final p in points) {
          final projected = _project(p.yaw, p.pitch, w, h);
          if (projected == null) continue;
          final aligned = lockedId == p.id;
          final color = switch (p.ring) {
            CaptureRing.upper => PanoColors.cyan,
            CaptureRing.mid => PanoColors.amber,
            CaptureRing.lower => PanoColors.emerald,
          };
          children.add(
            Positioned(
              left: projected.dx - 28,
              top: projected.dy - 28,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (p.captured ? PanoColors.emerald : color)
                      .withValues(alpha: aligned ? 0.36 : 0.15),
                  border: Border.all(
                    color: p.captured
                        ? PanoColors.emerald
                        : aligned
                            ? Colors.white
                            : color,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.id,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: p.captured ? const Color(0xFF6EE7B7) : color,
                      ),
                    ),
                    Text(
                      '${p.yaw.toInt()}°',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: (p.captured ? const Color(0xFF6EE7B7) : color)
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  Offset? _project(double ty, double tp, double w, double h) {
    final dy = normalizeDeg180(ty - yaw);
    final dp = tp - pitch;
    final halfFovX = fov * (w / h) / 2;
    final halfFovY = fov / 2;
    if (dy.abs() > halfFovX * 1.35 || dp.abs() > halfFovY * 1.35) return null;
    final x = w / 2 + (dy / halfFovX) * (w / 2) * 0.85;
    final y = h / 2 - (dp / halfFovY) * (h / 2) * 0.85;
    return Offset(x, y);
  }
}

class MiniRadar extends StatelessWidget {
  const MiniRadar({
    super.key,
    required this.points,
    required this.yaw,
    required this.onTap,
    required this.onReset,
  });

  final List<CapturePoint> points;
  final double yaw;
  final VoidCallback onTap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: GlassPanel(
            borderRadius: 60,
            padding: const EdgeInsets.all(6),
            child: CustomPaint(
              size: const Size(108, 108),
              painter: _RadarPainter(points: points, yaw: yaw),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GlassPill(
          onTap: onReset,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: const Text('重置', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.points, required this.yaw});
  final List<CapturePoint> points;
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = Colors.white10);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white24
        ..strokeWidth = 1,
    );
    canvas.drawCircle(c, r * 0.55, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white12
      ..strokeWidth = 1);

    // View wedge
    final wedge = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: r),
        degToRad(-90 - 35),
        degToRad(70),
        false,
      )
      ..close();
    canvas.drawPath(wedge, Paint()..color = PanoColors.amber.withValues(alpha: 0.18));

    for (final p in points) {
      final ang = degToRad(p.yaw - yaw - 90);
      final pr = switch (p.ring) {
        CaptureRing.upper => r * 0.35,
        CaptureRing.mid => r * 0.62,
        CaptureRing.lower => r * 0.88,
      };
      final pos = Offset(c.dx + math.cos(ang) * pr, c.dy + math.sin(ang) * pr);
      final color = p.captured
          ? PanoColors.emerald
          : switch (p.ring) {
              CaptureRing.upper => PanoColors.cyan,
              CaptureRing.mid => PanoColors.amber,
              CaptureRing.lower => PanoColors.emerald,
            };
      canvas.drawCircle(pos, p.captured ? 3.5 : 2.8, Paint()..color = color);
    }

    // Center heading
    canvas.drawCircle(c, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.yaw != yaw || oldDelegate.points != points;
}
