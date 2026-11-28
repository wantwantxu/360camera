import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/features/inspection/guidance_logic.dart';
import 'package:pano_360_pro/features/inspection/inspection_state.dart';

void main() {
  group('isWithinArrivalRange', () {
    test('requires both distance and accuracy', () {
      expect(
        isWithinArrivalRange(distanceM: 10, accuracyM: 8, radiusM: 15),
        isTrue,
      );
      expect(
        isWithinArrivalRange(distanceM: 10, accuracyM: null, radiusM: 15),
        isFalse,
      );
      expect(
        isWithinArrivalRange(distanceM: null, accuracyM: 5, radiusM: 15),
        isFalse,
      );
    });

    test('poor accuracy blocks automatic arrival', () {
      expect(
        isWithinArrivalRange(distanceM: 2, accuracyM: 31, radiusM: 15),
        isFalse,
      );
    });

    test('distance must be inside radius', () {
      expect(
        isWithinArrivalRange(distanceM: 15.1, accuracyM: 5, radiusM: 15),
        isFalse,
      );
    });
  });

  group('hasUsableGpsFix', () {
    test('accepts up to twice the arrival accuracy', () {
      expect(hasUsableGpsFix(distanceM: 100, accuracyM: 60), isTrue);
      expect(hasUsableGpsFix(distanceM: 100, accuracyM: 60.1), isFalse);
      expect(hasUsableGpsFix(distanceM: null, accuracyM: 5), isFalse);
    });
  });

  group('evaluateGuidanceStage', () {
    InspectionStage evaluate({
      InspectionStage current = InspectionStage.aligning,
      bool arrival = true,
      bool hasTarget = true,
      bool compassReliable = true,
      bool manual = false,
      double? delta = 0,
    }) {
      return evaluateGuidanceStage(
        current: current,
        arrivalConfirmed: arrival,
        hasTargetAzimuth: hasTarget,
        compassReliable: compassReliable,
        manualDirectionConfirmed: manual,
        deltaDeg: delta,
      );
    }

    test('not arrived stays in positioning', () {
      expect(evaluate(arrival: false), InspectionStage.positioning);
    });

    test('point without target azimuth can capture once arrived', () {
      expect(evaluate(hasTarget: false), InspectionStage.ready);
    });

    test('manual direction confirmation unlocks capture', () {
      expect(
        evaluate(compassReliable: false, manual: true),
        InspectionStage.ready,
      );
    });

    test('unreliable compass or missing delta waits in aligning', () {
      expect(evaluate(compassReliable: false), InspectionStage.aligning);
      expect(evaluate(delta: null), InspectionStage.aligning);
    });

    test('enter threshold is 10°', () {
      expect(evaluate(delta: 9.9), InspectionStage.ready);
      expect(evaluate(delta: -10), InspectionStage.ready);
      expect(evaluate(delta: 10.1), InspectionStage.aligning);
    });

    test('ready stage keeps 16° hysteresis', () {
      expect(
        evaluate(current: InspectionStage.ready, delta: 16),
        InspectionStage.ready,
      );
      expect(
        evaluate(current: InspectionStage.ready, delta: 16.1),
        InspectionStage.aligning,
      );
    });
  });

  group('directionQuality', () {
    test('maps state to quality', () {
      expect(
        directionQuality(
          hasTargetAzimuth: false,
          compassReliable: true,
          deltaDeg: 0,
        ),
        DirectionQuality.noTarget,
      );
      expect(
        directionQuality(
          hasTargetAzimuth: true,
          compassReliable: false,
          deltaDeg: 0,
        ),
        DirectionQuality.unavailable,
      );
      expect(
        directionQuality(
          hasTargetAzimuth: true,
          compassReliable: true,
          deltaDeg: 10,
        ),
        DirectionQuality.aligned,
      );
      expect(
        directionQuality(
          hasTargetAzimuth: true,
          compassReliable: true,
          deltaDeg: 30,
        ),
        DirectionQuality.near,
      );
      expect(
        directionQuality(
          hasTargetAzimuth: true,
          compassReliable: true,
          deltaDeg: 30.1,
        ),
        DirectionQuality.far,
      );
    });
  });
}