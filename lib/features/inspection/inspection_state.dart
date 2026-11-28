import '../../core/constants.dart';
import '../../domain/inspection_point.dart';
import '../../domain/inspection_task.dart';

enum InspectionStage {
  /// 未选择点位。
  idle,

  /// 展示点位信息与参考照片。
  briefing,

  /// 前往点位 / 确认拍摄位置。
  positioning,

  /// 调整拍摄方向。
  aligning,

  /// 位置与方向均满足，可开始拍摄。
  ready,

  /// 14 点位全景拍摄中。
  panorama,

  /// 全景已合成，等待确认保存。
  review,

  /// 任务全部点位完成。
  taskComplete,
}

extension InspectionStageX on InspectionStage {
  bool get isGuidance =>
      this == InspectionStage.briefing ||
      this == InspectionStage.positioning ||
      this == InspectionStage.aligning ||
      this == InspectionStage.ready;

  String get label => switch (this) {
        InspectionStage.idle => '待选择点位',
        InspectionStage.briefing => '点位信息',
        InspectionStage.positioning => '前往拍摄位置',
        InspectionStage.aligning => '调整拍摄方向',
        InspectionStage.ready => '可以开始拍摄',
        InspectionStage.panorama => '360° 拍摄中',
        InspectionStage.review => '确认拍摄结果',
        InspectionStage.taskComplete => '任务已完成',
      };
}

enum LocationUiStatus {
  idle,
  noCoordinates,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  locating,
  fixed,
  error,
}

enum ReferenceCompareMode { none, ghost, split }

const _unset = Object();

class InspectionState {
  const InspectionState({
    this.tasks = const [],
    this.activeTaskId,
    this.activePointId,
    this.stage = InspectionStage.idle,
    this.loading = false,
    this.loadError,
    this.gpsStatus = LocationUiStatus.idle,
    this.latitude,
    this.longitude,
    this.gpsAccuracyM,
    this.gpsUpdatedAt,
    this.gpsError,
    this.distanceM,
    this.targetBearingDeg,
    this.arrivalConfirmed = false,
    this.arrivalWasManual = false,
    this.headingDeg,
    this.cameraPitchDeg,
    this.deviceRollDeg,
    this.magneticFieldUt,
    this.compassAvailable = false,
    this.compassInterfered = false,
    this.compassError,
    this.directionDeltaDeg,
    this.manualDirectionConfirmed = false,
    this.pendingWorkId,
    this.referenceMode = ReferenceCompareMode.none,
    this.referenceOpacity = 0.5,
  });

  final List<InspectionTask> tasks;
  final String? activeTaskId;
  final String? activePointId;
  final InspectionStage stage;
  final bool loading;
  final String? loadError;

  final LocationUiStatus gpsStatus;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracyM;
  final DateTime? gpsUpdatedAt;
  final String? gpsError;

  final double? distanceM;
  final double? targetBearingDeg;
  final bool arrivalConfirmed;
  final bool arrivalWasManual;

  final double? headingDeg;
  final double? cameraPitchDeg;
  final double? deviceRollDeg;
  final double? magneticFieldUt;
  final bool compassAvailable;
  final bool compassInterfered;
  final String? compassError;
  final double? directionDeltaDeg;
  final bool manualDirectionConfirmed;

  final String? pendingWorkId;
  final ReferenceCompareMode referenceMode;
  final double referenceOpacity;

  InspectionTask? get activeTask {
    if (activeTaskId == null) return null;
    for (final task in tasks) {
      if (task.id == activeTaskId) return task;
    }
    return null;
  }

  InspectionPoint? get activePoint {
    final task = activeTask;
    final id = activePointId;
    if (task == null || id == null) return null;
    return task.pointById(id);
  }

  int get activePointIndex {
    final task = activeTask;
    final point = activePoint;
    if (task == null || point == null) return -1;
    return task.points.indexWhere((e) => e.id == point.id);
  }

  int get taskCompletedCount => activeTask?.completedCount ?? 0;
  int get taskTotalCount => activeTask?.points.length ?? 0;

  bool get hasActivePoint => activePoint != null;
  bool get activeHasCoordinates => activePoint?.hasCoordinates ?? false;
  bool get activeHasTargetAzimuth => activePoint?.hasTargetAzimuth ?? false;

  bool get gpsFixFresh =>
      gpsUpdatedAt != null &&
      DateTime.now().difference(gpsUpdatedAt!) < const Duration(seconds: 30);

