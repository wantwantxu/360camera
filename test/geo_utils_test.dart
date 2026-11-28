import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/core/utils/geo_utils.dart';

void main() {
  group('distanceMeters', () {
    test('one degree of latitude is about 111 km', () {
      final d = distanceMeters(lat1: 0, lon1: 0, lat2: 1, lon2: 0);
      expect(d, closeTo(111195, 5));
    });

    test('identical points yield zero', () {
      final d = distanceMeters(
        lat1: 31.230416,
        lon1: 121.473701,
        lat2: 31.230416,
        lon2: 121.473701,
      );
      expect(d, closeTo(0, 1e-6));
    });

    test('longitude spacing shrinks with latitude', () {
      final equator = distanceMeters(lat1: 0, lon1: 0, lat2: 0, lon2: 1);
      final highLat = distanceMeters(lat1: 60, lon1: 0, lat2: 60, lon2: 1);
      expect(highLat, lessThan(equator));
      expect(highLat / equator, closeTo(0.5, 0.01));
    });
  });

  group('initialBearingDeg', () {
    test('cardinal bearings', () {
      expect(initialBearingDeg(lat1: 0, lon1: 0, lat2: 1, lon2: 0), closeTo(0, 1e-9));
      expect(initialBearingDeg(lat1: 0, lon1: 0, lat2: 0, lon2: 1), closeTo(90, 1e-9));
      expect(initialBearingDeg(lat1: 1, lon1: 0, lat2: 0, lon2: 0), closeTo(180, 1e-9));
      expect(initialBearingDeg(lat1: 0, lon1: 1, lat2: 0, lon2: 0), closeTo(270, 1e-9));
    });

    test('result stays in [0, 360)', () {
      final b = initialBearingDeg(lat1: -33.86, lon1: 151.2, lat2: 51.5, lon2: -0.12);
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
    });
  });

  group('formatting', () {
    test('formatDistance', () {
      expect(formatDistance(null), '—');
      expect(formatDistance(12.4), '12 m');
      expect(formatDistance(999.9), '1000 m');
      expect(formatDistance(1000), '1.00 km');
      expect(formatDistance(1534), '1.53 km');
    });

    test('formatCoordinates uses six decimals', () {
      expect(formatCoordinates(31.2, -121.5), '31.200000, -121.500000');
    });
  });
}