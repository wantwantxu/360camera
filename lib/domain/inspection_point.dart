class InspectionRecord {
  const InspectionRecord({required this.workId, required this.capturedAt});

  final String workId;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'workId': workId,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory InspectionRecord.fromJson(Map<String, dynamic> json) => InspectionRecord(
        workId: json['workId'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}

const _unset = Object();

class InspectionPoint {
  const InspectionPoint({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.instructions = '',
    this.directionName = '',
    this.latitude,
    this.longitude,
    this.targetAzimuthDeg,
    this.targetPitchDeg = 0,
    this.arrivalRadiusM = 15,
    this.referenceImagePath,
    this.records = const [],
  });

  final String id;
  final String code;
  final String name;

  /// 点位描述（现场位置说明）。
  final String description;

  /// 拍摄说明（如何取景、注意事项）。
  final String instructions;

  /// 方向说明，例如「朝向下游」。
  final String directionName;

  final double? latitude;
  final double? longitude;
  final double? targetAzimuthDeg;
  final double targetPitchDeg;
  final double arrivalRadiusM;
  final String? referenceImagePath;
  final List<InspectionRecord> records;

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasTargetAzimuth => targetAzimuthDeg != null;
  bool get completed => records.isNotEmpty;
  int get captureCount => records.length;

  DateTime? get lastCompletedAt => records.isEmpty ? null : records.last.capturedAt;
  String? get lastWorkId => records.isEmpty ? null : records.last.workId;

  InspectionPoint copyWith({
    String? code,
    String? name,
    String? description,
    String? instructions,
    String? directionName,
    Object? latitude = _unset,
    Object? longitude = _unset,
    Object? targetAzimuthDeg = _unset,
    double? targetPitchDeg,
    double? arrivalRadiusM,
    Object? referenceImagePath = _unset,
    List<InspectionRecord>? records,
  }) {
    return InspectionPoint(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      instructions: instructions ?? this.instructions,
      directionName: directionName ?? this.directionName,
      latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _unset) ? this.longitude : longitude as double?,
      targetAzimuthDeg: identical(targetAzimuthDeg, _unset)
          ? this.targetAzimuthDeg
          : targetAzimuthDeg as double?,
      targetPitchDeg: targetPitchDeg ?? this.targetPitchDeg,
      arrivalRadiusM: arrivalRadiusM ?? this.arrivalRadiusM,
      referenceImagePath: identical(referenceImagePath, _unset)
          ? this.referenceImagePath
          : referenceImagePath as String?,
      records: records ?? this.records,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'instructions': instructions,
        'directionName': directionName,
        'latitude': latitude,
        'longitude': longitude,
        'targetAzimuthDeg': targetAzimuthDeg,
        'targetPitchDeg': targetPitchDeg,
        'arrivalRadiusM': arrivalRadiusM,
        'referenceImagePath': referenceImagePath,
        'records': records.map((e) => e.toJson()).toList(),
      };

  factory InspectionPoint.fromJson(Map<String, dynamic> json) => InspectionPoint(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '未命名点位',
        description: json['description'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        directionName: json['directionName'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        targetAzimuthDeg: (json['targetAzimuthDeg'] as num?)?.toDouble(),
        targetPitchDeg: (json['targetPitchDeg'] as num?)?.toDouble() ?? 0,
        arrivalRadiusM: (json['arrivalRadiusM'] as num?)?.toDouble() ?? 15,
        referenceImagePath: json['referenceImagePath'] as String?,
        records: (json['records'] as List<dynamic>? ?? const [])
            .map((e) => InspectionRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}