import 'dart:math' as math;

import 'angle_utils.dart';

/// Time-based adaptive low-pass filter for device attitude.
///
/// While the phone is nearly still the filter strongly attenuates compass and
/// accelerometer noise so on-screen targets stop trembling. While the user is
/// actually turning, the time constant shrinks so guidance stays responsive.
class AttitudeFilter {
  AttitudeFilter({
    this.stillTauMs = 420,
    this.movingTauMs = 55,
    this.deadbandSpeedDps = 8,
    this.fullSpeedDps = 150,
    this.maxAlpha = 0.42,
  });

  final double stillTauMs;
  final double movingTauMs;
  final double deadbandSpeedDps;
  final double fullSpeedDps;
  final double maxAlpha;

  double? _yaw;
  double? _pitch;
  double? _roll;
  double _yawRateDps = 0;
  double _pitchRateDps = 0;

  double? get yaw => _yaw;
  double? get pitch => _pitch;
  double? get roll => _roll;

  /// Rotation speed of the smoothed attitude, in degrees per second.
  double get rateDps => math.max(_yawRateDps, _pitchRateDps);

  void clear() {
    _yaw = null;
    _pitch = null;
    _roll = null;
    _yawRateDps = 0;
    _pitchRateDps = 0;
  }

  void snapTo({
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    _yaw = normalizeDeg360(yaw);
    _pitch = pitch.clamp(-89.0, 89.0);
    _roll = normalizeDeg180(roll);
    _yawRateDps = 0;
    _pitchRateDps = 0;
  }

  void update({
    required double yawTarget,
    required double pitchTarget,
    required double rollTarget,
    required double dtMs,
  }) {
    if (_yaw == null) {
      snapTo(yaw: yawTarget, pitch: pitchTarget, roll: rollTarget);
      return;
    }
    final dt = dtMs.clamp(4.0, 250.0);
    final yawDelta = normalizeDeg180(yawTarget - _yaw!);
    final pitchDelta = (pitchTarget - _pitch!).clamp(-180.0, 180.0);
    final rollDelta = normalizeDeg180(rollTarget - _roll!);

    final targetSpeed =
        math.max(yawDelta.abs(), pitchDelta.abs()) * 1000.0 / dt;
    final moving = ((targetSpeed - deadbandSpeedDps) /
            (fullSpeedDps - deadbandSpeedDps))
        .clamp(0.0, 1.0);
    final tau = stillTauMs + (movingTauMs - stillTauMs) * moving;
    final alpha =
        math.min(maxAlpha, 1 - math.exp(-dt / math.max(1.0, tau)));

    final prevYaw = _yaw!;
    final prevPitch = _pitch!;
    _yaw = normalizeDeg360(prevYaw + yawDelta * alpha);
    _pitch = (_pitch! + pitchDelta * alpha).clamp(-89.0, 89.0);
    _roll = normalizeDeg180(_roll! + rollDelta * alpha);

    _yawRateDps = normalizeDeg180(_yaw! - prevYaw).abs() * 1000.0 / dt;
    _pitchRateDps = (_pitch! - prevPitch).abs() * 1000.0 / dt;
  }
}
