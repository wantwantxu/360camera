import 'dart:math' as math;

/// Integrates the device gyroscope into a compass-heading change for
/// pure-rotation panorama capture.
///
/// The compass heading of the rear camera increases when the device turns to
/// the right. With the accelerometer reporting the device-frame world-up
/// vector, a right-hand-rule rotation about that up axis is positive when
/// turning left, hence the minus sign. A slowly adapted zero-rate bias is
/// subtracted once the device has been held still (the auto-lock hold window),
/// so integration does not accumulate one-sided drift between shots.
class GyroHeadingTracker {
  static const double _stillRateRad = 0.07;
  static const double _stillAdaptMs = 250;
  static const double _maxStepSeconds = 0.25;

  double _headingRad = 0;
  DateTime? _lastAt;
  double _biasX = 0;
  double _biasY = 0;
  double _biasZ = 0;
  double _stillMs = 0;

  /// Number of accepted integration steps since [reset].
  int samples = 0;

  /// Accumulated heading change in degrees (compass convention, wrapped).
  double get headingDeg => _headingRad * 180 / math.pi;

  void reset() {
    _headingRad = 0;
    _lastAt = null;
    _biasX = 0;
    _biasY = 0;
    _biasZ = 0;
    _stillMs = 0;
    samples = 0;
  }

  /// Feeds one gyroscope sample (rad/s, device axes) together with the
  /// device-frame world-up direction from the accelerometer.
  void addSample({
    required DateTime timestamp,
    required double gx,
    required double gy,
    required double gz,
    required double upX,
    required double upY,
    required double upZ,
  }) {
    final last = _lastAt;
    _lastAt = timestamp;
    if (last == null) return;
    final dt = timestamp.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > _maxStepSeconds) return;

    final rate = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (rate < _stillRateRad) {
      _stillMs += dt * 1000;
      if (_stillMs > _stillAdaptMs) {
        final k = 1 - math.exp(-dt / 0.4);
        _biasX += (gx - _biasX) * k;
        _biasY += (gy - _biasY) * k;
        _biasZ += (gz - _biasZ) * k;
      }
    } else {
      _stillMs = 0;
    }

    final wx = gx - _biasX;
    final wy = gy - _biasY;
    final wz = gz - _biasZ;
    _headingRad -= (wx * upX + wy * upY + wz * upZ) * dt;
    if (_headingRad > math.pi) {
      _headingRad -= 2 * math.pi;
    } else if (_headingRad < -math.pi) {
      _headingRad += 2 * math.pi;
    }
    samples++;
  }
}
