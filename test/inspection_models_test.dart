import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/domain/inspection_point.dart';
import 'package:pano_360_pro/domain/inspection_task.dart';

InspectionPoint _point({
  required String id,
  String code = 'P-01',
  List<InspectionRecord> records = const [],
}) {
  return InspectionPoint(
    id: id,
    code: code,
    name: '点位 $id',
    description: '现场说明',
    instructions: '拍摄说明',
    directionName: '朝向下游',
    latitude: 31.230416,
    longitude: 121.473701,
    targetAzimuthDeg: 90,
    targetPitchDeg: 5,
    arrivalRadiusM: 20,
    referenceImagePath: '/tmp/ref.jpg',
    records: records,
  );
}

void main() {
  group('InspectionPoint JSON', () {
    test('round-trips every field', () {
      final capturedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final point = _point(
        id: 'p1',
        records: [
          InspectionRecord(workId: 'w1', capturedAt: capturedAt),
        ],
      );
      final decoded = InspectionPoint.fromJson(point.toJson());

      expect(decoded.id, 'p1');
      expect(decoded.code, 'P-01');
      expect(decoded.name, '点位 p1');
      expect(decoded.description, '现场说明');
      expect(decoded.instructions, '拍摄说明');
      expect(decoded.directionName, '朝向下游');
      expect(decoded.latitude, 31.230416);
      expect(decoded.longitude, 121.473701);
      expect(decoded.targetAzimuthDeg, 90);
      expect(decoded.targetPitchDeg, 5);
      expect(decoded.arrivalRadiusM, 20);
      expect(decoded.referenceImagePath, '/tmp/ref.jpg');
      expect(decoded.records, hasLength(1));
      expect(decoded.records.single.workId, 'w1');
      expect(decoded.records.single.capturedAt, capturedAt);
      expect(decoded.completed, isTrue);
    });

    test('handles missing optional fields', () {
      final point = InspectionPoint.fromJson({'id': 'x'});
      expect(point.code, '');
      expect(point.name, '未命名点位');
      expect(point.latitude, isNull);
      expect(point.hasCoordinates, isFalse);
      expect(point.targetPitchDeg, 0);
      expect(point.arrivalRadiusM, 15);
      expect(point.completed, isFalse);
    });

    test('copyWith can clear nullable fields', () {
      final point = _point(id: 'p2');
      final cleared = point.copyWith(
        latitude: null,
        longitude: null,
        targetAzimuthDeg: null,
        referenceImagePath: null,
      );
      expect(cleared.hasCoordinates, isFalse);
      expect(cleared.hasTargetAzimuth, isFalse);
      expect(cleared.referenceImagePath, isNull);
      expect(cleared.code, point.code);
    });
  });

  group('InspectionTask', () {
    test('counts completion and exposes latest record', () {
      final record = InspectionRecord(
        workId: 'w9',
        capturedAt: DateTime.utc(2026, 2, 3),
      );
      final task = InspectionTask(
        id: 't1',
        title: '任务',
        createdAt: DateTime.utc(2026, 1, 1),
        points: [
          _point(id: 'a'),
          _point(id: 'b', records: [record]),
        ],
      );
      expect(task.completedCount, 1);
      expect(task.isCompleted, isFalse);
      expect(task.points[1].lastWorkId, 'w9');
      expect(task.points[1].lastCompletedAt, DateTime.utc(2026, 2, 3));
    });

    test('nextIncomplete cycles to the next unfinished point', () {
      final task = InspectionTask(
        id: 't2',
        title: '任务',
        createdAt: DateTime.utc(2026, 1, 1),
        points: [
          _point(
            id: 'a',
            records: [
              InspectionRecord(
                workId: 'w',
                capturedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
          _point(id: 'b'),
          _point(id: 'c'),
        ],
      );
      expect(task.nextIncomplete(afterPointId: 'a')?.id, 'b');
      expect(task.nextIncomplete(afterPointId: 'b')?.id, 'c');
      expect(task.nextIncomplete(afterPointId: 'c')?.id, 'b');
      expect(task.nextIncomplete()?.id, 'b');
    });

    test('nextIncomplete returns null when all complete or empty', () {
      final empty = InspectionTask(
        id: 't3',
        title: '空',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(empty.nextIncomplete(), isNull);
      expect(empty.isCompleted, isFalse);

      final record = InspectionRecord(
        workId: 'w',
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final done = empty.copyWith(
        points: [_point(id: 'a', records: [record])],
      );
      expect(done.nextIncomplete(), isNull);
      expect(done.isCompleted, isTrue);
    });

    test('JSON round-trip preserves sample flag and points', () {
      final task = InspectionTask(
        id: 'sample',
        title: '示例',
        description: '说明',
        createdAt: DateTime.utc(2026, 5, 6),
        points: [_point(id: 'p')],
        isSample: true,
      );
      final decoded = InspectionTask.fromJson(task.toJson());
      expect(decoded.id, 'sample');
      expect(decoded.title, '示例');
      expect(decoded.description, '说明');
      expect(decoded.createdAt, task.createdAt);
      expect(decoded.isSample, isTrue);
      expect(decoded.points.single.id, 'p');
    });
  });
}