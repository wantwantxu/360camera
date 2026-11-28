import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/core/utils/gyro_heading.dart';

final _t0 = DateTime(2026, 11, 28, 12);

DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

void _feed(
  GyroHeadingTracker tracker, {
  required int fromMs,
  required int toMs,
  int stepMs = 20,
  double gx = 0,
  double gy = 0,
  double gz = 0,
  double upX = 0,
  double upY = 1,
  double upZ = 0,
}) {
  for (var t = fromMs; t <= toMs; t += stepMs) {
    tracker.addSample(
      timestamp: _at(t),
      gx: gx,
      gy: gy,
      gz: gz,
      upX: upX,
      upY: upY,
      upZ: upZ,
    );
  }
}

void main() {
  group('GyroHeadingTracker', () {
    test('a right turn raises the compass heading', () {
      final tracker = GyroHeadingTracker();
      // Upright portrait: world-up is the device +Y axis. A right turn is a
      // negative rotation about world-up in device axes.
      _feed(tracker, fromMs: 0, toMs: 1000, gy: -1);
      expect(tracker.headingDeg, closeTo(57.3, 0.2));
    });

    test('a left turn lowers the compass heading', () {
      final tracker = GyroHeadingTracker();
      _feed(tracker, fromMs: 0, toMs: 500, gy: 1);
      expect(tracker.headingDeg, closeTo(-28.65, 0.2));
    });

    test('heading wraps instead of overflowing', () {
      final tracker = GyroHeadingTracker();
      _feed(tracker, fromMs: 0, toMs: 4000, gy: -1);
      expect(tracker.headingDeg, lessThanOrEqualTo(180));
      expect(tracker.headingDeg, greaterThanOrEqualTo(-180));
    });

    test('still-device bias is learned and does not drift the heading', () {
      final tracker = GyroHeadingTracker();
      // A gyro reading 0.02 rad/s while perfectly still. Bias learning only
      // kicks in after the 250 ms still window, so a sub-degree residue is
      // expected; what matters is that it converges instead of drifting.
      _feed(tracker, fromMs: 0, toMs: 3000, gy: 0.02);
      expect(tracker.headingDeg.abs(), lessThan(1.0));

      // Now a real one-second right turn on top of the same bias.
      _feed(tracker, fromMs: 3020, toMs: 4020, gy: -0.98);
      expect(tracker.headingDeg, closeTo(57.3, 0.5));
    });

    test('samples with long gaps are not integrated', () {
      final tracker = GyroHeadingTracker();
      tracker.addSample(
        timestamp: _at(0),
        gx: 0,
        gy: -1,
        gz: 0,
        upX: 0,
        upY: 1,
        upZ: 0,
      );
      tracker.addSample(
        timestamp: _at(1000),
        gx: 0,
        gy: -1,
        gz: 0,
        upX: 0,
        upY: 1,
        upZ: 0,
      );
      expect(tracker.headingDeg, 0);
      expect(tracker.samples, 0);
    });

    test('projects the rate onto the tilted device-up axis', () {
      final tracker = GyroHeadingTracker();
      // Phone pitched 90° so device +Z is world-up: a pure z rotation turns
      // the heading, x/y rotations must not.
      _feed(tracker, fromMs: 0, toMs: 1000, gx: 2, gy: -2, upY: 0, upZ: 1);
      expect(tracker.headingDeg.abs(), lessThan(1e-9));
      _feed(tracker, fromMs: 1000, toMs: 2000, gz: -1, upY: 0, upZ: 1);
      expect(tracker.headingDeg, closeTo(57.3, 0.2));
      expect(tracker.samples, greaterThan(50));
    });

    test('heading rate uses radians per second', () {
      final tracker = GyroHeadingTracker();
      _feed(tracker, fromMs: 0, toMs: 1000, gy: -math.pi / 2);
      expect(tracker.headingDeg, closeTo(90, 0.2));
    });
  });
}
