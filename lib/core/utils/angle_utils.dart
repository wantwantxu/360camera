import 'dart:math' as math;

double degToRad(double deg) => deg * math.pi / 180.0;
double radToDeg(double rad) => rad * 180.0 / math.pi;

double normalizeDeg360(double deg) {
  var v = deg % 360.0;
  if (v < 0) v += 360.0;
  return v;
}

double normalizeDeg180(double deg) {
  var v = normalizeDeg360(deg + 180.0) - 180.0;
  return v;
}

double clampPitch(double pitch) => pitch.clamp(-89.0, 89.0);

/// Great-circle style angular distance on yaw/pitch sphere (degrees).
double sphericalAngleDeg(double yaw1, double pitch1, double yaw2, double pitch2) {
  final y1 = degToRad(yaw1);
  final p1 = degToRad(pitch1);
  final y2 = degToRad(yaw2);
  final p2 = degToRad(pitch2);
  final cosD = math.sin(p1) * math.sin(p2) +
      math.cos(p1) * math.cos(p2) * math.cos(y1 - y2);
  return radToDeg(math.acos(cosD.clamp(-1.0, 1.0)));
}

String formatSignedDeg(double value, {int digits = 1}) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(digits)}°';
}

String formatYawDeg(double value, {int digits = 1}) {
  return '${normalizeDeg360(value).toStringAsFixed(digits).padLeft(5 + digits, '0')}°';
}
