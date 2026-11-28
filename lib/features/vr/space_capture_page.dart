import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/theme/space_theme.dart';
import '../../core/utils/angle_utils.dart';
import '../../core/utils/heading_sampler.dart';
import '../../domain/app_enums.dart';
import '../../domain/vr_space.dart';
import '../capture/widgets/camera_preview_cover.dart';
import '../capture/widgets/capture_hud.dart';
import '../preview/pano_sphere_view.dart';
import '../session/pano_session.dart';
import 'space_routes.dart';
import 'spaces_controller.dart';

enum _CapturePhase { ready, capturing, stitching, review, saved }

class SpaceCapturePage extends ConsumerStatefulWidget {
  const SpaceCapturePage({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<SpaceCapturePage> createState() => _SpaceCapturePageState();
}

class _SpaceCapturePageState extends ConsumerState<SpaceCapturePage> {
  final TextEditingController _nameController = TextEditingController();
  final HeadingSampler _heading = HeadingSampler();
  late final PanoSessionNotifier _panoNotifier;

  _CapturePhase _phase = _CapturePhase.ready;
  late final Timer _statusTimer;
  double? _captureHeading;
  bool _captureHeadingReliable = false;
  bool _starting = false;
  bool _busy = false;
  bool _allowPop = false;
  bool _autoFinishTriggered = false;
  String? _lastSavedPointId;

  @override
  void initState() {
    super.initState();
    _panoNotifier = ref.read(panoSessionProvider.notifier);
    _heading.start();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      if (_phase == _CapturePhase.ready) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _preparePage());
  }

  @override
  void dispose() {
    _statusTimer.cancel();
    _heading.dispose();
    _nameController.dispose();
    unawaited(_panoNotifier.releaseCamera());
    super.dispose();
  }

  Future<void> _preparePage() async {
    if (!mounted) return;
    _panoNotifier.setMode(AppMode.capture);
    final space = ref.read(spacesProvider).byId(widget.spaceId);
    if (space != null && _nameController.text.trim().isEmpty) {
      _nameController.text = _suggestName(space);
    }
    if (!ref.read(panoSessionProvider).cameraReady) {
      await _panoNotifier.initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider);
    final pano = ref.watch(panoSessionProvider);
    final space = spaces.byId(widget.spaceId);
    final sessionToast = pano.toast;

    if (space == null) {
      return Theme(
        data: buildSpaceTheme(),
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: spaces.loading
                  ? const CircularProgressIndicator(color: SpaceColors.accent)
                  : _MissingSpace(onBack: _popNow),
            ),
          ),
        ),
      );
    }

    if (_phase == _CapturePhase.capturing &&
        pano.points.isNotEmpty &&
        pano.capturedCount == pano.points.length &&
        !_autoFinishTriggered) {
      _autoFinishTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _CapturePhase.capturing) {
          unawaited(_finishCapture());
        }
      });
    }

    return Theme(
      data: buildSpaceTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: PopScope(
          canPop: _allowPop ||
              _phase == _CapturePhase.ready ||
              _phase == _CapturePhase.saved,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _requestExit();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: true,
            body: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackdrop(pano),
                if (_phase == _CapturePhase.ready)
                  _buildReadyLayer(space, pano),
                if (_phase == _CapturePhase.capturing)
                  _buildCaptureLayer(space, pano),
                if (_phase == _CapturePhase.stitching ||
                    pano.isStitching)
                  const _StitchingOverlay(),
                if (_phase == _CapturePhase.review && !pano.isStitching)
                  _buildReviewLayer(space, pano),
                if (_phase == _CapturePhase.saved)
                  _buildSavedLayer(space),
                if (pano.flash)
                  const IgnorePointer(
                    child: ColoredBox(color: Color(0xCCFFFFFF)),
                  ),
                if (sessionToast != null)
                  _AutoToast(
                    key: ValueKey(sessionToast),
                    message: sessionToast,
                    onExpired: () {
                      ref.read(panoSessionProvider.notifier).clearToast();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop(PanoSessionState pano) {
    if (_phase == _CapturePhase.review) {
      return PanoSphereView(
        imageBytes: pano.previewBytes,
        lon: pano.yaw,
        lat: pano.pitch,
        fov: pano.fov,
        view: ProjectionView.normal,
        interactive: true,
        onDragStart: ref.read(panoSessionProvider.notifier).beginDrag,
        onDragEnd: ref.read(panoSessionProvider.notifier).endDrag,
        onAttitudeChanged: (delta) =>
            ref.read(panoSessionProvider.notifier).nudgeAttitude(
                  dYaw: delta.dx,
                  dPitch: delta.dy,
                ),
        onFovChanged: ref.read(panoSessionProvider.notifier).setFov,
      );
    }

    final notifier = ref.read(panoSessionProvider.notifier);
    final controller = notifier.cameraController;
    if (pano.mode == AppMode.capture &&
        pano.cameraReady &&
        controller != null &&
        controller.value.isInitialized) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          if (!pano.gyroEnabled) notifier.beginDrag();
        },
        onPanUpdate: (d) {
          if (pano.gyroEnabled) return;
          notifier.nudgeAttitude(
            dYaw: -d.delta.dx * 0.18,
            dPitch: d.delta.dy * 0.14,
          );
        },
        onPanEnd: (_) {
          if (!pano.gyroEnabled) notifier.endDrag();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreviewCover(controller),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xB309090B),
                    Colors.transparent,
                    Color(0xB309090B),
                  ],
                  stops: [0, 0.42, 1],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF121822), Color(0xFF09090B), Color(0xFF151A23)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.panorama_photosphere_rounded,
          size: 84,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _buildReadyLayer(VrSpace space, PanoSessionState pano) {
    final nextNumber = space.points.length + 1;
    final hasHeading = _heading.headingDeg != null;
    final reliable = _heading.isReliable;
    final canStart = pano.cameraReady && hasHeading && !_starting;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            _DarkTopBar(
              title: space.name,
              subtitle: '第 $nextNumber 个点位 · 24 方向采集',
              onBack: _requestExit,
              trailing: _PointCounter(count: space.points.length),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xF216181D),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: SpaceColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          space.points.isEmpty ? '开始建立空间' : '继续采集',
                          style: const TextStyle(
                            color: Color(0xFFFFB6A5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${PanoConstants.vrCapturePointCount} 方向 / 点位',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '站到点位中央',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '保持手机竖直、机位不动，以身体带动手机缓慢转动。系统会引导 24 个方向，稳定后自动锁定拍摄并合成 4K 全景。',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  if (space.points.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          size: 15,
                          color: Colors.white38,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '从上一个点位移动约 2–3 米，并让手机朝向与前进方向一致，空间示意会更连贯。',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _StatusRow(
                    icon: Icons.videocam_rounded,
                    label: pano.cameraReady ? '后置摄像头已就绪' : '摄像头未就绪',
                    tone: pano.cameraReady
                        ? _StatusTone.ok
                        : _StatusTone.warn,
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    icon: Icons.explore_rounded,
                    label: hasHeading
                        ? (reliable
                            ? '指南针已锚定 · 方位示意可用'
                            : '指南针信号受干扰 · 方位仅供参考')
                        : '正在读取指南针…',
                    tone: reliable
                        ? _StatusTone.ok
                        : hasHeading
                            ? _StatusTone.warn
                            : _StatusTone.muted,
                  ),
                  if (pano.cameraError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x33FF5A3C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x55FF5A3C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pano.cameraError!,
                            style: const TextStyle(
                              color: Color(0xFFFFC1B5),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _SmallDarkButton(
                                icon: Icons.refresh_rounded,
                                label: '重新初始化',
                                onTap: () => ref
                                    .read(panoSessionProvider.notifier)
                                    .initCamera(),
                              ),
                              _SmallDarkButton(
                                icon: Icons.settings_rounded,
                                label: '打开系统设置',
                                onTap: _openSettings,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: SpaceColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 54),
                      ),
                      onPressed: canStart ? _beginCapture : null,
                      icon: _starting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 19),
                      label: Text(
                        !pano.cameraReady
                            ? '等待摄像头'
                            : !hasHeading
                                ? '等待指南针'
                                : '开始采集 24 方向',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: _showTips,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('拍摄技巧 / 方位说明'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '采集仅在本机处理 · 不上传云端',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 10.5,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureLayer(VrSpace space, PanoSessionState pano) {
    final total = pano.points.length;
    final captured = pano.capturedCount;
    final rollWarn = pano.roll.abs() > PanoConstants.rollWarnDeg;
    final locked = pano.lockedTargetId;
    final guide = rollWarn
        ? '手机倾斜 ${pano.roll.abs().toStringAsFixed(0)}° · 请保持竖直'
        : locked != null
            ? '已锁定 $locked · 保持稳定'
            : pano.nearestGuideText ??
                (captured >= total
                    ? '全部方向已采集，点击完成'
                    : '保持机位不动 · 对准圆点后自动拍摄');

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ArTargetsOverlay(
            points: pano.points,
            yaw: pano.yaw,
            pitch: pano.pitch,
            fov: pano.fov,
            lockedId: pano.lockedTargetId,
          ),
        ),
        CenterReticle(
          roll: pano.roll,
          lockProgress: pano.lockProgress,
          statusText: captured >= total ? '采集完成' : '对准目标',
          warn: rollWarn,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Column(
              children: [
                _DarkTopBar(
                  title: space.name,
                  subtitle: '第 ${space.points.length + 1} 个点位',
                  onBack: _requestExit,
                  trailing: _PointCounter(count: space.points.length),
                ),
                const SizedBox(height: 8),
                _VrProgressCard(pano: pano),
                const Spacer(),
                _GuidePill(
                  text: guide,
                  tone: rollWarn
                      ? _StatusTone.warn
                      : locked != null
                          ? _StatusTone.ok
                          : _StatusTone.muted,
                ),
                const SizedBox(height: 12),
                _CaptureControls(
                  pano: pano,
                  onReset: _resetCapture,
                  onShutter: () =>
                      ref.read(panoSessionProvider.notifier).handleShutter(),
                  onFinish: _finishCapture,
                  onToggleAutoLock: () =>
                      ref.read(panoSessionProvider.notifier).toggleAutoLock(),
                  onToggleGyro: () =>
                      ref.read(panoSessionProvider.notifier).toggleGyro(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewLayer(VrSpace space, PanoSessionState pano) {
    final total = pano.points.length;
    final captured = pano.capturedCount;
    final partial = captured < total;

    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xB3000000), Colors.transparent, Color(0x55000000)],
                stops: [0, 0.28, 0.62],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Column(
              children: [
                _DarkTopBar(
                  title: '点位拍摄完成',
                  subtitle: '拖动查看全景 · 双指缩放',
                  onBack: _requestExit,
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: partial
                          ? const Color(0x33F79009)
                          : const Color(0x3312B76A),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: partial
                            ? const Color(0x66F79009)
                            : const Color(0x6612B76A),
                      ),
                    ),
                    child: Text(
                      '$captured/$total 方向',
                      style: TextStyle(
                        color: partial
                            ? const Color(0xFFFFD699)
                            : const Color(0xFF89E6B7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  partial ? '部分方向未覆盖，边缘可能有拉伸' : '拖动检查拼接效果',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ReviewPanel(
            space: space,
            heading: _captureHeading,
            headingReliable: _captureHeadingReliable,
            captured: captured,
            total: total,
            nameController: _nameController,
            busy: _busy,
            onNameSelected: (value) {
              _nameController.text = value;
              setState(() {});
            },
            onRetake: _retake,
            onSave: _savePoint,
          ),
        ),
      ],
    );
  }

  Widget _buildSavedLayer(VrSpace space) {
    final savedName = _nameController.text.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: ColoredBox(color: Color(0x99000000)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              children: [
                _DarkTopBar(
                  title: space.name,
                  subtitle: '空间采集',
                  onBack: _popNow,
                  trailing: _PointCounter(count: space.points.length),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: SpaceColors.surface,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 36,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: SpaceColors.successSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: SpaceColors.success,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '点位已加入空间',
                        style: TextStyle(
                          color: SpaceColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$savedName · 当前空间共 ${space.points.length} 个点位',
                        style: const TextStyle(
                          color: SpaceColors.inkSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SpaceColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.directions_walk_rounded,
                              size: 18,
                              color: SpaceColors.inkMuted,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '继续移动到下一个位置（约 2–3 米），保持手机朝向与前进方向一致，再开始采集。',
                                style: TextStyle(
                                  color: SpaceColors.inkSecondary,
                                  fontSize: 12,
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: SpaceColors.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: _startNextPoint,
                          icon: const Icon(
                            Icons.add_a_photo_rounded,
                            size: 18,
                          ),
                          label: const Text('继续拍摄下一点位'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _popNow,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('完成采集，返回空间'),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Center(
                        child: TextButton.icon(
                          onPressed: _lastSavedPointId == null
                              ? null
                              : () => context.push(
                                    SpaceRoutes.tour(
                                      widget.spaceId,
                                      pointId: _lastSavedPointId,
                                    ),
                                  ),
                          icon: const Icon(
                            Icons.panorama_photosphere_rounded,
                            size: 16,
                          ),
                          label: const Text('预览当前 VR 漫游'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _beginCapture() async {
    if (_starting) return;
    final pano = ref.read(panoSessionProvider);
    final space = ref.read(spacesProvider).byId(widget.spaceId);
    if (space == null) {
      _showSnack('空间不存在或已被删除');
      return;
    }
    if (!pano.cameraReady) {
      _showSnack('摄像头尚未就绪，请稍后重试');
      return;
    }
    var heading = sanitizeHeading(_heading.headingDeg);
    if (heading == null) {
      setState(() => _starting = true);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      heading = sanitizeHeading(_heading.headingDeg);
    }
    if (!mounted) return;
    if (heading == null) {
      setState(() => _starting = false);
      _showSnack('未读取到指南针数据，请先校准手机指南针后重试');
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      _nameController.text = _suggestName(space);
    }
    final reliable = _heading.isReliable;
    final ok = ref.read(panoSessionProvider.notifier).startVrCapture(
          compassHeadingDeg: heading,
        );
    if (!mounted) return;
    setState(() {
      _starting = false;
      if (ok) {
        _phase = _CapturePhase.capturing;
        _captureHeading = heading;
        _captureHeadingReliable = reliable;
        _autoFinishTriggered = false;
      }
    });
    if (!ok) {
      _showSnack('无法启动采集，请检查摄像头状态');
    }
  }

  Future<void> _resetCapture() async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: '重新采集本点位',
      content: '将清空本次已拍摄的方向，从当前朝向重新开始。',
      confirmLabel: '重新开始',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final heading = sanitizeHeading(_heading.headingDeg);
    if (heading == null) {
      _showSnack('未读取到指南针数据，无法重新对齐方向');
      return;
    }
    final ok = ref.read(panoSessionProvider.notifier).startVrCapture(
          compassHeadingDeg: heading,
        );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _captureHeading = heading;
        _captureHeadingReliable = _heading.isReliable;
        _autoFinishTriggered = false;
      });
    }
  }

  Future<void> _finishCapture() async {
    if (_busy ||
        _phase != _CapturePhase.capturing ||
        ref.read(panoSessionProvider).isStitching) {
      return;
    }
    final pano = ref.read(panoSessionProvider);
    final space = ref.read(spacesProvider).byId(widget.spaceId);
    if (space == null) return;
    final captured = pano.capturedCount;
    if (captured == 0) {
      _showSnack('请先拍摄至少一个方向');
      return;
    }
    if (captured < pano.points.length) {
      final go = await _confirm(
        title: '还有 ${pano.points.length - captured} 个方向未拍摄',
        content: '未覆盖区域会使用已有画面近似填充，可能出现拉伸。可以继续补拍，或直接合成。',
        confirmLabel: '仍然合成',
        cancelLabel: '继续补拍',
      );
      if (go != true || !mounted) return;
    }
    setState(() => _phase = _CapturePhase.stitching);
    final titleName = _nameController.text.trim().isEmpty
        ? '点位 ${space.points.length + 1}'
        : _nameController.text.trim();
    final work = await ref
        .read(panoSessionProvider.notifier)
        .completeStitching(titlePrefix: '${space.name} · $titleName');
    if (!mounted) return;
    if (work != null) {
      setState(() {
        _phase = _CapturePhase.review;
      });
    } else {
      setState(() => _phase = _CapturePhase.capturing);
      _showSnack('拼接失败，请重试或重新采集');
    }
  }

  Future<void> _retake() async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: '重拍这个点位',
      content: '当前已合成的全景会从作品库删除，然后重新开始 24 方向采集。',
      confirmLabel: '重拍',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final notifier = ref.read(panoSessionProvider.notifier);
    final work = ref.read(panoSessionProvider).activeWork;
    if (work != null) {
      await notifier.discardWork(work.id);
    }
    if (!mounted) return;
    final heading = sanitizeHeading(_heading.headingDeg);
    if (heading == null) {
      _showSnack('未读取到指南针数据，无法重新对齐方向');
      return;
    }
    final ok = notifier.startVrCapture(compassHeadingDeg: heading);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _phase = _CapturePhase.capturing;
        _captureHeading = heading;
        _captureHeadingReliable = _heading.isReliable;
        _autoFinishTriggered = false;
      });
    }
  }

  Future<void> _savePoint() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('请先填写点位名称');
      return;
    }
    final work = ref.read(panoSessionProvider).activeWork;
    if (work == null) {
      _showSnack('未找到已合成的全景，请重拍');
      return;
    }
    setState(() => _busy = true);
    try {
      final point = await ref
          .read(spacesProvider.notifier)
          .addPointFromWork(
            spaceId: widget.spaceId,
            work: work,
            name: name,
            headingDeg: _captureHeading,
          );
      if (!mounted) return;
      ref.read(panoSessionProvider.notifier).setMode(AppMode.capture);
      setState(() {
        _busy = false;
        _phase = _CapturePhase.saved;
        _lastSavedPointId = point.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('保存点位失败：$e');
    }
  }

  void _startNextPoint() {
    final space = ref.read(spacesProvider).byId(widget.spaceId);
    if (space == null) return;
    _nameController.text = _suggestName(space);
    _lastSavedPointId = null;
    _autoFinishTriggered = false;
    setState(() => _phase = _CapturePhase.ready);
  }

  Future<void> _requestExit() async {
    if (_busy || _phase == _CapturePhase.stitching) {
      _showSnack('正在处理，请稍候');
      return;
    }
    final pano = ref.read(panoSessionProvider);
    String? message;
    String confirmLabel = '退出';
    if (_phase == _CapturePhase.capturing) {
      if (pano.capturedCount > 0) {
        message = '本次已拍摄 ${pano.capturedCount}/${pano.points.length} 个方向，'
            '退出后不会保存，需要重新采集。';
      }
    } else if (_phase == _CapturePhase.review) {
      message = '全景已合成但尚未加入空间。退出后仍会保留在作品库，'
          '可在“添加点位 → 从作品库选择”中重新加入。';
    }
    if (message != null) {
      final ok = await _confirm(
        title: '退出当前采集？',
        content: message,
        confirmLabel: confirmLabel,
        destructive: true,
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _popNow();
  }

  void _popNow() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(SpaceRoutes.detail(widget.spaceId));
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
    String cancelLabel = '取消',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: SpaceColors.accent)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showTips() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拍摄技巧 / 方位说明'),
        content: const SingleChildScrollView(
          child: Text(
            '· 站在点位中央，保持手机竖直，原地转动一周。\n'
            '· 上仰或下俯时尽量缓慢，避免快速甩动导致画面模糊。\n'
            '· 室内光线不足时先开灯，拼接效果更稳定。\n'
            '· 点位方位由手机指南针估算，仅用于示意与前后点位漫游；'
            '不是测绘级定位，也不会上传到云端。\n'
            '· 指南针受干扰时，方位可能存在偏差，点位仍可通过底部列表浏览。',
            style: TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _suggestName(VrSpace space) {
    final used = space.points.map((e) => e.name.trim()).toSet();
    final candidates = _roomCandidates(space.category);
    for (final name in candidates) {
      if (!used.contains(name)) return name;
    }
    var index = space.points.length + 1;
    var candidate = '点位 $index';
    while (used.contains(candidate)) {
      index++;
      candidate = '点位 $index';
    }
    return candidate;
  }

  List<String> _roomCandidates(SpaceCategory category) {
    return switch (category) {
      SpaceCategory.residence || SpaceCategory.apartment => const [
          '客厅',
          '主卧',
          '次卧',
          '厨房',
          '卫生间',
          '阳台',
          '餐厅',
          '书房',
          '玄关',
          '走廊',
          '储物间',
          '衣帽间',
        ],
      SpaceCategory.shop => const [
          '入口',
          '主展示区',
          '接待区',
          '收银台',
          '通道',
          '体验区',
          '后场',
        ],
      SpaceCategory.office => const [
          '前台',
          '开放办公区',
          '会议室',
          '经理室',
          '茶水间',
          '走廊',
        ],
      SpaceCategory.exhibition => const [
          '入口',
          '展区 A',
          '展区 B',
          '中央展区',
          '互动区',
          '出口',
        ],
      SpaceCategory.other => const [],
    };
  }
}

enum _StatusTone { ok, warn, muted }

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.ok => const Color(0xFF6EE7B7),
      _StatusTone.warn => const Color(0xFFFFC98A),
      _StatusTone.muted => Colors.white38,
    };
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _GuidePill extends StatelessWidget {
  const _GuidePill({required this.text, required this.tone});

  final String text;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.ok => const Color(0xFF6EE7B7),
      _StatusTone.warn => const Color(0xFFFFC98A),
      _StatusTone.muted => Colors.white70,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DarkTopBar extends StatelessWidget {
  const _DarkTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.close_rounded, color: Colors.white, size: 21),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _PointCounter extends StatelessWidget {
  const _PointCounter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.pin_drop_rounded,
            size: 12,
            color: Colors.white54,
          ),
          const SizedBox(width: 5),
          Text(
            '$count 点位',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _VrProgressCard extends StatelessWidget {
  const _VrProgressCard({required this.pano});

  final PanoSessionState pano;

  @override
  Widget build(BuildContext context) {
    final total = pano.points.length;
    final progress = total == 0 ? 0.0 : pano.capturedCount / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _RingStat(
                color: const Color(0xFF7CC4FF),
                label: '仰拍',
                value: '${pano.upperCount}/${_ringSize(total, 0)}',
              ),
              const SizedBox(width: 12),
              _RingStat(
                color: SpaceColors.accent,
                label: '水平',
                value: '${pano.midCount}/${_ringSize(total, 1)}',
              ),
              const SizedBox(width: 12),
              _RingStat(
                color: const Color(0xFF6EE7B7),
                label: '俯拍',
                value: '${pano.lowerCount}/${_ringSize(total, 2)}',
              ),
              const Spacer(),
              Text(
                '${pano.capturedCount}/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(SpaceColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  int _ringSize(int total, int index) {
    if (total == 0) return 0;
    final perRing = total ~/ 3;
    if (total % 3 == 0) return perRing;
    return index == 0 ? total - perRing * 2 : perRing;
  }
}

class _RingStat extends StatelessWidget {
  const _RingStat({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.pano,
    required this.onReset,
    required this.onShutter,
    required this.onFinish,
    required this.onToggleAutoLock,
    required this.onToggleGyro,
  });

  final PanoSessionState pano;
  final VoidCallback onReset;
  final VoidCallback onShutter;
  final VoidCallback onFinish;
  final VoidCallback onToggleAutoLock;
  final VoidCallback onToggleGyro;

  @override
  Widget build(BuildContext context) {
    final total = pano.points.length;
    final ratio = total == 0 ? 0.0 : pano.capturedCount / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ToggleChip(
                icon: Icons.auto_awesome_rounded,
                label: '自动拍摄',
                value: pano.autoLockEnabled ? '开' : '关',
                active: pano.autoLockEnabled,
                onTap: onToggleAutoLock,
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                icon: Icons.screen_rotation_rounded,
                label: pano.gyroEnabled ? '陀螺仪' : '拖拽',
                value: pano.gyroEnabled ? '开' : '关',
                active: pano.gyroEnabled,
                onTap: onToggleGyro,
              ),
              const Spacer(),
              Text(
                pano.capturedCount == 0
                    ? '缓慢转动开始'
                    : '已拍 ${pano.capturedCount}/$total',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RoundAction(
                  icon: Icons.refresh_rounded,
                  label: '重置',
                  onTap: onReset,
                ),
              ),
              _ShutterButton(progress: ratio, onTap: onShutter),
              Expanded(
                child: _RoundAction(
                  icon: Icons.check_rounded,
                  label: '完成',
                  accent: true,
                  enabled: pano.capturedCount > 0,
                  onTap: onFinish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? SpaceColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active
                ? SpaceColors.accent.withValues(alpha: 0.55)
                : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? const Color(0xFFFFB6A5) : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              '$label $value',
              style: TextStyle(
                color: active ? const Color(0xFFFFD3C9) : Colors.white54,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && accent;
    return Column(
      children: [
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active
                  ? SpaceColors.accent
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: enabled
                  ? (active ? Colors.white : Colors.white70)
                  : Colors.white24,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white54 : Colors.white24,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.progress, required this.onTap});

  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 78,
        height: 78,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation(SpaceColors.accent),
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Color(0xFF16181D),
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.space,
    required this.heading,
    required this.headingReliable,
    required this.captured,
    required this.total,
    required this.nameController,
    required this.busy,
    required this.onNameSelected,
    required this.onRetake,
    required this.onSave,
  });

  final VrSpace space;
  final double? heading;
  final bool headingReliable;
  final int captured;
  final int total;
  final TextEditingController nameController;
  final bool busy;
  final ValueChanged<String> onNameSelected;
  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 32,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: SpaceColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: SpaceColors.successSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: SpaceColors.success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '全景已合成',
                        style: TextStyle(
                          color: SpaceColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        captured >= total
                            ? '24 方向完整覆盖 · 4K 等距全景'
                            : '$captured/$total 方向 · 边缘可能有拉伸',
                        style: const TextStyle(
                          color: SpaceColors.inkMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: SpaceColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${space.points.length + 1} 号点位',
                    style: const TextStyle(
                      color: SpaceColors.inkSecondary,
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '点位名称',
              style: TextStyle(
                color: SpaceColors.inkSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                color: SpaceColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: '例如：客厅、主卧、前台',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _roomPresets(space.category))
                  _RoomChip(
                    label: name,
                    onTap: () => onNameSelected(name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _HeadingNotice(
              heading: heading,
              reliable: headingReliable,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRetake,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('重拍'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SpaceColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                    ),
                    onPressed: busy ? null : onSave,
                    icon: busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(busy ? '保存中…' : '保存到空间'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _roomPresets(SpaceCategory category) {
    return switch (category) {
      SpaceCategory.residence || SpaceCategory.apartment => const [
          '客厅',
          '主卧',
          '次卧',
          '厨房',
          '卫生间',
          '阳台',
        ],
      SpaceCategory.shop => const ['入口', '主展示区', '接待区', '收银台'],
      SpaceCategory.office => const ['前台', '开放办公区', '会议室', '茶水间'],
      SpaceCategory.exhibition => const ['入口', '展区 A', '展区 B', '互动区'],
      SpaceCategory.other => const ['入口', '中心', '出口'],
    };
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: SpaceColors.surfaceAlt,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: SpaceColors.line),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: SpaceColors.inkSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _HeadingNotice extends StatelessWidget {
  const _HeadingNotice({required this.heading, required this.reliable});

  final double? heading;
  final bool reliable;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color background;
    final Color foreground;
    final IconData icon;
    if (heading == null) {
      text = '未获取到指南针方位：本点位不会生成前后方位热点，但仍可通过点位列表与示意图浏览。';
      background = const Color(0xFFFFF4E5);
      foreground = const Color(0xFF9A5B00);
      icon = Icons.explore_off_rounded;
    } else if (!reliable) {
      text = '指南针受到干扰，方位仅为估算示意（${heading!.round()}°），可能存在偏差。';
      background = const Color(0xFFFFF4E5);
      foreground = const Color(0xFF9A5B00);
      icon = Icons.warning_amber_rounded;
    } else {
      text = '指南针方位已记录（${heading!.round()}°，${_compassName(heading!)}）'
          '，用于前后点位方向示意，非测绘级定位。';
      background = SpaceColors.successSoft;
      foreground = const Color(0xFF0B7A4B);
      icon = Icons.explore_rounded;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontSize: 10.8,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _compassName(double value) {
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final index = ((normalizeDeg360(value) + 22.5) ~/ 45) % 8;
    return names[index];
  }
}

class _StitchingOverlay extends StatelessWidget {
  const _StitchingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xF209090B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: SpaceColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '正在拼接 24 方向全景',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '本机处理 · 请保持应用在前台',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoToast extends StatefulWidget {
  const _AutoToast({
    super.key,
    required this.message,
    required this.onExpired,
  });

  final String message;
  final VoidCallback onExpired;

  @override
  State<_AutoToast> createState() => _AutoToastState();
}

class _AutoToastState extends State<_AutoToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _AutoToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) widget.onExpired();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.paddingOf(context).top + 68,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallDarkButton extends StatelessWidget {
  const _SmallDarkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingSpace extends StatelessWidget {
  const _MissingSpace({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.panorama_photosphere_rounded,
          size: 44,
          color: SpaceColors.inkMuted,
        ),
        const SizedBox(height: 12),
        const Text(
          '空间不存在或已被删除',
          style: TextStyle(
            color: SpaceColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onBack, child: const Text('返回空间列表')),
      ],
    );
  }
}