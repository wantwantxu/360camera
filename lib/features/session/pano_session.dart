import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/utils/angle_utils.dart';
import '../../core/utils/attitude_filter.dart';
import '../../core/utils/compass_utils.dart';
import '../../data/gallery_repository.dart';
import '../../domain/app_enums.dart';
import '../../domain/capture_matrix.dart';
import '../../domain/capture_point.dart';
import '../../domain/export_options.dart';
import '../../domain/pano_work.dart';
import '../capture/camera_frame_decoder.dart';
import '../capture/procedural_pano.dart';
import '../capture/stitch_projector.dart';
import '../preview/color_filters.dart';

final panoSessionProvider =
    StateNotifierProvider<PanoSessionNotifier, PanoSessionState>((ref) {
  return PanoSessionNotifier(ref.watch(galleryRepositoryProvider));
});

class PanoSessionState {
  const PanoSessionState({
    this.mode = AppMode.capture,
    this.source = CaptureSource.camera,
    this.points = const [],
    this.yaw = 0,
    this.pitch = 0,
    this.roll = 0,
    this.fov = PanoConstants.defaultFov,
    this.gyroEnabled = false,
    this.autoLockEnabled = true,
    this.lockedTargetId,
    this.lockProgress = 0,
    this.projectionView = ProjectionView.normal,
    this.autoRotate = false,
    this.previewGyroEnabled = false,
    this.filter = ColorFilterId.none,
    this.gallery = const [],
    this.activeWorkId,
    this.previewBytes,
    this.isStitching = false,
    this.isExporting = false,
    this.flash = false,
    this.cameraReady = false,
    this.cameraError,
    this.toast,
    this.exportOptions = const ExportOptions(),
    this.nearestGuideText,
  });

  final AppMode mode;
  final CaptureSource source;
  final List<CapturePoint> points;
  final double yaw;
  final double pitch;
  final double roll;
  final double fov;
  final bool gyroEnabled;
  final bool autoLockEnabled;
  final String? lockedTargetId;
  final double lockProgress;
  final ProjectionView projectionView;
  final bool autoRotate;
  final bool previewGyroEnabled;
  final ColorFilterId filter;
  final List<PanoWork> gallery;
  final String? activeWorkId;
  final Uint8List? previewBytes;
  final bool isStitching;
  final bool isExporting;
  final bool flash;
  final bool cameraReady;
  final String? cameraError;
  final String? toast;
  final ExportOptions exportOptions;
  final String? nearestGuideText;

  int get capturedCount => points.where((e) => e.captured).length;
  int get upperCount =>
      points.where((e) => e.ring == CaptureRing.upper && e.captured).length;
  int get midCount =>
      points.where((e) => e.ring == CaptureRing.mid && e.captured).length;
  int get lowerCount =>
      points.where((e) => e.ring == CaptureRing.lower && e.captured).length;

  PanoWork? get activeWork {
    if (activeWorkId == null) return null;
    try {
      return gallery.firstWhere((e) => e.id == activeWorkId);
    } catch (_) {
      return null;
    }
  }

  PanoSessionState copyWith({
    AppMode? mode,
    CaptureSource? source,
    List<CapturePoint>? points,
    double? yaw,
    double? pitch,
    double? roll,
    double? fov,
    bool? gyroEnabled,
    bool? autoLockEnabled,
    Object? lockedTargetId = _sentinel,
    double? lockProgress,
    ProjectionView? projectionView,
    bool? autoRotate,
    bool? previewGyroEnabled,
    ColorFilterId? filter,
    List<PanoWork>? gallery,
    Object? activeWorkId = _sentinel,
    Object? previewBytes = _sentinel,
    bool? isStitching,
    bool? isExporting,
    bool? flash,
    bool? cameraReady,
    Object? cameraError = _sentinel,
    Object? toast = _sentinel,
    ExportOptions? exportOptions,
    Object? nearestGuideText = _sentinel,
  }) {
    return PanoSessionState(
      mode: mode ?? this.mode,
      source: source ?? this.source,
      points: points ?? this.points,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      fov: fov ?? this.fov,
      gyroEnabled: gyroEnabled ?? this.gyroEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      lockedTargetId: identical(lockedTargetId, _sentinel)
          ? this.lockedTargetId
          : lockedTargetId as String?,
      lockProgress: lockProgress ?? this.lockProgress,
      projectionView: projectionView ?? this.projectionView,
      autoRotate: autoRotate ?? this.autoRotate,
      previewGyroEnabled: previewGyroEnabled ?? this.previewGyroEnabled,
      filter: filter ?? this.filter,
      gallery: gallery ?? this.gallery,
      activeWorkId: identical(activeWorkId, _sentinel)
          ? this.activeWorkId
          : activeWorkId as String?,
      previewBytes: identical(previewBytes, _sentinel)
          ? this.previewBytes
          : previewBytes as Uint8List?,
      isStitching: isStitching ?? this.isStitching,
      isExporting: isExporting ?? this.isExporting,
      flash: flash ?? this.flash,
      cameraReady: cameraReady ?? this.cameraReady,
      cameraError: identical(cameraError, _sentinel)
          ? this.cameraError
          : cameraError as String?,
      toast: identical(toast, _sentinel) ? this.toast : toast as String?,
      exportOptions: exportOptions ?? this.exportOptions,
      nearestGuideText: identical(nearestGuideText, _sentinel)
          ? this.nearestGuideText
          : nearestGuideText as String?,
    );
  }
}

