import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/core/utils/angle_utils.dart';
import 'package:pano_360_pro/core/utils/attitude_filter.dart';

void main() {
  group('AttitudeFilter', () {
    test('attenuates sensor noise while the phone is still', () {
      final filter = AttitudeFilter();
      filter.snapTo(yaw: 10, pitch: 0, roll: 0);
      for (var i = 0; i < 400; i++) {
        final noise = i.isEven ? 0.8 : -0.8;
        filter.update(
          yawTarget: 10 + noise,
          pitchTarget: noise * 0.5,
          rollTarget: 0,
          dtMs: 20,
        );
      }
      expect((filter.yaw! - 10).abs(), lessThan(0.15));
      expect((filter.pitch!).abs(), lessThan(0.15));
      expect(filter.rateDps, lessThan(10));
    });

    test('follows a real turn without visible lag', () {
      final filter = AttitudeFilter();
      filter.snapTo(yaw: 0, pitch: 0, roll: 0);
      for (var i = 0; i < 25; i++) {
        filter.update(
          yawTarget: 40,
          pitchTarget: 0,
          rollTarget: 0,
          dtMs: 20,
        );
      }
      expect(filter.yaw!, greaterThan(30));
      expect(filter.rateDps, greaterThan(0));
    });

    test('takes the short path across the 0/360 seam', () {
      final filter = AttitudeFilter();
      filter.snapTo(yaw: 359, pitch: 0, roll: 0);
      filter.update(yawTarget: 1, pitchTarget: 0, rollTarget: 0, dtMs: 20);
      expect(filter.yaw!, greaterThan(350));
      expect(normalizeDeg180(filter.yaw! - 1).abs(), lessThan(2));
    });

    test('snapTo resets rates and clamps pitch', () {
      final filter = AttitudeFilter();
      filter.snapTo(yaw: 123, pitch: 100, roll: 30);
      expect(filter.yaw, 123);
      expect(filter.pitch, 89);
      expect(filter.roll, 30);
      expect(filter.rateDps, 0);
    });
  });
}
