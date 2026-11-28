import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/angle_utils.dart';
import '../../../core/utils/compass_utils.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../widgets/glass.dart';
import '../inspection_state.dart';

class WaypointGuidanceOverlay extends StatelessWidget {
  const WaypointGuidanceOverlay({
    super.key,
    required this.inspection,
    required this.onOpenDetails,
    required this.onExit,
  });

  final InspectionState inspection;
  final VoidCallback onOpenDetails;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final point = inspection.activePoint;
    if (point == null) return const SizedBox.shrink();
    final top = MediaQuery.paddingOf(context).top + 64;

    return Stack(
      children: [
        Positioned.fill(
          child: TargetArMarker(
            headingDeg: inspection.headingDeg,
            targetAzimuthDeg: point.targetAzimuthDeg,
            targetPitchDeg: point.targetPitchDeg,
            cameraPitchDeg: inspection.cameraPitchDeg,
            compassReliable: inspection.compassReliable,
            code: point.code,
            show: inspection.stage == InspectionStage.positioning ||
                inspection.stage == InspectionStage.aligning ||
                inspection.stage == InspectionStage.ready,
          ),
        ),
        if (inspection.deviceRollDeg != null &&
            inspection.stage != InspectionStage.briefing)
          LevelIndicator(rollDeg: inspection.deviceRollDeg!),
        Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Column(
            children: [
              InspectionInfoCard(
                inspection: inspection,
                onOpenDetails: onOpenDetails,
                onExit: onExit,
              ),
              const SizedBox(height: 8),
              CompassRibbon(
                headingDeg: inspection.headingDeg,
                targetAzimuthDeg: point.targetAzimuthDeg,
                deltaDeg: inspection.directionDeltaDeg,
                compassAvailable: inspection.compassAvailable,
                compassInterfered: inspection.compassInterfered,
              ),
            ],
          ),
        ),
        if (inspection.stage == InspectionStage.aligning ||
            inspection.stage == InspectionStage.ready)
          Positioned(
            left: 24,
            right: 24,
            bottom: 238,
            child: TurnHint(
              hasTarget: point.hasTargetAzimuth,
              compassReliable: inspection.compassReliable,
              compassInterfered: inspection.compassInterfered,
              headingAvailable: inspection.headingDeg != null,
              deltaDeg: inspection.directionDeltaDeg,
              manualConfirmed: inspection.manualDirectionConfirmed,
            ),
          ),
      ],
    );
  }
}

class InspectionInfoCard extends StatelessWidget {
  const InspectionInfoCard({
    super.key,
    required this.inspection,
    required this.onOpenDetails,
    required this.onExit,
  });

  final InspectionState inspection;
  final VoidCallback onOpenDetails;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final point = inspection.activePoint;
    final task = inspection.activeTask;
    if (point == null || task == null) return const SizedBox.shrink();

    final gps = _gpsChip();
    final compass = _compassChip();
    final target = point.hasTargetAzimuth
        ? '目标 ${formatAzimuth(point.targetAzimuthDeg)}'
        : '未设目标方向';
    final distance = point.hasCoordinates
        ? '距离 ${formatDistance(inspection.distanceM)}'
        : '未设点位坐标';

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 14, color: PanoColors.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PanoColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (task.isSample) ...[
                const _Badge(text: '示例数据', color: PanoColors.cyan),
                const SizedBox(width: 6),
              ],
              Text(
                '${inspection.taskCompletedCount}/${task.points.length}',
                style: const TextStyle(
                  color: PanoColors.amber,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onExit,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: PanoColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onOpenDetails,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _Badge(
                    text: point.code,
                    color: PanoColors.amber,
                    filled: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  _Badge(
                    text: point.completed ? '已完成 ${point.captureCount} 次' : '未完成',
                    color: point.completed ? PanoColors.emerald : PanoColors.textMuted,
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 16, color: PanoColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Badge(text: inspection.stage.label, color: PanoColors.cyan),
              _Badge(text: gps.$1, color: gps.$2),
              _Badge(
                text: distance,
                color: inspection.withinArrivalRange
                    ? PanoColors.emerald
                    : PanoColors.textSecondary,
              ),
              _Badge(text: target, color: PanoColors.amber),
              _Badge(text: compass.$1, color: compass.$2),
            ],
          ),
          if (point.description.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              point.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PanoColors.textSecondary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _gpsChip() {
    final accuracy = inspection.gpsAccuracyM;
    return switch (inspection.gpsStatus) {
      LocationUiStatus.fixed => (
          accuracy == null ? 'GPS 已定位' : 'GPS ±${accuracy.round()} m',
          inspection.gpsAccuracyGood ? PanoColors.emerald : PanoColors.amber,
        ),
      LocationUiStatus.locating => ('定位中…', PanoColors.cyan),
      LocationUiStatus.noCoordinates => ('无点位坐标', PanoColors.textMuted),
      LocationUiStatus.serviceDisabled => ('GPS 未开启', PanoColors.rose),
      LocationUiStatus.permissionDenied => ('定位未授权', PanoColors.rose),
      LocationUiStatus.permissionDeniedForever => ('定位权限关闭', PanoColors.rose),
      LocationUiStatus.error => ('定位异常', PanoColors.rose),
      LocationUiStatus.idle => ('待定位', PanoColors.textMuted),
    };
  }

  (String, Color) _compassChip() {
    if (inspection.compassInterfered) {
      return ('磁干扰', PanoColors.rose);
    }
    if (!inspection.compassAvailable) {
      return ('罗盘不可用', PanoColors.textMuted);
    }
    final heading = inspection.headingDeg;
    if (heading == null) {
      return ('请竖直握持', PanoColors.amber);
    }
    return ('罗盘 ${heading.round()}°', PanoColors.cyan);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: filled ? color.withValues(alpha: 0.6) : PanoColors.borderSubtle,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: filled ? 'monospace' : null,
        ),
      ),
    );
  }
}