const _sentinel = Object();

class PanoSessionNotifier extends StateNotifier<PanoSessionState> {
  PanoSessionNotifier(this._galleryRepo)
      : super(PanoSessionState(points: createStandard14Points())) {
    _init();
  }

  final GalleryRepository _galleryRepo;
  final _uuid = const Uuid();
  final stitcher = StitchProjector();

  CameraController? cameraController;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  Timer? _tick;
  Timer? _toastTimer;
  Timer? _flashTimer;
  DateTime? _lockStart;
  DateTime? _lockMissAt;
  String? _aligningId;
  String? _guideId;
  double? _magYawOffset;
  AccelerometerEvent? _lastAcc;
  MagnetometerEvent? _lastMag;
  final AttitudeFilter _attitude = AttitudeFilter();
  DateTime? _lastAttitudeAt;
  bool _userDragging = false;
  bool _capturingFrame = false;
  int _cameraGeneration = 0;
  Future<void> _cameraOps = Future<void>.value();

  Future<void> _enqueueCameraOp(Future<void> Function() op) {
    final result = _cameraOps.then((_) => op());
    _cameraOps = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _init() async {
    final works = await _galleryRepo.loadAll();
    Uint8List? preview;
    String? activeId;
    if (works.isNotEmpty) {
      activeId = works.first.id;
      final f = File(works.first.imagePath);
      if (await f.exists()) preview = await f.readAsBytes();
    } else {
      final procedural = generateProceduralEquirectangular(CaptureSource.sunset);
      preview = Uint8List.fromList(img.encodeJpg(procedural, quality: 88));
    }
    state = state.copyWith(
      gallery: works,
      activeWorkId: activeId,
      previewBytes: preview,
    );
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) => _onTick());
  }

  Future<bool> requestPermissions() async {
    final cam = await Permission.camera.request();
    final photos = await Permission.photos.request();
    if (cam.isDenied || cam.isPermanentlyDenied) {
      showToast('需要相机权限才能拍摄全景');
      return false;
    }
    if (photos.isDenied) {
      // Soft fail — export may still use share sheet.
    }
    return cam.isGranted;
  }

  Future<void> initCamera() {
    final generation = ++_cameraGeneration;
    return _enqueueCameraOp(() => _initCameraImpl(generation));
  }

  Future<void> _initCameraImpl(int generation) async {
    try {
      final ok = await requestPermissions();
      if (generation != _cameraGeneration) return;
      if (!ok) {
        state = state.copyWith(
          cameraReady: false,
          cameraError: '相机权限未授予',
          source: CaptureSource.sunset,
        );
        return;
      }
      final cameras = await availableCameras();
      if (generation != _cameraGeneration) return;
      if (cameras.isEmpty) {
        state = state.copyWith(
          cameraReady: false,
          cameraError: '未检测到摄像头',
          source: CaptureSource.sunset,
        );
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final previous = cameraController;
      cameraController = null;
      await previous?.dispose();
      // 4:3 stills give the ~53°×67° portrait field of view the 45° capture
      // grid needs; 16:9 crops would leave uncovered slivers between points.
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      cameraController = controller;
      state = state.copyWith(
        cameraReady: true,
        cameraError: null,
        source: CaptureSource.camera,
      );
    } catch (e) {
      if (generation != _cameraGeneration) return;
      state = state.copyWith(
        cameraReady: false,
        cameraError: '相机初始化失败: $e',
        source: CaptureSource.sunset,
      );
    }
  }

  /// Stops sensors and releases the camera when leaving a capture screen.
  Future<void> releaseCamera() async {
    _cameraGeneration++;
    _stopSensors();
    _magYawOffset = null;
    _lastAcc = null;
    _lastMag = null;
    _userDragging = false;
    _attitude.clear();
    _lastAttitudeAt = null;
    _guideId = null;
    _lockMissAt = null;
    final controller = cameraController;
    cameraController = null;
    if (mounted) {
      state = state.copyWith(
        cameraReady: false,
        cameraError: null,
        gyroEnabled: false,
        lockedTargetId: null,
        lockProgress: 0,
      );
    }
    await _enqueueCameraOp(() async {
      try {
        await controller?.dispose();
      } catch (_) {
        // The OS may already have released the camera.
      }
    });
  }

  void setMode(AppMode mode) {
    if (mode == AppMode.preview) {
      state = state.copyWith(
        mode: mode,
        autoRotate: false,
        gyroEnabled: false,
      );
      if (!state.previewGyroEnabled) _stopSensors();
    } else {
      state = state.copyWith(mode: mode);
    }
  }

  void setSource(CaptureSource source) {
    state = state.copyWith(source: source);
    if (source == CaptureSource.camera && !(cameraController?.value.isInitialized ?? false)) {
      initCamera();
    }
  }

  void toggleGyro() {
    final next = !state.gyroEnabled;
    // Without sensors the tilt is unknown; a stale angle would otherwise keep
    // showing a level warning and block auto-lock in virtual-gimbal mode.
    state = state.copyWith(gyroEnabled: next, roll: next ? state.roll : 0);
    if (next) {
      _startSensors();
      showToast('已启用手机陀螺仪云台');
    } else {
      _stopSensors();
      showToast('已切换为虚拟云台（拖拽）');
    }
  }

  void toggleAutoLock() {
    state = state.copyWith(
      autoLockEnabled: !state.autoLockEnabled,
      lockProgress: 0,
      lockedTargetId: null,
    );
    _lockStart = null;
    _lockMissAt = null;
    _aligningId = null;
  }

  void _startSensors() {
    _magSub?.cancel();
    _accSub?.cancel();
    _lastMag = null;
    _lastAcc = null;
    _lastAttitudeAt = null;
    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      _lastMag = e;
      _updateAttitudeFromSensors();
    });
    _accSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      _lastAcc = e;
      _updateAttitudeFromSensors();
    });
  }

  void _stopSensors() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
    _lastAttitudeAt = null;
    _attitude.clear();
  }

  /// Feeds raw sensors through the smoothing filter. UI state is only published
  /// from [_publishSmoothedAttitude] on the 30 Hz timer so compass noise never
  /// reaches the AR overlay directly.
  void _updateAttitudeFromSensors() {
    if (!state.gyroEnabled && !state.previewGyroEnabled) return;
    if (_userDragging) return;
    final acc = _lastAcc;
    if (acc == null) return;
    final accLen = math.sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z);
    if (accLen < 1e-3) return;

    final now = DateTime.now();
    final dtMs = _lastAttitudeAt == null
        ? 50.0
        : now.difference(_lastAttitudeAt!).inMicroseconds / 1000.0;
    _lastAttitudeAt = now;

    final mag = _lastMag;
    final reading = mag == null
        ? null
        : computeCompassReading(
            ax: acc.x,
            ay: acc.y,
            az: acc.z,
            mx: mag.x,
            my: mag.y,
            mz: mag.z,
          );

    if (reading == null) {
      // Keep the last yaw when the bearing is undefined (camera aimed at the
      // ground/sky or no magnetometer); still track camera pitch and roll.
      final ux = acc.x / accLen;
      final uy = acc.y / accLen;
      final uz = acc.z / accLen;
      _attitude.update(
        yawTarget: _attitude.yaw ?? state.yaw,
        pitchTarget: clampPitch(radToDeg(math.asin((-uz).clamp(-1.0, 1.0)))),
        rollTarget: radToDeg(math.atan2(-ux, uy)),
        dtMs: dtMs,
      );
      return;
    }

    _magYawOffset ??= normalizeDeg360(state.yaw - reading.headingDeg);
    _attitude.update(
      yawTarget: normalizeDeg360(reading.headingDeg + (_magYawOffset ?? 0)),
      pitchTarget: clampPitch(reading.cameraPitchDeg),
      rollTarget: reading.rollDeg,
      dtMs: dtMs,
    );
  }

  void _publishSmoothedAttitude() {
    if (!state.gyroEnabled && !state.previewGyroEnabled) return;
    if (_userDragging) return;
    final yaw = _attitude.yaw;
    final pitch = _attitude.pitch;
    final roll = _attitude.roll;
    if (yaw == null || pitch == null || roll == null) return;
    final dYaw = normalizeDeg180(yaw - state.yaw).abs();
    final dPitch = (pitch - state.pitch).abs();
    final dRoll = normalizeDeg180(roll - state.roll).abs();
    if (dYaw < 0.08 && dPitch < 0.08 && dRoll < 0.2) return;
    state = state.copyWith(yaw: yaw, pitch: pitch, roll: roll);
  }

  void beginDrag() => _userDragging = true;

  void endDrag() {
    _userDragging = false;
    if (!state.gyroEnabled && !state.previewGyroEnabled) return;
    // Re-anchor the world offset to the dragged view so the panorama does not
    // snap back when the finger lifts.
    final acc = _lastAcc;
    final mag = _lastMag;
    if (acc != null && mag != null) {
      final reading = computeCompassReading(
        ax: acc.x,
        ay: acc.y,
        az: acc.z,
        mx: mag.x,
        my: mag.y,
        mz: mag.z,
      );
      if (reading != null) {
        _magYawOffset = normalizeDeg360(state.yaw - reading.headingDeg);
      }
    }
    _attitude.snapTo(yaw: state.yaw, pitch: state.pitch, roll: state.roll);
  }

  void nudgeAttitude({double dYaw = 0, double dPitch = 0}) {
    state = state.copyWith(
      yaw: normalizeDeg360(state.yaw + dYaw),
      pitch: clampPitch(state.pitch + dPitch),
    );
  }

  void setFov(double fov) {
    state = state.copyWith(
      fov: fov.clamp(PanoConstants.minFov, PanoConstants.maxFov),
    );
  }

  void resetCapture() {
    stitcher.reset();
    state = state.copyWith(
      points: createStandard14Points(),
      roll: state.gyroEnabled ? state.roll : 0,
      lockProgress: 0,
      lockedTargetId: null,
      nearestGuideText: null,
    );
    _lockStart = null;
    _aligningId = null;
    _guideId = null;
    _lockMissAt = null;
    showToast('已重置全部点位');
  }

  CapturePoint? findNearestUncaptured() {
    CapturePoint? best;
    var bestAng = 1e9;
    for (final p in state.points) {
      if (p.captured) continue;
      final ang = sphericalAngleDeg(state.yaw, state.pitch, p.yaw, p.pitch);
      if (ang < bestAng) {
        bestAng = ang;
        best = p;
      }
    }
    return best;
  }

  /// Nearest uncaptured point with hysteresis: the current guide target is kept
  /// until another point is clearly closer, so arrows and auto-lock do not
  /// flicker between neighbours on the staggered VR rings.
  CapturePoint? _selectStickyTarget() {
    final nearest = findNearestUncaptured();
    if (nearest == null) {
      _guideId = null;
      return null;
    }
    final stickyId = _guideId;
    if (stickyId != null && stickyId != nearest.id) {
      for (final p in state.points) {
        if (p.id != stickyId || p.captured) continue;
        final nearestAng = sphericalAngleDeg(
          state.yaw,
          state.pitch,
          nearest.yaw,
          nearest.pitch,
        );
        final stickyAng = sphericalAngleDeg(
          state.yaw,
          state.pitch,
          p.yaw,
          p.pitch,
        );
        if (stickyAng <= nearestAng + PanoConstants.autoLockExitMarginDeg) {
          return p;
        }
        break;
      }
    }
    _guideId = nearest.id;
    return nearest;
  }

  void _setLockUi(String? id, double progress) {
    if (state.lockedTargetId == id && state.lockProgress == progress) return;
    state = state.copyWith(lockedTargetId: id, lockProgress: progress);
  }

  void _clearLock() {
    _aligningId = null;
    _lockStart = null;
    _lockMissAt = null;
    _setLockUi(null, 0);
  }

  void _onTick() {
    if (state.mode == AppMode.preview &&
        state.autoRotate &&
        !state.previewGyroEnabled &&
        !_userDragging) {
      state = state.copyWith(yaw: normalizeDeg360(state.yaw + 0.35));
    }

    _publishSmoothedAttitude();

    if (state.mode != AppMode.capture) return;

    final target = _selectStickyTarget();

    if (_capturingFrame) {
      // Keep the lock ring full while the still is being written: the photo is
      // taken asynchronously, so clearing the cue immediately made users start
      // turning again mid-exposure and every frame picked up a few degrees of
      // smear. The next tick after capture releases the cue.
      return;
    }

    String? guide;
    var ang = double.infinity;
    if (target != null) {
      ang = sphericalAngleDeg(state.yaw, state.pitch, target.yaw, target.pitch);
      if (ang > PanoConstants.alignThresholdDeg) {
        final dy = normalizeDeg180(target.yaw - state.yaw);
        final dp = target.pitch - state.pitch;
        final dir = dy.abs() > dp.abs()
            ? (dy > 0 ? '向右' : '向左')
            : (dp > 0 ? '向上' : '向下');
        guide = '$dir ${ang.toStringAsFixed(0)}° 寻找 ${target.id}';
      }
    }
    if (guide != state.nearestGuideText) {
      state = state.copyWith(nearestGuideText: guide);
    }

    if (!state.autoLockEnabled || target == null) {
      _clearLock();
      return;
    }

    final gyroActive = state.gyroEnabled || state.previewGyroEnabled;
    final stable = !gyroActive ||
        _attitude.rateDps <= PanoConstants.autoLockStableRateDps;
    final levelOk = state.roll.abs() <= PanoConstants.rollWarnDeg;

    if (_aligningId != target.id) {
      _aligningId = null;
      _lockStart = null;
      _lockMissAt = null;
      if (ang <= PanoConstants.alignThresholdDeg && levelOk && stable) {
        _aligningId = target.id;
        _lockStart = DateTime.now();
        _setLockUi(target.id, 0);
      } else {
        _setLockUi(null, 0);
      }
      return;
    }

    final withinHold = ang <=
        PanoConstants.alignThresholdDeg + PanoConstants.autoLockExitMarginDeg;
    if (!withinHold || !levelOk || !stable) {
      // Brief sensor glitches or a small hand tremor should not discard the
      // hold; only give up after the miss tolerance elapses.
      final now = DateTime.now();
      _lockMissAt ??= now;
      if (now.difference(_lockMissAt!).inMilliseconds >=
          PanoConstants.autoLockMissToleranceMs) {
        _clearLock();
      }
      return;
    }
    _lockMissAt = null;
    _lockStart ??= DateTime.now();
    final elapsed = DateTime.now().difference(_lockStart!).inMilliseconds;
    final progress = (elapsed / PanoConstants.autoLockHoldMs).clamp(0.0, 1.0);
    _setLockUi(target.id, progress);
    if (progress >= 1) {
      _aligningId = null;
      _lockStart = null;
      _lockMissAt = null;
      // Leave the ring at 100% ("已锁定 · 保持稳定") until capturePoint
      // finishes; see the _capturingFrame branch above.
      unawaited(capturePoint(target));
    }
  }

  Future<void> handleShutter() async {
    if (state.mode == AppMode.preview) {
      setMode(AppMode.capture);
      return;
    }
    final nearest = _selectStickyTarget();
    if (nearest == null) {
      showToast('全部点位已捕捉，可点击合成预览');
      return;
    }
    final ang = sphericalAngleDeg(state.yaw, state.pitch, nearest.yaw, nearest.pitch);
    if (ang > PanoConstants.alignThresholdDeg * 1.6) {
      showToast('请先对准 ${nearest.id}');
      return;
    }
    await capturePoint(nearest);
  }

  Future<void> capturePoint(CapturePoint point) async {
    if (point.captured || _capturingFrame) return;
    // Snapshot the actual pointing direction at shutter time; the point may be
    // up to the lock tolerance away, and projecting at the point's nominal
    // angle would shift every patch and produce visible seams.
    final captureYaw = state.yaw;
    final capturePitch = state.pitch;
    final captureRoll = state.roll;
    _capturingFrame = true;
    try {
      _triggerFlash();

      var hasFrame = false;
      try {
        if (state.source == CaptureSource.camera &&
            (cameraController?.value.isInitialized ?? false)) {
          final file = await cameraController!.takePicture();
          final bytes = await File(file.path).readAsBytes();
          try {
            await File(file.path).delete();
          } catch (_) {}
          final decoded = await decodeCameraFrame(bytes);
          if (decoded != null) {
            stitcher.projectRgba(
              rgba: decoded.rgba,
              imageWidth: decoded.width,
              imageHeight: decoded.height,
              yawDeg: captureYaw,
              pitchDeg: capturePitch,
              rollDeg: captureRoll,
            );
            hasFrame = true;
          } else {
            final frame = img.decodeImage(bytes);
            if (frame != null) {
              stitcher.projectFrame(
                frame,
                yawDeg: captureYaw,
                pitchDeg: capturePitch,
                rollDeg: captureRoll,
              );
              hasFrame = true;
            }
          }
        } else {
          final preset = state.source == CaptureSource.camera
              ? CaptureSource.sunset
              : state.source;
          final full = generateProceduralEquirectangular(preset, width: 1024, height: 512);
          // Crop a FOV-like patch around current attitude for demo sources.
          final cx = (normalizeDeg360(point.yaw) / 360 * full.width).round();
          final cy = ((90 - point.pitch) / 180 * full.height).round();
          final pw = full.width ~/ 5;
          final ph = full.height ~/ 3;
          final frame = img.copyCrop(
            full,
            x: (cx - pw ~/ 2).clamp(0, full.width - pw),
            y: (cy - ph ~/ 2).clamp(0, full.height - ph),
            width: pw,
            height: ph,
          );
          stitcher.projectFrame(
            frame,
            yawDeg: point.yaw,
            pitchDeg: point.pitch,
            rollDeg: captureRoll,
          );
          hasFrame = true;
        }
      } catch (e) {
        showToast('捕捉失败: $e');
        return;
      }

      if (!hasFrame) {
        showToast('无法解码图像帧');
        return;
      }

      final updated = state.points
          .map((e) => e.id == point.id ? e.copyWith(captured: true) : e)
          .toList();
      state = state.copyWith(points: updated);
      final done = updated.every((e) => e.captured);
      showToast(
        done
            ? '已捕捉全部 ${updated.length} 个方向，可以完成拍摄'
            : '已捕捉 ${point.id}（${state.capturedCount}/${updated.length}）',
      );
    } finally {
      _capturingFrame = false;
    }
  }

  Future<void> instantFullStitch() async {
    _triggerFlash();
    final preset = state.source == CaptureSource.camera
        ? CaptureSource.sunset
        : state.source;
    final full = generateProceduralEquirectangular(preset);
    stitcher.buffer = full;
    final updated = state.points.map((e) => e.copyWith(captured: true)).toList();
    state = state.copyWith(points: updated);
    await completeStitching(titlePrefix: '${preset.label} · 一键全景');
  }

  Future<PanoWork?> completeStitching({String? titlePrefix}) async {
    if (state.capturedCount == 0 && titlePrefix == null) {
      showToast('请先捕捉至少一个点位');
      return null;
    }
    if (state.isStitching) return null;
    state = state.copyWith(isStitching: true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // 4K JPEG encoding blocks for seconds; keep the UI responsive by
      // encoding from a snapshot on a background isolate.
      final bytes = await compute(
        _encodeEquirectJpeg,
        (stitcher.snapshotRgba(), stitcher.width, stitcher.height, 92),
      );
      final work = await _persistWork(
        bytes: bytes,
        title: titlePrefix ??
            '${state.points.length}点实景全景 (${DateTime.now().toString().substring(11, 16)})',
        source: state.source.name,
        width: stitcher.width,
        height: stitcher.height,
      );
      state = state.copyWith(
        isStitching: false,
        mode: AppMode.preview,
        gyroEnabled: false,
        previewBytes: bytes,
        activeWorkId: work.id,
        gallery: [work, ...state.gallery.where((e) => e.id != work.id)],
      );
      if (!state.previewGyroEnabled) _stopSensors();
      showToast('全景合成完成！拖动查看拼接效果');
      return work;
    } catch (e) {
      state = state.copyWith(isStitching: false);
      showToast('全景合成失败：$e');
      return null;
    }
  }

  /// 以当前视角作为 H-01 的起始方向，重置并进入巡检拍摄。
  void startInspectionCapture({double yawOffsetDeg = 0}) {
    _resetCaptureMatrix(yawOffsetDeg: yawOffsetDeg);
    state = state.copyWith(
      mode: AppMode.capture,
      roll: state.gyroEnabled ? state.roll : 0,
    );
  }

  /// 手机拍 VR：以当前视角为起点启动 8×3 共 24 个方向的采集。
  ///
  /// When [compassHeadingDeg] is supplied the panorama longitude 0° is anchored
  /// to that measured world heading, and the view is reset to [yawOffsetDeg],
  /// so H-01 matches the direction the phone was facing when capture started.
  bool startVrCapture({
    double yawOffsetDeg = 0,
    double? compassHeadingDeg,
  }) {
    if (state.source != CaptureSource.camera ||
        !state.cameraReady ||
        !(cameraController?.value.isInitialized ?? false)) {
      showToast('需要可用的后置相机才能开始空间采集');
      return false;
    }
    _resetCaptureMatrix(yawOffsetDeg: yawOffsetDeg, vrLayout: true);
    if (compassHeadingDeg != null && compassHeadingDeg.isFinite) {
      _magYawOffset = normalizeDeg360(yawOffsetDeg - compassHeadingDeg);
      state = state.copyWith(
        mode: AppMode.capture,
        gyroEnabled: true,
        yaw: normalizeDeg360(yawOffsetDeg),
        pitch: 0,
        roll: 0,
        points: state.points,
      );
    } else {
      state = state.copyWith(
        mode: AppMode.capture,
        gyroEnabled: true,
        pitch: 0,
        roll: 0,
        points: state.points,
      );
    }
    _attitude.snapTo(yaw: state.yaw, pitch: state.pitch, roll: state.roll);
    _startSensors();
    showToast('开始采集 · 保持机位不动并缓慢转动');
    return true;
  }

  /// 完成一个巡检点位后静默重置矩阵，供下一个点位使用。
  void prepareNextInspectionPoint() {
    _resetCaptureMatrix();
    state = state.copyWith(
      mode: AppMode.capture,
      roll: state.gyroEnabled ? state.roll : 0,
    );
  }

  void _resetCaptureMatrix({
    double yawOffsetDeg = 0,
    bool vrLayout = false,
  }) {
    stitcher.reset();
    _lockStart = null;
    _aligningId = null;
    _lockMissAt = null;
    _guideId = null;
    state = state.copyWith(
      points: vrLayout
          ? createVr24Points(yawOffsetDeg: yawOffsetDeg)
          : createStandard14Points(yawOffsetDeg: yawOffsetDeg),
      lockProgress: 0,
      lockedTargetId: null,
      nearestGuideText: null,
    );
  }

  Future<void> discardWork(String id) async {
    await _galleryRepo.delete(id);
    final remaining = state.gallery.where((e) => e.id != id).toList();
    var activeId = state.activeWorkId;
    var preview = state.previewBytes;
    if (activeId == id) {
      if (remaining.isEmpty) {
        activeId = null;
        preview = null;
      } else {
        activeId = remaining.first.id;
        try {
          preview = await File(remaining.first.imagePath).readAsBytes();
        } catch (_) {
          preview = null;
        }
      }
    }
    state = state.copyWith(
      gallery: remaining,
      activeWorkId: activeId,
      previewBytes: preview,
    );
  }

  Future<PanoWork> _persistWork({
    required Uint8List bytes,
    required String title,
    required String source,
    required int width,
    required int height,
  }) async {
    final id = _uuid.v4();
    final imagesDir = await _galleryRepo.imagesDir();
    final thumbsDir = await _galleryRepo.thumbsDir();
    final imagePath = p.join(imagesDir, '$id.jpg');
    final thumbPath = p.join(thumbsDir, '$id.jpg');
    await File(imagePath).writeAsBytes(bytes);

    // Decoding a 4K JPEG in pure Dart stalls the UI; offload the thumbnail.
    final thumb = await compute(_encodeThumbJpeg, (bytes, 320, 80));
    await File(thumbPath).writeAsBytes(thumb.isEmpty ? bytes : thumb);

    final work = PanoWork(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      imagePath: imagePath,
      thumbPath: thumbPath,
      source: source,
      width: width,
      height: height,
    );
    await _galleryRepo.upsert(work);
    return work;
  }

  Future<void> importLocalImage() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final file = files.first;
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      showToast('无法读取所选图片');
      return;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      showToast('不支持的图片格式');
      return;
    }
    final jpg = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
    final work = await _persistWork(
      bytes: jpg,
      title: '导入 · ${file.name}',
      source: 'import',
      width: decoded.width,
      height: decoded.height,
    );
    state = state.copyWith(
      mode: AppMode.preview,
      previewBytes: jpg,
      activeWorkId: work.id,
      gallery: [work, ...state.gallery.where((e) => e.id != work.id)],
    );
    showToast('已导入全景图');
  }

  Future<void> loadWork(String id) async {
    PanoWork? work;
    for (final item in state.gallery) {
      if (item.id == id) {
        work = item;
        break;
      }
    }
    if (work == null) return;
    final bytes = await File(work.imagePath).readAsBytes();
    state = state.copyWith(
      activeWorkId: id,
      previewBytes: bytes,
      mode: AppMode.preview,
    );
  }

  void setProjectionView(ProjectionView view) {
    state = state.copyWith(projectionView: view);
  }

  void toggleAutoRotate() {
    state = state.copyWith(autoRotate: !state.autoRotate);
  }

  void togglePreviewGyro() {
    final next = !state.previewGyroEnabled;
    state = state.copyWith(previewGyroEnabled: next);
    if (next) {
      if (!state.gyroEnabled) _startSensors();
      showToast('体感环顾已开启');
    } else if (!state.gyroEnabled) {
      _stopSensors();
    }
  }

  void setFilter(ColorFilterId id) {
    state = state.copyWith(filter: id);
  }

  void updateExportOptions(ExportOptions options) {
    state = state.copyWith(exportOptions: options);
  }

  Future<void> exportCurrent({
    required double snapshotLon,
    required double snapshotLat,
    required double snapshotFov,
  }) async {
    final base = state.previewBytes;
    if (base == null) {
      showToast('没有可导出的全景');
      return;
    }
    state = state.copyWith(isExporting: true);
    try {
      final opts = state.exportOptions;
      final decoded = img.decodeImage(base);
      if (decoded == null) throw Exception('解码失败');

      img.Image output;
      if (opts.type == ExportType.equirectangular) {
        final (w, h) = opts.pixelSize;
        output = img.copyResize(decoded, width: w, height: h);
        output = applyImageFilter(output, state.filter);
      } else {
        output = _renderFlatSnapshot(
          decoded,
          lon: snapshotLon,
          lat: snapshotLat,
          fov: snapshotFov,
          width: 1920,
          height: 1080,
        );
        output = applyImageFilter(output, state.filter);
      }

      if (opts.includeWatermark) {
        _drawWatermark(output);
      }

      final bytes = opts.format == ExportFormat.png
          ? Uint8List.fromList(img.encodePng(output))
          : Uint8List.fromList(img.encodeJpg(output, quality: 92));

      final ext = opts.format == ExportFormat.png ? 'png' : 'jpg';
      final tmpDir = await _galleryRepo.imagesDir();
      final outPath = p.join(
        tmpDir,
        'export_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await File(outPath).writeAsBytes(bytes);

      try {
        await Gal.putImage(outPath, album: 'PANO 360 Pro');
      } catch (_) {
        // Fall through to share.
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outPath)],
          text: 'PANO 360 Pro 导出',
        ),
      );
      showToast('导出完成');
    } catch (e) {
      showToast('导出失败: $e');
    } finally {
      state = state.copyWith(isExporting: false);
    }
  }

  img.Image _renderFlatSnapshot(
    img.Image pano, {
    required double lon,
    required double lat,
    required double fov,
    required int width,
    required int height,
  }) {
    final out = img.Image(width: width, height: height, numChannels: 4);
    final aspect = width / height;
    final fovY = degToRad(fov);
    final fovX = fovY * aspect;
    final yaw0 = degToRad(lon);
    final pitch0 = degToRad(lat);

    for (var y = 0; y < height; y++) {
      final ny = (y + 0.5) / height * 2 - 1;
      for (var x = 0; x < width; x++) {
        final nx = (x + 0.5) / width * 2 - 1;
        final dirX = math.tan(nx * fovX / 2);
        final dirY = -math.tan(ny * fovY / 2);
        final dirZ = 1.0;
        final len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ);
        var dx = dirX / len;
        var dy = dirY / len;
        var dz = dirZ / len;

        // Rotate by pitch then yaw.
        final cp = math.cos(pitch0);
        final sp = math.sin(pitch0);
        final y2 = dy * cp - dz * sp;
        final z2 = dy * sp + dz * cp;
        dy = y2;
        dz = z2;
        final cy = math.cos(yaw0);
        final sy = math.sin(yaw0);
        final x3 = dx * cy + dz * sy;
        final z3 = -dx * sy + dz * cy;
        dx = x3;
        dz = z3;

        final theta = math.atan2(dx, dz);
        final phi = math.asin(dy.clamp(-1.0, 1.0));
        final u = normalizeDeg360(radToDeg(theta)) / 360.0;
        final v = 0.5 - radToDeg(phi) / 180.0;
        final px = (u * pano.width).floor().clamp(0, pano.width - 1);
        final py = (v * pano.height).floor().clamp(0, pano.height - 1);
        final c = pano.getPixel(px, py);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  void _drawWatermark(img.Image image) {
    final text = 'PANO 360 Pro';
    img.drawString(
      image,
      text,
      font: img.arial24,
      x: image.width - 220,
      y: image.height - 40,
      color: img.ColorRgba8(245, 158, 11, 200),
    );
  }

  void _triggerFlash() {
    state = state.copyWith(flash: true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 180), () {
      state = state.copyWith(flash: false);
    });
  }

  void showToast(String msg) {
    state = state.copyWith(toast: msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      state = state.copyWith(toast: null);
    });
  }

  void clearToast() => state = state.copyWith(toast: null);

  void slewToNearest() {
    final n = _selectStickyTarget();
    if (n == null) {
      showToast('没有未捕捉点位');
      return;
    }
    final yaw = normalizeDeg360(n.yaw);
    final pitch = clampPitch(n.pitch);
    state = state.copyWith(yaw: yaw, pitch: pitch);
    if (state.gyroEnabled || state.previewGyroEnabled) {
      final acc = _lastAcc;
      final mag = _lastMag;
      if (acc != null && mag != null) {
        final reading = computeCompassReading(
          ax: acc.x,
          ay: acc.y,
          az: acc.z,
          mx: mag.x,
          my: mag.y,
          mz: mag.z,
        );
        if (reading != null) {
          _magYawOffset = normalizeDeg360(yaw - reading.headingDeg);
          _attitude.snapTo(yaw: yaw, pitch: pitch, roll: state.roll);
        }
      }
    }
    showToast('已转向 ${n.id}');
  }

  @override
  void dispose() {
    _tick?.cancel();
    _toastTimer?.cancel();
    _flashTimer?.cancel();
    _stopSensors();
    cameraController?.dispose();
    super.dispose();
  }
}

