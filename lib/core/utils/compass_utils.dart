import 'dart:math' as math;

import 'angle_utils.dart';

/// Result of fusing raw accelerometer (gravity) and magnetometer readings.
class CompassReading {
  const CompassReading({
    required this.headingDeg,
    required this.cameraPitchDeg,
    required this.rollDeg,
    required this.fieldMagnitudeUt,
  });

  /// Compass bearing of the rear camera axis, degrees clockwise from magnetic north.
  final double headingDeg;

  /// Camera axis elevation, positive when pointing upward.
  final double cameraPitchDeg;

  /// Device tilt around the viewing axis (0 = upright portrait, level horizon).
  final double rollDeg;

  /// Raw magnetic field magnitude in µT.
  final double fieldMagnitudeUt;
}

/// Computes the physical direction the rear camera points toward.
///
/// Uses Android/iOS sensor conventions: accelerometer reports the world "up"
/// direction (gravity reaction) and magnetometer reports the local magnetic
/// field vector, both in device coordinates. Returns null when the phone is
/// held nearly flat (camera pointing at the ground/sky) because a horizontal
/// bearing is then geometrically undefined.
CompassReading? computeCompassReading({
  required double ax,
  required double ay,
  required double az,
  required double mx,
  required double my,
  required double mz,
}) {
  final upLen = math.sqrt(ax * ax + ay * ay + az * az);
  if (upLen < 1e-3) return null;
  final ux = ax / upLen;
  final uy = ay / upLen;
  final uz = az / upLen;

  final fieldLen = math.sqrt(mx * mx + my * my + mz * mz);
  if (fieldLen < 1e-3) return null;

  final mDotU = mx * ux + my * uy + mz * uz;
  final hx = mx - ux * mDotU;
  final hy = my - uy * mDotU;
  final hz = mz - uz * mDotU;
  final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
  if (hLen < 3.0) return null;
  final nx = hx / hLen;
  final ny = hy / hLen;
  final nz = hz / hLen;

  // East = north × up.
  final ex = ny * uz - nz * uy;
  final ey = nz * ux - nx * uz;
  final ez = nx * uy - ny * ux;
  final eLen = math.sqrt(ex * ex + ey * ey + ez * ez);
  if (eLen < 1e-3) return null;
  final eNx = ex / eLen;
  final eNy = ey / eLen;
  final eNz = ez / eLen;

  // Rear camera looks along -Z.
  const fx = 0.0;
  const fy = 0.0;
  const fz = -1.0;
  final fDotU = fz * uz;
  var hx2 = fx - ux * fDotU;
  var hy2 = fy - uy * fDotU;
  var hz2 = fz - uz * fDotU;
  final fhLen = math.sqrt(hx2 * hx2 + hy2 * hy2 + hz2 * hz2);
  if (fhLen < 0.12) return null;
  hx2 /= fhLen;
  hy2 /= fhLen;
  hz2 /= fhLen;

  final heading = math.atan2(
        hx2 * eNx + hy2 * eNy + hz2 * eNz,
        hx2 * nx + hy2 * ny + hz2 * nz,
      ) *
      180.0 /
      math.pi;

  final pitch = math.asin((fDotU).clamp(-1.0, 1.0)) * 180.0 / math.pi;
  final roll = math.atan2(-ux, uy) * 180.0 / math.pi;

  return CompassReading(
    headingDeg: normalizeDeg360(heading),
    cameraPitchDeg: pitch,
    rollDeg: roll,
    fieldMagnitudeUt: fieldLen,
  );
}

const List<String> _compassLabels = [
  '北',
  '东北',
  '东',
  '东南',
  '南',
  '西南',
  '西',
  '西北',
];

String compassLabel(double azimuthDeg) {
  final index = ((normalizeDeg360(azimuthDeg) + 22.5) ~/ 45) % 8;
  return _compassLabels[index];
}

String formatAzimuth(double? azimuthDeg) {
  if (azimuthDeg == null) return '—';
  final deg = normalizeDeg360(azimuthDeg);
  return '${deg.toStringAsFixed(0)}° ${compassLabel(deg)}';
}

class TurnGuidance {
  const TurnGuidance({
    required this.deltaDeg,
    required this.magnitudeDeg,
    required this.isAligned,
    required this.isNear,
    required this.text,
  });

  /// Signed shortest rotation from current heading to target (positive = turn right).
  final double deltaDeg;
  final double magnitudeDeg;
  final bool isAligned;
  final bool isNear;
  final String text;
}

TurnGuidance describeTurn(
  double deltaDeg, {
  double alignedThresholdDeg = 10,
  double nearThresholdDeg = 30,
}) {
  final delta = normalizeDeg180(deltaDeg);
  final magnitude = delta.abs();
  if (magnitude <= alignedThresholdDeg) {
    return TurnGuidance(
      deltaDeg: delta,
      magnitudeDeg: magnitude,
      isAligned: true,
      isNear: true,
      text: '已对准目标方向',
    );
  }
  final side = delta > 0 ? '向右' : '向左';
  final near = magnitude <= nearThresholdDeg;
  return TurnGuidance(
    deltaDeg: delta,
    magnitudeDeg: magnitude,
    isAligned: false,
    isNear: near,
    text: near ? '微调：$side约 ${magnitude.round()}°' : '请$side转约 ${magnitude.round()}°',
  );
}

/// Formats a bearing delta for compact HUD display (e.g. "右偏 12°").
String formatDelta(double deltaDeg) {
  final delta = normalizeDeg180(deltaDeg);
  if (delta.abs() < 1) return '0°';
  return '${delta > 0 ? '右偏' : '左偏'} ${delta.abs().round()}°';
}