class CompassRibbon extends StatelessWidget {
  const CompassRibbon({
    super.key,
    required this.headingDeg,
    required this.targetAzimuthDeg,
    required this.deltaDeg,
    required this.compassAvailable,
    required this.compassInterfered,
  });

  final double? headingDeg;
  final double? targetAzimuthDeg;
  final double? deltaDeg;
  final bool compassAvailable;
  final bool compassInterfered;

  @override
  Widget build(BuildContext context) {
    final heading = headingDeg;
    final aligned = deltaDeg != null &&
        deltaDeg!.abs() <= PanoConstants.waypointAlignEnterDeg;
    final statusColor = compassInterfered
        ? PanoColors.rose
        : aligned
            ? PanoColors.emerald
            : PanoColors.amber;

    return GlassPanel(
      borderRadius: 14,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: heading == null
                ? Center(
                    child: Text(
                      compassAvailable
                          ? '请竖直握持手机以获取拍摄方向'
                          : '正在等待方向传感器…',
                      style: const TextStyle(
                        color: PanoColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 36),
                    painter: _CompassPainter(
                      heading: heading,
                      target: targetAzimuthDeg,
                      aligned: aligned,
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '当前 ${formatAzimuth(heading)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: heading == null ? PanoColors.textMuted : PanoColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Text(
                targetAzimuthDeg == null
                    ? '目标方向未设置'
                    : '目标 ${formatAzimuth(targetAzimuthDeg)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: PanoColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
              if (deltaDeg != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatDelta(deltaDeg!),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.heading,
    required this.target,
    required this.aligned,
  });

  final double heading;
  final double? target;
  final bool aligned;

  static const _range = 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final minor = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final major = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.4;

    final start = ((heading - _range) / 15).ceil() * 15;
    for (var a = start; a <= heading + _range; a += 15) {
      final delta = normalizeDeg180(a - heading);
      if (delta.abs() > _range) continue;
      final x = cx + delta / _range * size.width / 2;
      final abs = normalizeDeg360(a.toDouble());
      final isMajor = (abs % 45).abs() < 0.01;
      canvas.drawLine(
        Offset(x, isMajor ? 4 : 9),
        Offset(x, 18),
        isMajor ? major : minor,
      );
      if (isMajor) {
        final label = compassLabel(abs);
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: PanoColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 20));
      }
    }

    final targetAzimuth = target;
    final targetDelta = targetAzimuth == null
        ? null
        : normalizeDeg180(targetAzimuth - heading);
    if (targetDelta != null) {
      final clamped = targetDelta.clamp(-_range, _range).toDouble();
      final x = cx + clamped / _range * size.width / 2;
      final color = aligned ? PanoColors.emerald : PanoColors.amber;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 2), Offset(x, 29), paint);
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x - 4.5, 7)
        ..lineTo(x + 4.5, 7)
        ..close();
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
      if (targetDelta.abs() > _range) {
        final edge = targetDelta > 0 ? x + 5 : x - 5;
        canvas.drawCircle(Offset(edge, 6), 2.2, Paint()..color = color);
      }
    }

    final center = Paint()
      ..color = PanoColors.amber
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cx, 24), Offset(cx, 33), center);
    final caret = Path()
      ..moveTo(cx, 29)
      ..lineTo(cx - 4, 36)
      ..lineTo(cx + 4, 36)
      ..close();
    canvas.drawPath(caret, Paint()..color = PanoColors.amber);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.target != target ||
      oldDelegate.aligned != aligned;
}

class TargetArMarker extends StatelessWidget {
  const TargetArMarker({
    super.key,
    required this.headingDeg,
    required this.targetAzimuthDeg,
    required this.targetPitchDeg,
    required this.cameraPitchDeg,
    required this.compassReliable,
    required this.code,
    required this.show,
  });

  final double? headingDeg;
  final double? targetAzimuthDeg;
  final double targetPitchDeg;
  final double? cameraPitchDeg;
  final bool compassReliable;
  final String code;
  final bool show;

