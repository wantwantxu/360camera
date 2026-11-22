import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../../data/gallery_repository.dart';
import '../../domain/app_enums.dart';
import '../../domain/capture_matrix.dart';
import '../../domain/capture_point.dart';
import '../../domain/export_options.dart';
import '../../domain/pano_work.dart';
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
  String? _aligningId;
  double? _magYawOffset;
  AccelerometerEvent? _lastAcc;
  MagnetometerEvent? _lastMag;
  bool _userDragging = false;

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
    await initCamera();
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

  Future<void> initCamera() async {
    try {
      final ok = await requestPermissions();
      if (!ok) {
        state = state.copyWith(
          cameraReady: false,
          cameraError: '相机权限未授予',
          source: CaptureSource.sunset,
        );
        return;
      }
      final cameras = await availableCameras();
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
      await cameraController?.dispose();
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      cameraController = controller;
      state = state.copyWith(
        cameraReady: true,
        cameraError: null,
        source: CaptureSource.camera,
      );
    } catch (e) {
      state = state.copyWith(
        cameraReady: false,
        cameraError: '相机初始化失败: $e',
        source: CaptureSource.sunset,
      );
    }
  }

  void setMode(AppMode mode) {
    state = state.copyWith(mode: mode);
    if (mode == AppMode.preview) {
      state = state.copyWith(autoRotate: false);
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
    state = state.copyWith(gyroEnabled: next);
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
    _aligningId = null;
  }

  void _startSensors() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = magnetometerEventStream().listen((e) {
      _lastMag = e;
      _updateAttitudeFromSensors();
    });
    _accSub = accelerometerEventStream().listen((e) {
      _lastAcc = e;
      _updateAttitudeFromSensors();
    });
  }

  void _stopSensors() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
  }

  void _updateAttitudeFromSensors() {
    if (!state.gyroEnabled && !state.previewGyroEnabled) return;
    if (_userDragging) return;
    final acc = _lastAcc;
    final mag = _lastMag;
    if (acc == null) return;

    final pitch = radToDeg(math.atan2(-acc.y, math.sqrt(acc.x * acc.x + acc.z * acc.z)));
    final roll = radToDeg(math.atan2(acc.x, acc.z));

    double yaw = state.yaw;
    if (mag != null) {
      final mx = mag.x;
      final my = mag.y;
      final mz = mag.z;
      // Tilt-compensated heading (approx).
      final rollRad = degToRad(roll);
      final pitchRad = degToRad(pitch);
      final xh = mx * math.cos(pitchRad) + mz * math.sin(pitchRad);
      final yh = mx * math.sin(rollRad) * math.sin(pitchRad) +
          my * math.cos(rollRad) -
          mz * math.sin(rollRad) * math.cos(pitchRad);
      var heading = radToDeg(math.atan2(-yh, xh));
      heading = normalizeDeg360(heading);
      _magYawOffset ??= normalizeDeg360(state.yaw - heading);
      yaw = normalizeDeg360(heading + (_magYawOffset ?? 0));
    }

    state = state.copyWith(
      yaw: yaw,
      pitch: clampPitch(pitch),
      roll: roll,
    );
  }

  void beginDrag() => _userDragging = true;
  void endDrag() => _userDragging = false;

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
      lockProgress: 0,
      lockedTargetId: null,
      nearestGuideText: null,
    );
    _lockStart = null;
    _aligningId = null;
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

  void _onTick() {
    if (state.mode == AppMode.preview && state.autoRotate && !_userDragging) {
      state = state.copyWith(yaw: normalizeDeg360(state.yaw + 0.35));
    }

    if (state.mode != AppMode.capture) return;

    final nearest = findNearestUncaptured();
    String? guide;
    if (nearest != null) {
      final ang = sphericalAngleDeg(state.yaw, state.pitch, nearest.yaw, nearest.pitch);
      if (ang > PanoConstants.alignThresholdDeg) {
        final dy = normalizeDeg180(nearest.yaw - state.yaw);
        final dp = nearest.pitch - state.pitch;
        final dir = dy.abs() > dp.abs()
            ? (dy > 0 ? '向右' : '向左')
            : (dp > 0 ? '向上' : '向下');
        guide = '$dir ${ang.toStringAsFixed(0)}° 寻找 ${nearest.id}';
      }
    }
    if (guide != state.nearestGuideText) {
      state = state.copyWith(nearestGuideText: guide);
    }

    if (!state.autoLockEnabled || nearest == null) {
      if (state.lockProgress != 0 || state.lockedTargetId != null) {
        state = state.copyWith(lockProgress: 0, lockedTargetId: null);
      }
      return;
    }

    final ang = sphericalAngleDeg(state.yaw, state.pitch, nearest.yaw, nearest.pitch);
    final levelOk = state.roll.abs() <= PanoConstants.rollWarnDeg;
    if (ang <= PanoConstants.alignThresholdDeg && levelOk) {
      if (_aligningId != nearest.id) {
        _aligningId = nearest.id;
        _lockStart = DateTime.now();
        state = state.copyWith(lockedTargetId: nearest.id, lockProgress: 0);
      } else {
        final elapsed =
            DateTime.now().difference(_lockStart ?? DateTime.now()).inMilliseconds;
        final progress = (elapsed / PanoConstants.autoLockHoldMs).clamp(0.0, 1.0);
        state = state.copyWith(
          lockedTargetId: nearest.id,
          lockProgress: progress,
        );
        if (progress >= 1) {
          unawaited(capturePoint(nearest));
          _aligningId = null;
          _lockStart = null;
          state = state.copyWith(lockProgress: 0, lockedTargetId: null);
        }
      }
    } else {
      _aligningId = null;
      _lockStart = null;
      if (state.lockProgress != 0 || state.lockedTargetId != null) {
        state = state.copyWith(lockProgress: 0, lockedTargetId: null);
      }
    }
  }

  Future<void> handleShutter() async {
    if (state.mode == AppMode.preview) {
      setMode(AppMode.capture);
      return;
    }
    final nearest = findNearestUncaptured();
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
    if (point.captured) return;
    _triggerFlash();

    img.Image? frame;
    try {
      if (state.source == CaptureSource.camera &&
          (cameraController?.value.isInitialized ?? false)) {
        final file = await cameraController!.takePicture();
        final bytes = await File(file.path).readAsBytes();
        frame = img.decodeImage(bytes);
        try {
          await File(file.path).delete();
        } catch (_) {}
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
        frame = img.copyCrop(
          full,
          x: (cx - pw ~/ 2).clamp(0, full.width - pw),
          y: (cy - ph ~/ 2).clamp(0, full.height - ph),
          width: pw,
          height: ph,
        );
      }
    } catch (e) {
      showToast('捕捉失败: $e');
      return;
    }

    if (frame == null) {
      showToast('无法解码图像帧');
      return;
    }

    stitcher.projectFrame(
      frame,
      yawDeg: point.yaw,
      pitchDeg: point.pitch,
    );

    final updated = state.points
        .map((e) => e.id == point.id ? e.copyWith(captured: true) : e)
        .toList();
    state = state.copyWith(points: updated);
    showToast('已捕捉 ${point.id}（${state.capturedCount}/14）');
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

  Future<void> completeStitching({String? titlePrefix}) async {
    if (state.capturedCount == 0 && titlePrefix == null) {
      showToast('请先捕捉至少一个点位');
      return;
    }
    state = state.copyWith(isStitching: true);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final bytes = stitcher.encodeJpeg(quality: 90);
    final work = await _persistWork(
      bytes: bytes,
      title: titlePrefix ??
          '14点实景全景 (${DateTime.now().toString().substring(11, 16)})',
      source: state.source.name,
      width: stitcher.width,
      height: stitcher.height,
    );

    state = state.copyWith(
      isStitching: false,
      mode: AppMode.preview,
      previewBytes: bytes,
      activeWorkId: work.id,
      gallery: [work, ...state.gallery.where((e) => e.id != work.id)],
    );
    showToast('全景合成完成！支持拖拽环顾与小行星视角');
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

    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final thumb = img.copyResize(decoded, width: 320);
      await File(thumbPath).writeAsBytes(img.encodeJpg(thumb, quality: 80));
    } else {
      await File(thumbPath).writeAsBytes(bytes);
    }

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
    final n = findNearestUncaptured();
    if (n == null) {
      showToast('没有未捕捉点位');
      return;
    }
    state = state.copyWith(yaw: n.yaw, pitch: n.pitch);
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
