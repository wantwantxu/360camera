import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'angle_utils.dart';
import 'compass_utils.dart';

/// Lightweight compass sampler for anchoring a panorama's longitude 0°.
///
/// Only used to make the schematic minimap/hotspots coherent; it never claims
/// survey-grade positioning.
class HeadingSampler {
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;

  AccelerometerEvent? _lastAcc;
  MagnetometerEvent? _lastMag;
  double? _smoothedHeading;
  CompassReading? _latest;
  DateTime? _lastEmit;

  double? get headingDeg => _smoothedHeading;
  CompassReading? get reading => _latest;

  bool get isReliable {
    final mag = _latest?.fieldMagnitudeUt;
    return _smoothedHeading != null && mag != null && mag >= 15 && mag <= 110;
  }

  void start() {
    _magSub ??= magnetometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _lastMag = event;
      _recompute();
    });
    _accSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _lastAcc = event;
      _recompute();
    });
  }

  void _recompute() {
    final acc = _lastAcc;
    final mag = _lastMag;
    if (acc == null || mag == null) return;
    final now = DateTime.now();
    if (_lastEmit != null &&
        now.difference(_lastEmit!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastEmit = now;

    final reading = computeCompassReading(
      ax: acc.x,
      ay: acc.y,
      az: acc.z,
      mx: mag.x,
      my: mag.y,
      mz: mag.z,
    );
    if (reading == null) return;
    _latest = reading;
    final previous = _smoothedHeading;
    if (previous == null) {
      _smoothedHeading = reading.headingDeg;
    } else {
      final delta = normalizeDeg180(reading.headingDeg - previous);
      _smoothedHeading = normalizeDeg360(previous + delta * 0.25);
    }
  }

  void dispose() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
  }
}

double? sanitizeHeading(double? heading) {
  if (heading == null || heading.isNaN || heading.isInfinite) return null;
  return normalizeDeg360(heading);
}