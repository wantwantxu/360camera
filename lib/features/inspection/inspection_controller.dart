import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/utils/angle_utils.dart';
import '../../core/utils/compass_utils.dart';
import '../../core/utils/geo_utils.dart';
import '../../data/inspection_repository.dart';
import '../../data/inspection_seed.dart';
import '../../domain/app_enums.dart';
import '../../domain/inspection_point.dart';
import '../../domain/inspection_task.dart';
import '../session/pano_session.dart';
import 'guidance_logic.dart';
import 'inspection_state.dart';

final inspectionProvider =
    StateNotifierProvider<InspectionController, InspectionState>((ref) {
  return InspectionController(ref.watch(inspectionRepositoryProvider), ref);
});

class InspectionController extends StateNotifier<InspectionState> {
  InspectionController(this._repo, this._ref) : super(const InspectionState(loading: true)) {
    unawaited(_init());
  }

  final InspectionRepository _repo;
  final Ref _ref;
  final _uuid = const Uuid();

  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<Position>? _posSub;
  Timer? _compassStartupTimer;

  MagnetometerEvent? _lastMag;
  AccelerometerEvent? _lastAcc;
  DateTime? _lastCompassPublish;
  double? _smoothedSin;
  double? _smoothedCos;

  bool _sawMag = false;
  bool _sawAcc = false;
  bool _sensorErrorReported = false;
  bool _interferenceWarned = false;
  bool _disposed = false;
  bool _locationBusy = false;
  bool _arrivalHintShown = false;

  PanoSessionNotifier get _pano => _ref.read(panoSessionProvider.notifier);

  Future<void> _init() async {
    try {
      var tasks = await _repo.loadTasks();
      if (tasks == null) {
        tasks = [buildSampleInspectionTask()];
        await _repo.saveTasks(tasks);
      }
      if (_disposed || !mounted) return;
      state = state.copyWith(
        tasks: tasks,
        loading: false,
        activeTaskId: state.activeTaskId ??
            (tasks.isNotEmpty ? tasks.first.id : null),
      );
    } catch (e) {
      if (_disposed || !mounted) return;
      state = state.copyWith(loading: false, loadError: '巡检任务读取失败：$e');
      _toast('巡检任务读取失败，请检查应用存储权限');
    }
  }

  // ---------------------------------------------------------------------------
  // 任务 / 点位选择
  // ---------------------------------------------------------------------------

  void selectTask(String taskId) {
    if (state.stage == InspectionStage.panorama ||
        state.stage == InspectionStage.review) {
      _toast('请先完成或退出当前点位拍摄与结果确认');
      return;
    }
    final exists = state.tasks.any((t) => t.id == taskId);
    if (!exists) return;
    _endGuidanceStreams();
    state = state.copyWith(
      activeTaskId: taskId,
      activePointId: null,
      stage: InspectionStage.idle,
      pendingWorkId: null,
      referenceMode: ReferenceCompareMode.none,
      arrivalConfirmed: false,
      arrivalWasManual: false,
      manualDirectionConfirmed: false,
      gpsStatus: LocationUiStatus.idle,
      gpsError: null,
      latitude: null,
      longitude: null,
      gpsAccuracyM: null,
      gpsUpdatedAt: null,
      distanceM: null,
      targetBearingDeg: null,
      headingDeg: null,
      cameraPitchDeg: null,
      deviceRollDeg: null,
      magneticFieldUt: null,
      compassAvailable: false,
      compassInterfered: false,
      compassError: null,
      directionDeltaDeg: null,
    );
  }

  void selectPoint(String taskId, String pointId) {
    if (state.stage == InspectionStage.panorama ||
        state.stage == InspectionStage.review) {
      _toast('请先完成或退出当前点位拍摄与结果确认');
      return;
    }
    final task = _findTask(taskId);
    final point = task?.pointById(pointId);
    if (task == null || point == null) return;

    _endGuidanceStreams();
    _arrivalHintShown = false;

    state = _pointEntryState(state, task: task, point: point, stage: InspectionStage.briefing);
    _startCompass();
    if (point.hasCoordinates) {
      unawaited(refreshLocation(startStream: true));
    }
  }