  bool get gpsAccuracyGood =>
      gpsAccuracyM != null && gpsAccuracyM! <= PanoConstants.waypointMaxGpsAccuracyM;

  bool get withinArrivalRange {
    final point = activePoint;
    if (point == null || distanceM == null) return false;
    return distanceM! <= point.arrivalRadiusM && gpsAccuracyGood;
  }

  bool get compassReliable =>
      compassAvailable && !compassInterfered && headingDeg != null;

  bool get referenceVisible => referenceMode != ReferenceCompareMode.none;

  bool get isGuidanceStage => stage.isGuidance;

  bool get canStartCapture => stage == InspectionStage.ready;

  int get completedTotalAcrossTasks =>
      tasks.fold(0, (sum, task) => sum + task.completedCount);

  bool get allTasksCompleted => tasks.isNotEmpty && tasks.every((t) => t.isCompleted);

  InspectionState copyWith({
    List<InspectionTask>? tasks,
    Object? activeTaskId = _unset,
    Object? activePointId = _unset,
    InspectionStage? stage,
    bool? loading,
    Object? loadError = _unset,
    LocationUiStatus? gpsStatus,
    Object? latitude = _unset,
    Object? longitude = _unset,
    Object? gpsAccuracyM = _unset,
    Object? gpsUpdatedAt = _unset,
    Object? gpsError = _unset,
    Object? distanceM = _unset,
    Object? targetBearingDeg = _unset,
    bool? arrivalConfirmed,
    bool? arrivalWasManual,
    Object? headingDeg = _unset,
    Object? cameraPitchDeg = _unset,
    Object? deviceRollDeg = _unset,
    Object? magneticFieldUt = _unset,
    bool? compassAvailable,
    bool? compassInterfered,
    Object? compassError = _unset,
    Object? directionDeltaDeg = _unset,
    bool? manualDirectionConfirmed,
    Object? pendingWorkId = _unset,
    ReferenceCompareMode? referenceMode,
    double? referenceOpacity,
  }) {
    return InspectionState(
      tasks: tasks ?? this.tasks,
      activeTaskId: identical(activeTaskId, _unset)
          ? this.activeTaskId
          : activeTaskId as String?,
      activePointId: identical(activePointId, _unset)
          ? this.activePointId
          : activePointId as String?,
      stage: stage ?? this.stage,
      loading: loading ?? this.loading,
      loadError: identical(loadError, _unset) ? this.loadError : loadError as String?,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _unset) ? this.longitude : longitude as double?,
      gpsAccuracyM:
          identical(gpsAccuracyM, _unset) ? this.gpsAccuracyM : gpsAccuracyM as double?,
      gpsUpdatedAt:
          identical(gpsUpdatedAt, _unset) ? this.gpsUpdatedAt : gpsUpdatedAt as DateTime?,
      gpsError: identical(gpsError, _unset) ? this.gpsError : gpsError as String?,
      distanceM: identical(distanceM, _unset) ? this.distanceM : distanceM as double?,
      targetBearingDeg: identical(targetBearingDeg, _unset)
          ? this.targetBearingDeg
          : targetBearingDeg as double?,
      arrivalConfirmed: arrivalConfirmed ?? this.arrivalConfirmed,
      arrivalWasManual: arrivalWasManual ?? this.arrivalWasManual,
      headingDeg:
          identical(headingDeg, _unset) ? this.headingDeg : headingDeg as double?,
      cameraPitchDeg: identical(cameraPitchDeg, _unset)
          ? this.cameraPitchDeg
          : cameraPitchDeg as double?,
      deviceRollDeg: identical(deviceRollDeg, _unset)
          ? this.deviceRollDeg
          : deviceRollDeg as double?,
      magneticFieldUt: identical(magneticFieldUt, _unset)
          ? this.magneticFieldUt
          : magneticFieldUt as double?,
      compassAvailable: compassAvailable ?? this.compassAvailable,
      compassInterfered: compassInterfered ?? this.compassInterfered,
      compassError:
          identical(compassError, _unset) ? this.compassError : compassError as String?,
      directionDeltaDeg: identical(directionDeltaDeg, _unset)
          ? this.directionDeltaDeg
          : directionDeltaDeg as double?,
      manualDirectionConfirmed:
          manualDirectionConfirmed ?? this.manualDirectionConfirmed,
      pendingWorkId:
          identical(pendingWorkId, _unset) ? this.pendingWorkId : pendingWorkId as String?,
      referenceMode: referenceMode ?? this.referenceMode,
      referenceOpacity: referenceOpacity ?? this.referenceOpacity,
    );
  }
}