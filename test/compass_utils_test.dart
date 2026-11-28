import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/core/utils/angle_utils.dart';
import 'package:pano_360_pro/core/utils/compass_utils.dart';

// Device held upright (screen facing the user): gravity reaction points along
// +Y and the rear camera looks along -Z.
const _uprightAccel = (x: 0.0, y: 9.81, z: 0.0);

CompassReading? _readingForField(double mx, double my, double mz) {
  return computeCompassReading(
    ax: _uprightAccel.x,
    ay: _uprightAccel.y,
    az: _uprightAccel.z,
    mx: mx,
    my: my,
    mz: mz,
  );
}

void main() {
  group('computeCompassReading', () {
    test('camera facing magnetic north reads 0°', () {
      final reading = _readingForField(0, 0, -40)!;
      expect(reading.headingDeg, closeTo(0, 0.01));
      expect(reading.cameraPitchDeg, closeTo(0, 0.01));
      expect(reading.rollDeg, closeTo(0, 0.01));
      expect(reading.fieldMagnitudeUt, closeTo(40, 0.01));
    });

    test('camera facing east reads 90°', () {
      final reading = _readingForField(-40, 0, 0)!;
      expect(reading.headingDeg, closeTo(90, 0.01));
    });

    test('camera facing west reads 270°', () {
      final reading = _readingForField(40, 0, 0)!;
      expect(reading.headingDeg, closeTo(270, 0.01));
    });

    test('flat device cannot define a horizontal bearing', () {
      final reading = computeCompassReading(
        ax: 0,
        ay: 0,
        az: 9.81,
        mx: 0,
        my: 0,
        mz: -40,
      );
      expect(reading, isNull);
    });

    test('upright device with tiny field returns null', () {
      expect(_readingForField(0.1, 0, 0), isNull);
    });

    test('device pointing nearly at the ground returns null', () {
      final reading = computeCompassReading(
        ax: 0,
        ay: 0.087 * 9.81,
        az: 0.996 * 9.81,
        mx: 0,
        my: 0,
        mz: -40,
      );
      expect(reading, isNull);
    });
  });

  group('labels and formatting', () {
    test('compassLabel snaps to eight sectors', () {
      expect(compassLabel(0), '北');
      expect(compassLabel(44), '东北');
      expect(compassLabel(90), '东');
      expect(compassLabel(180), '南');
      expect(compassLabel(315), '西北');
      expect(compassLabel(350), '北');
    });

    test('formatAzimuth normalizes', () {
      expect(formatAzimuth(null), '—');
      expect(formatAzimuth(450), '90° 东');
      expect(formatAzimuth(-90), '270° 西');
    });

    test('formatDelta', () {
      expect(formatDelta(0.4), '0°');
      expect(formatDelta(12.4), '右偏 12°');
      expect(formatDelta(-12.4), '左偏 12°');
      expect(formatDelta(350), '左偏 10°');
    });
  });

  group('describeTurn', () {
    test('within aligned threshold', () {
      final g = describeTurn(9.5);
      expect(g.isAligned, isTrue);
      expect(g.isNear, isTrue);
      expect(g.text, '已对准目标方向');
    });

    test('near threshold', () {
      final g = describeTurn(21);
      expect(g.isAligned, isFalse);
      expect(g.isNear, isTrue);
      expect(g.text, contains('向右'));
      expect(g.text, contains('21°'));
    });

    test('large deviation', () {
      final g = describeTurn(-40);
      expect(g.isNear, isFalse);
      expect(g.text, contains('向左'));
      expect(g.deltaDeg, closeTo(-40, 1e-9));
      expect(g.magnitudeDeg, closeTo(40, 1e-9));
    });
  });

  group('angle utils', () {
    test('normalizeDeg360', () {
      expect(normalizeDeg360(-1), closeTo(359, 1e-9));
      expect(normalizeDeg360(720), closeTo(0, 1e-9));
    });

    test('normalizeDeg180', () {
      expect(normalizeDeg180(190), closeTo(-170, 1e-9));
      expect(normalizeDeg180(-190), closeTo(170, 1e-9));
    });
  });
}