  InspectionState _pointEntryState(
    InspectionState base, {
    required InspectionTask task,
    required InspectionPoint point,
    required InspectionStage stage,
    List<InspectionTask>? tasks,
  }) {
    return base.copyWith(
      tasks: tasks ?? base.tasks,
      activeTaskId: task.id,
      activePointId: point.id,
      stage: stage,
      pendingWorkId: null,
      referenceMode: ReferenceCompareMode.none,
      referenceOpacity: 0.5,
      arrivalConfirmed: false,
      arrivalWasManual: false,
      manualDirectionConfirmed: false,
      gpsStatus: point.hasCoordinates ? LocationUiStatus.idle : LocationUiStatus.noCoordinates,
      gpsError: null,
      latitude: null,
      longitude: null,
      gpsAccuracyM: null,
      gpsUpdatedAt: null,
      distanceM: null,
      targetBearingDeg: null,
      headingDeg: null,
      cameraPitchDeg: null,
      deviceRollDeg: null,
      magneticFieldUt: null,
      compassAvailable: false,
      compassInterfered: false,
      compassError: null,
      directionDeltaDeg: null,
    );
  }

  void beginNavigation() {
    final point = state.activePoint;
    if (point == null) return;
    if (state.stage == InspectionStage.panorama || state.stage == InspectionStage.review) {
      return;
    }
    if (!point.hasCoordinates) {
      state = state.copyWith(stage: InspectionStage.positioning, gpsStatus: LocationUiStatus.noCoordinates);
      return;
    }
    state = state.copyWith(stage: InspectionStage.positioning);
    if (state.gpsStatus == LocationUiStatus.fixed && state.gpsFixFresh) {
      _maybeAnnounceArrival();
    } else {
      unawaited(refreshLocation(startStream: true));
    }
  }

  // ---------------------------------------------------------------------------
  // 位置确认
  // ---------------------------------------------------------------------------

