import 'dart:math' as math;

import '../core/utils/angle_utils.dart';

enum SpaceCategory { residence, apartment, shop, office, exhibition, other }

extension SpaceCategoryX on SpaceCategory {
  String get label => switch (this) {
        SpaceCategory.residence => '住宅',
        SpaceCategory.apartment => '公寓',
        SpaceCategory.shop => '商铺',
        SpaceCategory.office => '办公',
        SpaceCategory.exhibition => '展馆',
        SpaceCategory.other => '其他',
      };

  String get hint => switch (this) {
        SpaceCategory.residence => '住宅 / 别墅 / 样板间',
        SpaceCategory.apartment => '公寓 / 租赁房源',
        SpaceCategory.shop => '门店 / 餐饮 / 展厅',
        SpaceCategory.office => '办公室 / 会议室',
        SpaceCategory.exhibition => '展馆 / 文旅空间',
        SpaceCategory.other => '其他需要记录的空间',
      };

  static SpaceCategory parse(String? raw) {
    return SpaceCategory.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => SpaceCategory.residence,
    );
  }
}

class SpaceLabel {
  const SpaceLabel({
    required this.id,
    required this.text,
    required this.yawDeg,
    required this.pitchDeg,
  });

  final String id;
  final String text;

  /// Local equirectangular longitude. 0° is the panorama's starting heading.
  final double yawDeg;
  final double pitchDeg;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'yawDeg': yawDeg,
        'pitchDeg': pitchDeg,
      };

  factory SpaceLabel.fromJson(Map<String, dynamic> json) => SpaceLabel(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        yawDeg: (json['yawDeg'] as num?)?.toDouble() ?? 0,
        pitchDeg: (json['pitchDeg'] as num?)?.toDouble() ?? 0,
      );
}

class VrPoint {
  const VrPoint({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.thumbPath,
    required this.width,
    required this.height,
    required this.mapX,
    required this.mapY,
    required this.createdAt,
    this.headingDeg,
    this.source = 'capture',
    this.workId,
    this.labels = const [],
  });

  final String id;
  final String name;
  final String imagePath;
  final String thumbPath;
  final int width;
  final int height;

  /// World heading (magnetic north) of equirectangular longitude 0°.
  /// Null when the orientation could not be measured (e.g. imported image).
  final double? headingDeg;
  bool get orientationKnown => headingDeg != null;

  /// Schematic east/north coordinates in metres, not a surveyed floor plan.
  final double mapX;
  final double mapY;

  final DateTime createdAt;
  final String source;
  final String? workId;
  final List<SpaceLabel> labels;

