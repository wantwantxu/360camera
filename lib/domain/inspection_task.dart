import 'inspection_point.dart';

class InspectionTask {
  const InspectionTask({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.points = const [],
    this.isSample = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<InspectionPoint> points;

  /// 示例任务，仅用于演示流程，不代表真实业务数据。
  final bool isSample;

  int get completedCount => points.where((e) => e.completed).length;
  bool get isCompleted => points.isNotEmpty && completedCount == points.length;

  InspectionPoint? pointById(String id) {
    for (final p in points) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 当前点位之后的下一个未完成点位（循环查找）。
  InspectionPoint? nextIncomplete({String? afterPointId}) {
    if (points.isEmpty) return null;
    final start = afterPointId == null
        ? 0
        : (points.indexWhere((e) => e.id == afterPointId) + 1)
            .clamp(0, points.length)
            .toInt();
    for (var i = 0; i < points.length; i++) {
      final point = points[(start + i) % points.length];
      if (!point.completed) return point;
    }
    return null;
  }

  InspectionTask copyWith({
    String? title,
    String? description,
    List<InspectionPoint>? points,
  }) {
    return InspectionTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      points: points ?? this.points,
      isSample: isSample,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'points': points.map((e) => e.toJson()).toList(),
        'isSample': isSample,
      };

  factory InspectionTask.fromJson(Map<String, dynamic> json) => InspectionTask(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未命名任务',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((e) => InspectionPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        isSample: json['isSample'] as bool? ?? false,
      );
}