  Future<void> refreshLocation({bool startStream = true}) async {
    if (_disposed || _locationBusy) return;
    final point = state.activePoint;
    if (point == null) return;
    if (!point.hasCoordinates) {
      state = state.copyWith(
        gpsStatus: LocationUiStatus.noCoordinates,
        distanceM: null,
        targetBearingDeg: null,
      );
      return;
    }
    _locationBusy = true;
    state = state.copyWith(gpsStatus: LocationUiStatus.locating, gpsError: null);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateLocationFailure(LocationUiStatus.serviceDisabled, '系统定位服务未开启，请打开 GPS 后重试');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _updateLocationFailure(
          LocationUiStatus.permissionDeniedForever,
          '定位权限已被永久拒绝，请在系统设置中开启定位权限',
        );
        return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _updateLocationFailure(LocationUiStatus.permissionDenied, '定位权限未授予，将无法计算距离');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (_disposed || !mounted) return;
      _applyPosition(pos);
      if (startStream) _startLocationStream();
    } on TimeoutException {
      _updateLocationFailure(LocationUiStatus.error, '定位超时，请到开阔处后点击重新定位');
    } on LocationServiceDisabledException {
      _updateLocationFailure(LocationUiStatus.serviceDisabled, '系统定位服务未开启，请打开 GPS 后重试');
    } on PermissionDeniedException {
      _updateLocationFailure(LocationUiStatus.permissionDenied, '定位权限未授予，将无法计算距离');
    } catch (e) {
      _updateLocationFailure(LocationUiStatus.error, '定位失败：$e');
    } finally {
      _locationBusy = false;
    }
  }

  void _updateLocationFailure(LocationUiStatus status, String message) {
    if (_disposed || !mounted) return;
    state = state.copyWith(gpsStatus: status, gpsError: message);
    _toast(message);
  }

  void _startLocationStream() {
    if (_posSub != null || _disposed) return;
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen(
        (pos) {
          if (_disposed) return;
          _applyPosition(pos);
        },
        onError: (Object error) {
          if (_disposed) return;
          if (state.gpsStatus == LocationUiStatus.fixed) {
            state = state.copyWith(gpsError: '定位更新中断：$error');
          } else {
            state = state.copyWith(
              gpsStatus: LocationUiStatus.error,
              gpsError: '定位更新失败：$error',
            );
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      state = state.copyWith(gpsStatus: LocationUiStatus.error, gpsError: '定位失败：$e');
    }
  }

  void _stopLocationStream() {
    _posSub?.cancel();
    _posSub = null;
  }

  void _applyPosition(Position pos) {
    final point = state.activePoint;
    if (point == null || _disposed) return;

    double? distance;
    double? bearing;
    if (point.hasCoordinates) {
      distance = distanceMeters(
        lat1: pos.latitude,
        lon1: pos.longitude,
        lat2: point.latitude!,
        lon2: point.longitude!,
      );
      bearing = initialBearingDeg(
        lat1: pos.latitude,
        lon1: pos.longitude,
        lat2: point.latitude!,
        lon2: point.longitude!,
      );
    }

    state = state.copyWith(
      gpsStatus: LocationUiStatus.fixed,
      latitude: pos.latitude,
      longitude: pos.longitude,
      gpsAccuracyM: pos.accuracy,
      gpsUpdatedAt: DateTime.now(),
      gpsError: null,
      distanceM: distance,
      targetBearingDeg: bearing,
    );

    if (state.arrivalConfirmed &&
        !state.arrivalWasManual &&
        distance != null &&
        distance > point.arrivalRadiusM * 2) {
      state = state.copyWith(
        arrivalConfirmed: false,
        arrivalWasManual: false,
        manualDirectionConfirmed: false,
        stage: InspectionStage.positioning,
      );
      _toast('已离开拍摄点范围，请重新确认拍摄位置');
      return;
    }

    _maybeAnnounceArrival();
    _evaluateGuidance();
  }

  void _maybeAnnounceArrival() {
    final point = state.activePoint;
    if (point == null || _arrivalHintShown) return;
    if (state.stage != InspectionStage.positioning || state.arrivalConfirmed) return;
    if (!isWithinArrivalRange(
      distanceM: state.distanceM,
      accuracyM: state.gpsAccuracyM,
      radiusM: point.arrivalRadiusM,
    )) {
      return;
    }
    _arrivalHintShown = true;
    _toast('已进入目标点位范围（${formatDistance(state.distanceM)}），请确认拍摄位置');
  }

  void confirmArrival() {
    final point = state.activePoint;
    if (point == null || state.stage != InspectionStage.positioning) return;

    final manual = !point.hasCoordinates ||
        state.latitude == null ||
        state.longitude == null ||
        !state.gpsFixFresh ||
        !state.gpsAccuracyGood ||
        state.distanceM == null ||
        state.distanceM! > point.arrivalRadiusM;

    state = state.copyWith(
      arrivalConfirmed: true,
      arrivalWasManual: manual,
      stage: InspectionStage.aligning,
    );
    _evaluateGuidance();
    _toast(manual ? '已手动确认拍摄位置' : '拍摄位置已确认');
  }

  // ---------------------------------------------------------------------------
  // 方向引导
  // ---------------------------------------------------------------------------

  void _startCompass() {
    if (_disposed || _magSub != null || _accSub != null) return;
    _compassStartupTimer?.cancel();
    _sawMag = false;
    _sawAcc = false;
    _sensorErrorReported = false;
    _smoothedSin = null;
    _smoothedCos = null;
    _lastMag = null;
    _lastAcc = null;
    _lastCompassPublish = null;
    state = state.copyWith(
      compassAvailable: false,
      compassInterfered: false,
      compassError: null,
      headingDeg: null,
      cameraPitchDeg: null,
      deviceRollDeg: null,
      magneticFieldUt: null,
      directionDeltaDeg: null,
    );
    _compassStartupTimer = Timer(PanoConstants.compassStartupTimeout, () {
      if (_disposed || !mounted) return;
      if (!_sawMag || !_sawAcc) {
        _stopCompass();
        state = state.copyWith(
          compassAvailable: false,
          compassError: '未检测到可靠的方向传感器（磁力计/加速度计）',
        );
        _toast('设备不支持方向引导，请使用参考照片对齐或手动确认方向');
      }
    });
    try {
      _magSub = magnetometerEventStream().listen(_onMagnetometer, onError: _onCompassError);
      _accSub = accelerometerEventStream().listen(_onAccelerometer, onError: _onCompassError);
    } catch (e) {
      _compassStartupTimer?.cancel();
      state = state.copyWith(compassAvailable: false, compassError: '方向传感器初始化失败：$e');
    }
  }

  void _stopCompass() {
    _compassStartupTimer?.cancel();
    _compassStartupTimer = null;
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
    _lastMag = null;
    _lastAcc = null;
    _smoothedSin = null;
    _smoothedCos = null;
  }

  void _onMagnetometer(MagnetometerEvent event) {
    if (_disposed) return;
    _sawMag = true;
    _lastMag = event;
    _recomputeCompass();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    if (_disposed) return;
    _sawAcc = true;
    _lastAcc = event;
    _recomputeCompass();
  }

  void _onCompassError(Object error) {
    if (_disposed || _sensorErrorReported) return;
    _sensorErrorReported = true;
    _stopCompass();
    state = state.copyWith(
      compassAvailable: false,
      compassError: '方向传感器不可用：$error',
      headingDeg: null,
      directionDeltaDeg: null,
    );
    _toast('方向传感器不可用，请使用参考照片对齐或手动确认方向');
  }

  void _recomputeCompass() {
    final mag = _lastMag;
    final acc = _lastAcc;
    if (mag == null || acc == null || _disposed) return;

    _compassStartupTimer?.cancel();
    final reading = computeCompassReading(
      ax: acc.x,
      ay: acc.y,
      az: acc.z,
      mx: mag.x,
      my: mag.y,
      mz: mag.z,
    );
    final now = DateTime.now();

    if (reading == null) {
      if (_lastCompassPublish != null &&
          now.difference(_lastCompassPublish!) <
              const Duration(milliseconds: PanoConstants.compassSamplePublishMs)) {
        return;
      }
      _lastCompassPublish = now;
      final magnitude = math.sqrt(mag.x * mag.x + mag.y * mag.y + mag.z * mag.z);
      state = state.copyWith(
        compassAvailable: true,
        compassError: null,
        headingDeg: null,
        directionDeltaDeg: null,
        cameraPitchDeg: null,
        deviceRollDeg: null,
        magneticFieldUt: magnitude,
      );
      return;
    }

    final rad = degToRad(reading.headingDeg);
    final s = math.sin(rad);
    final c = math.cos(rad);
    if (_smoothedSin == null || _smoothedCos == null) {
      _smoothedSin = s;
      _smoothedCos = c;
    } else {
      final alignment = _smoothedSin! * s + _smoothedCos! * c;
      if (alignment < -0.5) {
        _smoothedSin = s;
        _smoothedCos = c;
      } else {
        const alpha = 0.28;
        _smoothedSin = _smoothedSin! * (1 - alpha) + s * alpha;
        _smoothedCos = _smoothedCos! * (1 - alpha) + c * alpha;
      }
    }
    final heading = normalizeDeg360(
      radToDeg(math.atan2(_smoothedSin!, _smoothedCos!)),
    );

    if (_lastCompassPublish != null &&
        now.difference(_lastCompassPublish!) <
            const Duration(milliseconds: PanoConstants.compassSamplePublishMs)) {
      return;
    }
    _lastCompassPublish = now;

    final target = state.activePoint?.targetAzimuthDeg;
    final delta = target == null ? null : normalizeDeg180(target - heading);
    final field = reading.fieldMagnitudeUt;
    final interfered = field < PanoConstants.compassInterferenceLowUt ||
        field > PanoConstants.compassInterferenceHighUt;
    if (interfered && !_interferenceWarned) {
      _interferenceWarned = true;
      _toast('电子罗盘受到磁场干扰：请远离金属/电子设备，并呈 8 字形晃动手机校准');
    } else if (!interfered) {
      _interferenceWarned = false;
    }

    state = state.copyWith(
      compassAvailable: true,
      compassInterfered: interfered,
      compassError: null,
      headingDeg: heading,
      cameraPitchDeg: reading.cameraPitchDeg,
      deviceRollDeg: reading.rollDeg,
      magneticFieldUt: field,
      directionDeltaDeg: delta,
    );
    _evaluateGuidance();
  }

  void captureHeadingAsTarget() {
    final point = state.activePoint;
    if (point == null) return;
    final heading = state.headingDeg;
    if (heading == null || !state.compassAvailable) {
      _toast('未获取到可靠方向读数，无法记录当前朝向');
      return;
    }
    unawaited(updatePoint(point.copyWith(targetAzimuthDeg: normalizeDeg360(heading))));
    _toast('已将当前朝向 ${formatAzimuth(heading)} 记录为目标方向');
  }

  void manualConfirmDirection() {
    final point = state.activePoint;
    if (point == null || !state.arrivalConfirmed) return;
    if (!point.hasTargetAzimuth) {
      _evaluateGuidance();
      return;
    }
    if (state.compassReliable) {
      _toast('方向传感器可用，请按罗盘指引对准目标方向');
      return;
    }
    state = state.copyWith(manualDirectionConfirmed: true);
    _evaluateGuidance();
    _toast('已手动确认拍摄方向（未经传感器校验）');
  }

  void _evaluateGuidance() {
    if (_disposed) return;
    final point = state.activePoint;
    if (point == null) return;
    final current = state.stage;
    if (!current.isGuidance || current == InspectionStage.briefing) return;
    final next = evaluateGuidanceStage(
      current: current,
      arrivalConfirmed: state.arrivalConfirmed,
      hasTargetAzimuth: point.hasTargetAzimuth,
      compassReliable: state.compassReliable,
      manualDirectionConfirmed: state.manualDirectionConfirmed,
      deltaDeg: state.directionDeltaDeg,
    );
    if (next != current) {
      state = state.copyWith(stage: next);
    }
  }

  // ---------------------------------------------------------------------------
  // 参考照片对齐
  // ---------------------------------------------------------------------------

  void openReferenceOverlay([ReferenceCompareMode mode = ReferenceCompareMode.ghost]) {
    final point = state.activePoint;
    if (point == null) return;
    if (point.referenceImagePath == null) {
      _toast('该点位暂无参考照片，请先在点位编辑中添加');
      return;
    }
    state = state.copyWith(referenceMode: mode);
  }

  void closeReferenceOverlay() {
    state = state.copyWith(referenceMode: ReferenceCompareMode.none);
  }

  void setReferenceMode(ReferenceCompareMode mode) {
    state = state.copyWith(referenceMode: mode);
  }

  void setReferenceOpacity(double opacity) {
    state = state.copyWith(referenceOpacity: opacity.clamp(0.15, 0.85));
  }

  // ---------------------------------------------------------------------------
  // 全景拍摄衔接
  // ---------------------------------------------------------------------------

  void beginPanoramaCapture() {
    final point = state.activePoint;
    if (point == null) return;
    if (state.stage != InspectionStage.ready) {
      _toast('请先确认拍摄位置并对准目标方向');
      return;
    }
    final pano = _pano;
    if (pano.state.source != CaptureSource.camera) {
      _toast('巡检拍摄需要真实摄像头，请先启用相机后重试');
      return;
    }
    if (!pano.state.cameraReady) {
      _toast(
        pano.state.cameraError == null
            ? '相机尚未就绪，请稍候重试'
            : '相机不可用：${pano.state.cameraError}',
      );
      return;
    }
    if (state.compassAvailable && !pano.state.gyroEnabled) {
      pano.toggleGyro();
    }
    pano.startInspectionCapture(yawOffsetDeg: pano.state.yaw);
    _endGuidanceStreams();
    state = state.copyWith(stage: InspectionStage.panorama, referenceMode: ReferenceCompareMode.none);
    _toast('已锁定起始方向，按点位指引完成 14 点拍摄');
  }

  Future<void> finishPanoramaCapture() async {
    if (state.stage != InspectionStage.panorama) return;
    final point = state.activePoint;
    final pano = _pano;
    if (pano.state.capturedCount == 0) {
      _toast('请先捕捉至少一个点位');
      return;
    }
    final title = point == null ? null : '${point.code} ${point.name}';
    await pano.completeStitching(titlePrefix: title);
    if (_disposed || !mounted) return;
    if (state.stage == InspectionStage.panorama &&
        pano.state.mode == AppMode.preview &&
        pano.state.activeWorkId != null) {
      onPanoramaStitched(pano.state.activeWorkId);
    }
  }

  void onPanoramaStitched(String? workId) {
    if (state.stage != InspectionStage.panorama) return;
    if (workId == null) {
      _toast('未获取到有效拍摄结果，请重新合成');
      return;
    }
    state = state.copyWith(stage: InspectionStage.review, pendingWorkId: workId);
  }

  Future<void> confirmReview() async {
    if (state.stage != InspectionStage.review) return;
    final task = state.activeTask;
    final point = state.activePoint;
    final workId = state.pendingWorkId;
    if (task == null || point == null || workId == null) {
      _toast('缺少拍摄结果，无法保存点位记录');
      return;
    }

    final updatedPoint = point.copyWith(
      records: [
        ...point.records,
        InspectionRecord(workId: workId, capturedAt: DateTime.now()),
      ],
    );
    final updatedTasks = _replacePointInTasks(state.tasks, task.id, updatedPoint);
    try {
      await _repo.saveTasks(updatedTasks);
    } catch (e) {
      _toast('巡检记录保存失败：$e');
      return;
    }
    if (_disposed || !mounted) return;

    final updatedTask = _findTaskIn(updatedTasks, task.id);
    if (updatedTask == null) return;
    final next = updatedTask.nextIncomplete(afterPointId: point.id);

    if (next != null) {
      _pano.prepareNextInspectionPoint();
      _endGuidanceStreams();
      _arrivalHintShown = false;
      state = _pointEntryState(
        state,
        task: updatedTask,
        point: next,
        stage: InspectionStage.briefing,
        tasks: updatedTasks,
      );
      _startCompass();
      if (next.hasCoordinates) {
        unawaited(refreshLocation(startStream: true));
      }
      _toast('已完成 ${point.code}，下一站 ${next.code} · ${next.name}');
    } else {
      _endGuidanceStreams();
      state = state.copyWith(
        tasks: updatedTasks,
        stage: InspectionStage.taskComplete,
        pendingWorkId: null,
        referenceMode: ReferenceCompareMode.none,
      );
      _toast('任务「${updatedTask.title}」全部点位已完成');
    }
  }

  Future<void> retakePanorama() async {
    if (state.stage != InspectionStage.review) return;
    final workId = state.pendingWorkId;
    final pano = _pano;
    if (workId != null) {
      await pano.discardWork(workId);
    }
    if (_disposed || !mounted) return;
    _arrivalHintShown = false;
    pano.prepareNextInspectionPoint();
    state = state.copyWith(
      pendingWorkId: null,
      stage: state.arrivalConfirmed ? InspectionStage.aligning : InspectionStage.positioning,
      referenceMode: ReferenceCompareMode.none,
      manualDirectionConfirmed: false,
    );
    _evaluateGuidance();
    _startCompass();
    if (state.activeHasCoordinates) {
      unawaited(refreshLocation(startStream: true));
    }
    _toast('已删除本次全景，请重新拍摄');
  }

  void exitPoint() {
    final stage = state.stage;
    if (stage == InspectionStage.idle) return;
    if (stage == InspectionStage.panorama) {
      _pano.prepareNextInspectionPoint();
    }
    _endGuidanceStreams();
    _arrivalHintShown = false;
    state = state.copyWith(
      activePointId: null,
      stage: InspectionStage.idle,
      pendingWorkId: null,
      referenceMode: ReferenceCompareMode.none,
      arrivalConfirmed: false,
      arrivalWasManual: false,
      manualDirectionConfirmed: false,
      gpsStatus: LocationUiStatus.idle,
      gpsError: null,
      latitude: null,
      longitude: null,
      gpsAccuracyM: null,
      gpsUpdatedAt: null,
      distanceM: null,
      targetBearingDeg: null,
      headingDeg: null,
      cameraPitchDeg: null,
      deviceRollDeg: null,
      magneticFieldUt: null,
      compassAvailable: false,
      compassInterfered: false,
      compassError: null,
      directionDeltaDeg: null,
    );
    if (stage == InspectionStage.review) {
      _toast('已退出点位确认，拍摄作品保留在相册');
    } else if (stage == InspectionStage.panorama) {
      _toast('已退出点位拍摄');
    } else {
      _toast('已退出点位引导');
    }
  }

  void handleAppLifecycle(AppLifecycleState lifecycle) {
    if (_disposed) return;
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.detached) {
      _stopCompass();
      _stopLocationStream();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final point = state.activePoint;
      if (point != null && state.stage.isGuidance) {
        _startCompass();
        if (point.hasCoordinates) {
          unawaited(refreshLocation(startStream: true));
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 任务 / 点位编辑
  // ---------------------------------------------------------------------------

  Future<InspectionTask?> createTask({required String title, String description = ''}) async {
    if (state.stage == InspectionStage.panorama ||
        state.stage == InspectionStage.review) {
      _toast('请先完成或退出当前点位拍摄与结果确认');
      return null;
    }
    final trimmed = title.trim();
    final task = InspectionTask(
      id: _uuid.v4(),
      title: trimmed.isEmpty ? '新建巡检任务' : trimmed,
      description: description.trim(),
      createdAt: DateTime.now(),
    );
    final tasks = [...state.tasks, task];
    try {
      await _repo.saveTasks(tasks);
    } catch (e) {
      _toast('任务保存失败：$e');
      return null;
    }
    if (_disposed || !mounted) return null;
    _endGuidanceStreams();
    state = state.copyWith(
      tasks: tasks,
      activeTaskId: task.id,
      activePointId: null,
      stage: InspectionStage.idle,
    );
    return task;
  }

  Future<InspectionPoint?> addPoint({
    required String code,
    required String name,
    String description = '',
    String instructions = '',
    String directionName = '',
    double? latitude,
    double? longitude,
    double? targetAzimuthDeg,
    double targetPitchDeg = 0,
    double arrivalRadiusM = PanoConstants.waypointArrivalRadiusM,
    String? referenceImagePath,
  }) async {
    final task = state.activeTask;
    if (task == null) {
      _toast('请先选择巡检任务');
      return null;
    }
    final point = InspectionPoint(
      id: _uuid.v4(),
      code: code.trim().isEmpty ? 'P-${task.points.length + 1}' : code.trim(),
      name: name.trim().isEmpty ? '未命名点位' : name.trim(),
      description: description.trim(),
      instructions: instructions.trim(),
      directionName: directionName.trim(),
      latitude: latitude,
      longitude: longitude,
      targetAzimuthDeg: targetAzimuthDeg,
      targetPitchDeg: targetPitchDeg,
      arrivalRadiusM: arrivalRadiusM <= 0
          ? PanoConstants.waypointArrivalRadiusM
          : arrivalRadiusM,
      referenceImagePath: referenceImagePath,
    );
    final updatedTask = task.copyWith(points: [...task.points, point]);
    final updatedTasks = _replaceTaskInTasks(state.tasks, updatedTask);
    try {
      await _repo.saveTasks(updatedTasks);
    } catch (e) {
      _toast('点位保存失败：$e');
      return null;
    }
    if (_disposed || !mounted) return null;
    state = state.copyWith(tasks: updatedTasks, activeTaskId: task.id);
    _toast('已添加点位 ${point.code}');
    return point;
  }

  Future<bool> updatePoint(InspectionPoint updated, {String? replacedReferencePath}) async {
    String? taskId;
    InspectionPoint? previous;
    for (final task in state.tasks) {
      for (final point in task.points) {
        if (point.id == updated.id) {
          taskId = task.id;
          previous = point;
          break;
        }
      }
      if (taskId != null) break;
    }
    if (taskId == null) return false;

    final updatedTasks = _replacePointInTasks(state.tasks, taskId, updated);
    try {
      await _repo.saveTasks(updatedTasks);
    } catch (e) {
      _toast('点位保存失败：$e');
      return false;
    }
    if (_disposed || !mounted) return false;
    state = state.copyWith(tasks: updatedTasks);

    if (replacedReferencePath != null &&
        replacedReferencePath != updated.referenceImagePath) {
      unawaited(_repo.deleteReferencePhoto(replacedReferencePath));
    }

    if (state.activePointId == updated.id) {
      _refreshActiveDerived(
        directionChanged: previous?.targetAzimuthDeg != updated.targetAzimuthDeg,
      );
    }
    return true;
  }

  Future<void> deletePoint(String pointId) async {
    InspectionTask? owner;
    InspectionPoint? removed;
    for (final task in state.tasks) {
      for (final point in task.points) {
        if (point.id == pointId) {
          owner = task;
          removed = point;
          break;
        }
      }
      if (owner != null) break;
    }
    if (owner == null || removed == null) return;

    final updatedTask = owner.copyWith(
      points: owner.points.where((p) => p.id != pointId).toList(),
    );
    final updatedTasks = _replaceTaskInTasks(state.tasks, updatedTask);
    try {
      await _repo.saveTasks(updatedTasks);
    } catch (e) {
      _toast('删除点位失败：$e');
      return;
    }
    if (_disposed || !mounted) return;
    if (state.activePointId == pointId) {
      _endGuidanceStreams();
      state = state.copyWith(
        tasks: updatedTasks,
        activePointId: null,
        stage: InspectionStage.idle,
        pendingWorkId: null,
      );
    } else {
      state = state.copyWith(tasks: updatedTasks);
    }
    unawaited(_repo.deleteReferencePhoto(removed.referenceImagePath));
    _toast('已删除点位 ${removed.code}');
  }

  Future<String?> storeReferencePhoto(Uint8List bytes, {String extension = 'jpg'}) async {
    try {
      return await _repo.saveReferencePhoto(bytes, extension: extension);
    } catch (e) {
      _toast('参考照片保存失败：$e');
      return null;
    }
  }

  Future<double?> measureHeadingForEditor() async {
    final wasRunning = _magSub != null;
    _startCompass();
    if (state.compassReliable) {
      return state.headingDeg;
    }
    await _waitForHeading(const Duration(seconds: 3));
    if (!_disposed && !wasRunning && state.activePoint == null) {
      _stopCompass();
    }
    if (state.headingDeg == null) {
      _toast('未获取到可靠方向读数，请竖直握持手机并校准罗盘');
      return null;
    }
    return state.headingDeg;
  }

  Future<void> _waitForHeading(Duration timeout) async {
    final completer = Completer<void>();
    late Timer poll;
    late Timer limit;
    poll = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_disposed || state.compassReliable) {
        if (!completer.isCompleted) completer.complete();
      }
    });
    limit = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    poll.cancel();
    limit.cancel();
  }

  Future<({double latitude, double longitude, double accuracy})?> acquirePositionForEditor() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('系统定位服务未开启，请打开 GPS 后重试');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _toast('定位权限已被永久拒绝，请在系统设置中开启');
        return null;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _toast('定位权限未授予，无法获取当前位置');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (latitude: pos.latitude, longitude: pos.longitude, accuracy: pos.accuracy);
    } on TimeoutException {
      _toast('定位超时，请到开阔处后重试');
    } on LocationServiceDisabledException {
      _toast('系统定位服务未开启，请打开 GPS 后重试');
    } on PermissionDeniedException {
      _toast('定位权限未授予，无法获取当前位置');
    } catch (e) {
      _toast('定位失败：$e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  InspectionTask? _findTask(String id) => _findTaskIn(state.tasks, id);

  InspectionTask? _findTaskIn(List<InspectionTask> tasks, String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  List<InspectionTask> _replaceTaskInTasks(List<InspectionTask> tasks, InspectionTask updated) {
    return tasks.map((task) => task.id == updated.id ? updated : task).toList();
  }

  List<InspectionTask> _replacePointInTasks(
    List<InspectionTask> tasks,
    String taskId,
    InspectionPoint updated,
  ) {
    return tasks.map((task) {
      if (task.id != taskId) return task;
      return task.copyWith(
        points: task.points.map((p) => p.id == updated.id ? updated : p).toList(),
      );
    }).toList();
  }

  void _refreshActiveDerived({bool directionChanged = false}) {
    final point = state.activePoint;
    if (point == null) return;

    double? distance;
    double? bearing;
    if (point.hasCoordinates && state.latitude != null && state.longitude != null) {
      distance = distanceMeters(
        lat1: state.latitude!,
        lon1: state.longitude!,
        lat2: point.latitude!,
        lon2: point.longitude!,
      );
      bearing = initialBearingDeg(
        lat1: state.latitude!,
        lon1: state.longitude!,
        lat2: point.latitude!,
        lon2: point.longitude!,
      );
    }
    final delta = point.targetAzimuthDeg != null && state.headingDeg != null
        ? normalizeDeg180(point.targetAzimuthDeg! - state.headingDeg!)
        : null;

    final wasArrivalConfirmed = state.arrivalConfirmed;
    final wasArrivalManual = state.arrivalWasManual;
    final resetManualDirection = directionChanged && state.manualDirectionConfirmed;
    final arrivalRevoked = wasArrivalConfirmed &&
        !wasArrivalManual &&
        (!point.hasCoordinates ||
            distance == null ||
            distance > point.arrivalRadiusM * 2);

    if (!point.hasCoordinates) {
      _stopLocationStream();
      state = state.copyWith(
        gpsStatus: LocationUiStatus.noCoordinates,
        gpsError: null,
        latitude: null,
        longitude: null,
        gpsAccuracyM: null,
        gpsUpdatedAt: null,
        distanceM: null,
        targetBearingDeg: null,
        directionDeltaDeg: delta,
        manualDirectionConfirmed: resetManualDirection ? false : state.manualDirectionConfirmed,
      );
    } else {
      state = state.copyWith(
        gpsStatus: state.gpsStatus == LocationUiStatus.noCoordinates
            ? LocationUiStatus.idle
            : state.gpsStatus,
        distanceM: distance,
        targetBearingDeg: bearing,
        directionDeltaDeg: delta,
        manualDirectionConfirmed: resetManualDirection ? false : state.manualDirectionConfirmed,
      );
      if (state.gpsStatus == LocationUiStatus.idle) {
        unawaited(refreshLocation(startStream: true));
      }
    }

    if (arrivalRevoked) {
      state = state.copyWith(
        arrivalConfirmed: false,
        arrivalWasManual: false,
        manualDirectionConfirmed: false,
        stage: InspectionStage.positioning,
      );
      _toast('点位位置或范围已更新，请重新确认拍摄位置');
      return;
    }

    if (state.stage == InspectionStage.ready || state.stage == InspectionStage.aligning) {
      _evaluateGuidance();
    }
  }

  void _endGuidanceStreams() {
    _stopCompass();
    _stopLocationStream();
  }

  void _toast(String message) {
    if (_disposed) return;
    _pano.showToast(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _compassStartupTimer?.cancel();
    _magSub?.cancel();
    _accSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }
}