  @override
  Widget build(BuildContext context) {
    final heading = headingDeg;
    final target = targetAzimuthDeg;
    if (!show || !compassReliable || heading == null || target == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final delta = normalizeDeg180(target - heading);
        final fov = PanoConstants.defaultFov;
        final halfFovX = fov * (w / h) / 2;
        final aligned = delta.abs() <= PanoConstants.waypointAlignEnterDeg;
        final color = aligned ? PanoColors.emerald : PanoColors.amber;

        if (delta.abs() > halfFovX * 0.92) {
          final toRight = delta > 0;
          return Stack(
            children: [
              Positioned(
                top: h * 0.42,
                left: toRight ? null : 16,
                right: toRight ? 16 : null,
                child: IgnorePointer(
                  child: GlassPill(
                    color: const Color(0xCC09090B),
                    borderColor: color.withValues(alpha: 0.65),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          toRight ? Icons.arrow_forward : Icons.arrow_back,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '目标在${toRight ? '右' : '左'}侧 ${delta.abs().round()}°',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final pitchDelta = targetPitchDeg - (cameraPitchDeg ?? 0);
        final halfFovY = fov / 2;
        final x =
            (w / 2 + delta / halfFovX * (w / 2) * 0.9).clamp(48.0, w - 48.0).toDouble();
        final rawY = h / 2 - pitchDelta / halfFovY * (h / 2) * 0.75;
        final y = rawY.clamp(h * 0.42, h * 0.68).toDouble();
        final pitchText = pitchDelta.abs() < 3
            ? ''
            : '${pitchDelta > 0 ? '抬高' : '压低'} ${pitchDelta.abs().round()}°';

        return Stack(
          children: [
            Positioned(
              left: x - 42,
              top: y - 42,
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.18),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flag_rounded, size: 18, color: color),
                          const SizedBox(height: 2),
                          Text(
                            code,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Text(
                            '目标方向',
                            style: TextStyle(
                              color: PanoColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (pitchText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xCC09090B),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          pitchText,
                          style: const TextStyle(
                            color: PanoColors.textSecondary,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class LevelIndicator extends StatelessWidget {
  const LevelIndicator({super.key, required this.rollDeg});

  final double rollDeg;

  @override
  Widget build(BuildContext context) {
    final level = rollDeg.abs() <= PanoConstants.rollWarnDeg;
    final color = level ? PanoColors.emerald : PanoColors.amber;
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -26),
          child: Transform.rotate(
            angle: degToRad(rollDeg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 150,
                  height: 18,
                  child: Row(
                    children: [
                      _wing(color),
                      const SizedBox(width: 6),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _wing(color),
                    ],
                  ),
                ),
                Text(
                  level ? '水平' : '倾斜 ${rollDeg.abs().round()}°',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wing(Color color) {
    return Expanded(
      child: Container(
        height: 1.4,
        color: color,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class TurnHint extends StatelessWidget {
  const TurnHint({
    super.key,
    required this.hasTarget,
    required this.compassReliable,
    required this.compassInterfered,
    required this.headingAvailable,
    required this.deltaDeg,
    required this.manualConfirmed,
  });

  final bool hasTarget;
  final bool compassReliable;
  final bool compassInterfered;
  final bool headingAvailable;
  final double? deltaDeg;
  final bool manualConfirmed;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    final Color color;
    if (!hasTarget) {
      color = PanoColors.textSecondary;
      content = const _HintContent(
        icon: Icons.info_outline,
        color: PanoColors.textSecondary,
        text: '该点位未设置目标方向，确认位置后可直接拍摄',
      );
    } else if (manualConfirmed) {
      color = PanoColors.amber;
      content = const _HintContent(
        icon: Icons.touch_app_outlined,
        color: PanoColors.amber,
        text: '方向已手动确认（未经传感器校验）',
      );
    } else if (compassInterfered) {
      color = PanoColors.rose;
      content = const _HintContent(
        icon: Icons.warning_amber_rounded,
        color: PanoColors.rose,
        text: '电子罗盘受到干扰，请远离金属并校准',
      );
    } else if (!compassReliable || deltaDeg == null) {
      color = PanoColors.amber;
      content = _HintContent(
        icon: Icons.screen_rotation,
        color: PanoColors.amber,
        text: headingAvailable ? '方向不可用，请使用参考照片对齐' : '请竖直握持手机以获取方向',
      );
    } else {
      final delta = deltaDeg!;
      final aligned = delta.abs() <= PanoConstants.waypointAlignEnterDeg;
      final text = describeTurn(
        delta,
        alignedThresholdDeg: PanoConstants.waypointAlignEnterDeg,
        nearThresholdDeg: PanoConstants.waypointAlignNearDeg,
      ).text;
      color = aligned ? PanoColors.emerald : PanoColors.amber;
      content = _HintContent(
        icon: aligned
            ? Icons.check_circle_outline
            : (delta > 0 ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
        color: color,
        text: text,
        emphasize: true,
      );
    }

    return Center(
      child: GlassPill(
        color: const Color(0xE009090B),
        borderColor: color.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: content,
      ),
    );
  }
}

class _HintContent extends StatelessWidget {
  const _HintContent({
    required this.icon,
    required this.color,
    required this.text,
    this.emphasize = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: emphasize ? 22 : 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: emphasize ? 14 : 12,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}