Uint8List _encodeEquirectJpeg((Uint8List, int, int, int) args) {
  final (rgba, width, height, quality) = args;
  final sharpened = _unsharpRgba(rgba, width, height);
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: sharpened.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: quality);
}

/// Mild unsharp mask to restore the modulation lost to bilinear resampling
/// and JPEG-90 compression without introducing visible halos at 4K.
Uint8List _unsharpRgba(
  Uint8List rgba,
  int width,
  int height, {
  double amount = 0.35,
}) {
  final blur = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final i = (row + x) * 4;
      final l = x > 0 ? i - 4 : i;
      final r = x < width - 1 ? i + 4 : i;
      final o = (row + x) * 3;
      for (var c = 0; c < 3; c++) {
        blur[o + c] = (rgba[l + c] + 2 * rgba[i + c] + rgba[r + c]) >> 2;
      }
    }
  }
  final out = Uint8List.fromList(rgba);
  for (var y = 0; y < height; y++) {
    final up = y > 0 ? y - 1 : y;
    final down = y < height - 1 ? y + 1 : y;
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 3;
      final ou = (up * width + x) * 3;
      final od = (down * width + x) * 3;
      final i = (y * width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final b = (blur[ou + c] + 2 * blur[o + c] + blur[od + c]) >> 2;
        final v = rgba[i + c];
        out[i + c] = (v + (v - b) * amount).round().clamp(0, 255);
      }
    }
  }
  return out;
}

Uint8List _encodeThumbJpeg((Uint8List, int, int) args) {
  final (bytes, width, quality) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return Uint8List(0);
  return img.encodeJpg(
    img.copyResize(decoded, width: width),
    quality: quality,
  );
}