  VrPoint copyWith({
    String? name,
    Object? headingDeg = _sentinel,
    List<SpaceLabel>? labels,
  }) {
    return VrPoint(
      id: id,
      name: name ?? this.name,
      imagePath: imagePath,
      thumbPath: thumbPath,
      width: width,
      height: height,
      mapX: mapX,
      mapY: mapY,
      createdAt: createdAt,
      headingDeg: identical(headingDeg, _sentinel)
          ? this.headingDeg
          : headingDeg as double?,
      source: source,
      workId: workId,
      labels: labels ?? this.labels,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'thumbPath': thumbPath,
        'width': width,
        'height': height,
        'headingDeg': headingDeg,
        'mapX': mapX,
        'mapY': mapY,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
        'workId': workId,
        'labels': labels.map((e) => e.toJson()).toList(),
      };

  factory VrPoint.fromJson(Map<String, dynamic> json) => VrPoint(
        id: json['id'] as String,
        name: json['name'] as String? ?? '空间点位',
        imagePath: json['imagePath'] as String,
        thumbPath: json['thumbPath'] as String,
        width: (json['width'] as num?)?.toInt() ?? 2048,
        height: (json['height'] as num?)?.toInt() ?? 1024,
        headingDeg: (json['headingDeg'] as num?)?.toDouble(),
        mapX: (json['mapX'] as num?)?.toDouble() ?? 0,
        mapY: (json['mapY'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        source: json['source'] as String? ?? 'capture',
        workId: json['workId'] as String?,
        labels: (json['labels'] as List<dynamic>? ?? const [])
            .map((e) => SpaceLabel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VrSpace {
  const VrSpace({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.points = const [],
    this.coverPointId,
  });

  final String id;
  final String name;
  final SpaceCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<VrPoint> points;
  final String? coverPointId;

  VrPoint? get coverPoint {
    if (points.isEmpty) return null;
    if (coverPointId != null) {
      for (final point in points) {
        if (point.id == coverPointId) return point;
      }
    }
    return points.first;
  }

  int get labelCount => points.fold(0, (sum, e) => sum + e.labels.length);

  VrPoint? pointById(String? id) {
    if (id == null) return null;
    for (final point in points) {
      if (point.id == id) return point;
    }
    return null;
  }

  int indexOfPoint(String id) => points.indexWhere((e) => e.id == id);

  VrSpace copyWith({
    String? name,
    SpaceCategory? category,
    DateTime? updatedAt,
    List<VrPoint>? points,
    Object? coverPointId = _sentinel,
  }) {
    return VrSpace(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      points: points ?? this.points,
      coverPointId: identical(coverPointId, _sentinel)
          ? this.coverPointId
          : coverPointId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'coverPointId': coverPointId,
        'points': points.map((e) => e.toJson()).toList(),
      };

  factory VrSpace.fromJson(Map<String, dynamic> json) => VrSpace(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名空间',
        category: SpaceCategoryX.parse(json['category'] as String?),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        coverPointId: json['coverPointId'] as String?,
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((e) => VrPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

const _sentinel = Object();

/// Realsee-style 2–3 m capture spacing; used only for the schematic map.
const double vrPointSpacingM = 2.6;

/// Appends the next point along [headingDeg] so the minimap stays coherent.
({double x, double y}) nextVrPointPosition(
  VrSpace space, {
  double? headingDeg,
  double spacingM = vrPointSpacingM,
}) {
  if (space.points.isEmpty) return (x: 0, y: 0);
  final last = space.points.last;
  final direction = headingDeg ?? last.headingDeg ?? 0;
  final rad = degToRad(direction);
  return (
    x: last.mapX + math.sin(rad) * spacingM,
    y: last.mapY + math.cos(rad) * spacingM,
  );
}

double? worldBearingDeg(VrPoint from, VrPoint to) {
  final dx = to.mapX - from.mapX;
  final dy = to.mapY - from.mapY;
  if (dx.abs() < 1e-6 && dy.abs() < 1e-6) return null;
  return normalizeDeg360(math.atan2(dx, dy) * 180 / math.pi);
}

/// Local panorama yaw that points toward [to], when the capture heading is known.
double? localYawToward(VrPoint from, VrPoint to) {
  final heading = from.headingDeg;
  if (heading == null) return null;
  final bearing = worldBearingDeg(from, to);
  if (bearing == null) return null;
  return normalizeDeg360(bearing - heading);
}

class VrHotspot {
  const VrHotspot({
    required this.targetPointId,
    required this.label,
    required this.yawDeg,
    required this.pitchDeg,
    required this.isNext,
  });

  final String targetPointId;
  final String label;
  final double yawDeg;
  final double pitchDeg;
  final bool isNext;
}

/// Sequential door-like hotspots between the previous/next capture point.
List<VrHotspot> buildSequentialHotspots(VrSpace space, VrPoint point) {
  final index = space.indexOfPoint(point.id);
  if (index < 0) return const [];
  final hotspots = <VrHotspot>[];

  if (index > 0) {
    final target = space.points[index - 1];
    final yaw = localYawToward(point, target);
    if (yaw != null) {
      hotspots.add(
        VrHotspot(
          targetPointId: target.id,
          label: '返回 ${target.name}',
          yawDeg: yaw,
          pitchDeg: 0,
          isNext: false,
        ),
      );
    }
  }

  if (index < space.points.length - 1) {
    final target = space.points[index + 1];
    final yaw = localYawToward(point, target);
    if (yaw != null) {
      hotspots.add(
        VrHotspot(
          targetPointId: target.id,
          label: '前往 ${target.name}',
          yawDeg: yaw,
          pitchDeg: 0,
          isNext: true,
        ),
      );
    }
  }

  return hotspots;
}