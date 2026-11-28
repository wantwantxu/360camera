import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/domain/capture_matrix.dart';
import 'package:pano_360_pro/domain/capture_point.dart';
import 'package:pano_360_pro/domain/vr_space.dart';

VrPoint _point(
  String id, {
  double heading = 0,
  double mapX = 0,
  double mapY = 0,
  List<SpaceLabel> labels = const [],
}) {
  return VrPoint(
    id: id,
    name: '点位 $id',
    imagePath: '/tmp/$id.png',
    thumbPath: '/tmp/$id-thumb.png',
    width: 4000,
    height: 2000,
    headingDeg: heading,
    mapX: mapX,
    mapY: mapY,
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    labels: labels,
  );
}

void main() {
  group('createVr24Points', () {
    test('has 8 frames per ring with the requested pitches', () {
      final pts = createVr24Points();
      expect(pts, hasLength(24));
      expect(pts.where((e) => e.ring == CaptureRing.mid), hasLength(8));
      expect(pts.where((e) => e.ring == CaptureRing.upper), hasLength(8));
      expect(pts.where((e) => e.ring == CaptureRing.lower), hasLength(8));
      expect(
        pts.where((e) => e.ring == CaptureRing.mid).map((e) => e.pitch),
        everyElement(0),
      );
      expect(
        pts.where((e) => e.ring == CaptureRing.upper).map((e) => e.pitch),
        everyElement(50),
      );
      expect(
        pts.where((e) => e.ring == CaptureRing.lower).map((e) => e.pitch),
        everyElement(-50),
      );
    });

    test('lower ring is staggered by 22.5°', () {
      final pts = createVr24Points();
      final uppers = pts.where((e) => e.ring == CaptureRing.upper).toList();
      final lowers = pts.where((e) => e.ring == CaptureRing.lower).toList();
      for (var i = 0; i < 8; i++) {
        expect(lowers[i].yaw, closeTo((uppers[i].yaw + 22.5) % 360, 1e-9));
      }
    });

    test('yaw offset rotates all rings and wraps', () {
      final pts = createVr24Points(yawOffsetDeg: 350);
      final mids = pts.where((e) => e.ring == CaptureRing.mid).toList();
      expect(mids.first.yaw, closeTo(350, 1e-9));
      expect(mids[1].yaw, closeTo(35, 1e-9));
      final lowers = pts.where((e) => e.ring == CaptureRing.lower).toList();
      expect(lowers.first.yaw, closeTo(12.5, 1e-9));
      expect(
        pts.map((e) => e.yaw).every((yaw) => yaw >= 0 && yaw < 360),
        isTrue,
      );
      expect(pts.map((e) => e.id).toSet(), hasLength(24));
    });
  });

  group('VrSpace persistence', () {
    test('JSON round-trip keeps heading, labels, and cover', () {
      final space = VrSpace(
        id: 's1',
        name: '客厅',
        category: SpaceCategory.residence,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 2),
        coverPointId: 'p2',
        points: [
          _point('p1', heading: 12.5, labels: const [
            SpaceLabel(id: 'l1', text: '沙发', yawDeg: 30, pitchDeg: -5),
          ]),
          _point('p2', heading: 200, mapX: 2.6, mapY: 1.5),
        ],
      );

      final restored = VrSpace.fromJson(space.toJson());

      expect(restored.id, 's1');
      expect(restored.category, SpaceCategory.residence);
      expect(restored.coverPointId, 'p2');
      expect(restored.labelCount, 1);
      expect(restored.points[0].headingDeg, 12.5);
      expect(restored.points[0].labels.single.text, '沙发');
      expect(restored.points[0].labels.single.yawDeg, 30);
      expect(restored.points[1].mapX, 2.6);
      expect(restored.points[1].createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('missing heading stays unknown after reload', () {
      final space = VrSpace(
        id: 's2',
        name: '导入',
        category: SpaceCategory.other,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        points: [
          VrPoint(
            id: 'p1',
            name: '导入图',
            imagePath: '/tmp/a.png',
            thumbPath: '/tmp/a-thumb.png',
            width: 4096,
            height: 2048,
            mapX: 0,
            mapY: 0,
            createdAt: DateTime.utc(2026, 1, 1),
            source: 'import',
          ),
        ],
      );

      final restored = VrSpace.fromJson(space.toJson());
      expect(restored.points.single.orientationKnown, isFalse);
      expect(restored.points.single.source, 'import');
      expect(restored.coverPoint?.id, 'p1');
    });

    test('cover falls back to the first point', () {
      final empty = VrSpace(
        id: 's3',
        name: '空',
        category: SpaceCategory.office,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(empty.coverPoint, isNull);
      expect(empty.pointById('missing'), isNull);

      final space = empty.copyWith(points: [_point('p1'), _point('p2')]);
      expect(space.coverPoint?.id, 'p1');
      expect(space.indexOfPoint('p2'), 1);
    });
  });

  group('schematic layout', () {
    test('first point sits at the origin; later points follow heading', () {
      final space = VrSpace(
        id: 's',
        name: 's',
        category: SpaceCategory.other,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(nextVrPointPosition(space), (x: 0.0, y: 0.0));

      final north = space.copyWith(points: [_point('p1', heading: 0)]);
      final p2 = nextVrPointPosition(north);
      expect(p2.x, closeTo(0, 1e-9));
      expect(p2.y, closeTo(vrPointSpacingM, 1e-9));

      final east = space.copyWith(points: [_point('p1', heading: 90)]);
      final p3 = nextVrPointPosition(east, spacingM: 3);
      expect(p3.x, closeTo(3, 1e-9));
      expect(p3.y, closeTo(0, 1e-9));
    });

    test('world bearing and local yaw toward neighbours', () {
      final a = _point('a', heading: 0);
      final b = _point('b', heading: 0, mapY: 2.6);
      final c = _point('c', heading: 90, mapX: 2.6, mapY: 2.6);

      expect(worldBearingDeg(a, b), closeTo(0, 1e-9));
      expect(worldBearingDeg(b, c), closeTo(90, 1e-9));
      expect(worldBearingDeg(a, a), isNull);

      expect(localYawToward(a, b), closeTo(0, 1e-9));
      expect(localYawToward(b, a), closeTo(180, 1e-9));
      expect(localYawToward(b, c), closeTo(90, 1e-9));

      final unknown = VrPoint(
        id: 'u',
        name: '未知方位',
        imagePath: '/tmp/u.png',
        thumbPath: '/tmp/u-thumb.png',
        width: 1,
        height: 1,
        mapX: 3,
        mapY: 3,
        createdAt: DateTime.utc(2026),
      );
      expect(localYawToward(unknown, a), isNull);
      expect(unknown.copyWith(name: '改名').headingDeg, isNull);
    });

    test('sequential hotspots link previous and next only', () {
      final space = VrSpace(
        id: 'tour',
        name: 'tour',
        category: SpaceCategory.residence,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        points: [
          _point('a', heading: 0),
          _point('b', heading: 0, mapY: 2.6),
          _point('c', heading: 90, mapX: 2.6, mapY: 2.6),
        ],
      );

      expect(buildSequentialHotspots(space, space.points[0]), hasLength(1));
      final first = buildSequentialHotspots(space, space.points[0]).single;
      expect(first.targetPointId, 'b');
      expect(first.isNext, isTrue);
      expect(first.yawDeg, closeTo(0, 1e-9));

      final middle = buildSequentialHotspots(space, space.points[1]);
      expect(middle, hasLength(2));
      final back = middle.firstWhere((e) => !e.isNext);
      final next = middle.firstWhere((e) => e.isNext);
      expect(back.targetPointId, 'a');
      expect(back.yawDeg, closeTo(180, 1e-9));
      expect(next.targetPointId, 'c');
      expect(next.yawDeg, closeTo(90, 1e-9));

      final last = buildSequentialHotspots(space, space.points[2]).single;
      expect(last.targetPointId, 'b');
      expect(last.isNext, isFalse);
      expect(last.yawDeg, closeTo(180, 1e-9));

      final outside = VrPoint(
        id: 'x',
        name: 'x',
        imagePath: '/tmp/x.png',
        thumbPath: '/tmp/x-thumb.png',
        width: 1,
        height: 1,
        mapX: 0,
        mapY: 0,
        createdAt: DateTime.utc(2026),
      );
      expect(buildSequentialHotspots(space, outside), isEmpty);
    });

    test('unknown orientation yields no directional hotspots', () {
      final unknown = VrPoint(
        id: 'u',
        name: 'u',
        imagePath: '/tmp/u.png',
        thumbPath: '/tmp/u-thumb.png',
        width: 1,
        height: 1,
        mapX: 0,
        mapY: 0,
        createdAt: DateTime.utc(2026),
      );
      final space = VrSpace(
        id: 's',
        name: 's',
        category: SpaceCategory.other,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        points: [unknown, _point('b', mapY: 2.6)],
      );
      expect(buildSequentialHotspots(space, space.points[0]), isEmpty);
    });
  });
}