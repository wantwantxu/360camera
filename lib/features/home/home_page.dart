import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/pano_colors.dart';
import '../../core/utils/angle_utils.dart';
import '../../domain/app_enums.dart';
import '../capture/widgets/capture_hud.dart';
import '../export/export_sheet.dart';
import '../gallery/gallery_sheet.dart';
import '../preview/color_filters.dart';
import '../preview/pano_sphere_view.dart';
import '../session/pano_session.dart';
import '../../widgets/glass.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panoSessionProvider);
    final notifier = ref.read(panoSessionProvider.notifier);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Viewport(state: state, notifier: notifier),
          if (state.mode == AppMode.capture) _CaptureOverlays(state: state, notifier: notifier),
          if (state.mode == AppMode.preview) _PreviewOverlays(state: state, notifier: notifier),
          _TopHeader(state: state, notifier: notifier),
          _BottomDock(state: state, notifier: notifier),
          if (state.flash)
            const IgnorePointer(
              child: ColoredBox(color: Color(0xCCFFFFFF)),
            ),
          if (state.isStitching) const _StitchingOverlay(),
          if (state.toast != null) _Toast(message: state.toast!),
        ],
      ),
    );
  }
}

class _Viewport extends StatelessWidget {
  const _Viewport({required this.state, required this.notifier});
  final PanoSessionState state;
  final PanoSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.mode == AppMode.capture &&
        state.source == CaptureSource.camera &&
        state.cameraReady &&
        notifier.cameraController != null) {
      return GestureDetector(
        onPanStart: (_) => notifier.beginDrag(),
        onPanUpdate: (d) {
          if (!state.gyroEnabled) {
            notifier.nudgeAttitude(
              dYaw: -d.delta.dx * 0.18,
              dPitch: d.delta.dy * 0.14,
            );
          }
        },
        onPanEnd: (_) => notifier.endDrag(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(notifier.cameraController!),
            // Dim edges for HUD readability
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x9909090B), Colors.transparent, Color(0x9909090B)],
                  stops: [0, 0.35, 1],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.mode == AppMode.capture) {
      // Procedural / no-camera capture: dark stage + drag gimbal.
      return GestureDetector(
        onPanStart: (_) => notifier.beginDrag(),
        onPanUpdate: (d) {
          if (!state.gyroEnabled) {
            notifier.nudgeAttitude(
              dYaw: -d.delta.dx * 0.18,
              dPitch: d.delta.dy * 0.14,
            );
          }
        },
        onPanEnd: (_) => notifier.endDrag(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B1220), Color(0xFF09090B), Color(0xFF101820)],
            ),
          ),
          child: Center(
            child: Text(
              state.cameraError ?? '演示源 · ${state.source.label}\n拖拽或开启陀螺仪对准点位',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PanoColors.textSecondary, height: 1.5),
            ),
          ),
        ),
      );
    }

    return PanoSphereView(
      imageBytes: state.previewBytes,
      lon: state.yaw,
      lat: state.pitch,
      fov: state.fov,
      view: state.projectionView,
      colorFilter: flutterColorFilter(state.filter),
      interactive: true,
      onDragStart: notifier.beginDrag,
      onDragEnd: notifier.endDrag,
      onAttitudeChanged: (delta) => notifier.nudgeAttitude(
        dYaw: delta.dx,
        dPitch: delta.dy,
      ),
      onFovChanged: notifier.setFov,
    );
  }
}

class _TopHeader extends ConsumerWidget {
  const _TopHeader({required this.state, required this.notifier});
  final PanoSessionState state;
  final PanoSessionNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              GlassPill(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: PanoColors.amber,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: PanoColors.amber.withValues(alpha: 0.8),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      PanoConstants.brandName,
                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                    const Text(
                      ' ${PanoConstants.brandAccent}',
                      style: TextStyle(
                        color: PanoColors.amber,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GlassPill(
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _ModeTab(
                      label: '拍摄拼接',
                      active: state.mode == AppMode.capture,
                      onTap: () => notifier.setMode(AppMode.capture),
                    ),
                    _ModeTab(
                      label: '全景预览',
                      active: state.mode == AppMode.preview,
                      onTap: () => notifier.setMode(AppMode.preview),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Flexible(
                child: GlassPill(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      children: [
                        _telem('Y', formatYawDeg(state.yaw), PanoColors.amber),
                        _sep(),
                        _telem('P', formatSignedDeg(state.pitch), PanoColors.cyan),
                        _sep(),
                        _telem('R', formatSignedDeg(state.roll), PanoColors.emerald),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GlassPill(
                onTap: () => notifier.importLocalImage(),
                child: const Icon(Icons.upload_file, size: 16),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => openExportSheet(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: PanoColors.amber,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: PanoColors.amber.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    '导出',
                    style: TextStyle(
                      color: PanoColors.bgBase,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _telem(String k, String v, Color c) {
    return Row(
      children: [
        Text(k, style: const TextStyle(color: PanoColors.textMuted, fontSize: 10, fontFamily: 'monospace')),
        const SizedBox(width: 3),
        Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 10, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('|', style: TextStyle(color: Colors.white24, fontSize: 10)),
      );
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? PanoColors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? PanoColors.bgBase : PanoColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CaptureOverlays extends StatelessWidget {
  const _CaptureOverlays({required this.state, required this.notifier});
  final PanoSessionState state;
  final PanoSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final rollWarn = state.roll.abs() > PanoConstants.rollWarnDeg;
    final status = rollWarn
        ? '请保持水平'
        : state.lockedTargetId != null
            ? '锁定 ${state.lockedTargetId}'
            : '寻找点位';

    return Stack(
      children: [
        Positioned(
          top: MediaQuery.paddingOf(context).top + 64,
          left: 12,
          right: 12,
          child: Column(
            children: [
              CaptureProgressCard(
                upper: state.upperCount,
                mid: state.midCount,
                lower: state.lowerCount,
                total: state.capturedCount,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  GlassPill(
                    onTap: notifier.toggleGyro,
                    borderColor: PanoColors.cyan.withValues(alpha: 0.38),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.gyroEnabled ? PanoColors.emerald : PanoColors.textMuted,
                            boxShadow: state.gyroEnabled
                                ? [BoxShadow(color: PanoColors.emerald.withValues(alpha: 0.8), blurRadius: 8)]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.gyroEnabled ? '陀螺仪云台' : '虚拟云台',
                          style: const TextStyle(color: Color(0xFF67E8F9), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  GlassPill(
                    onTap: notifier.toggleAutoLock,
                    color: state.autoLockEnabled ? PanoColors.amberDim : PanoColors.bgPill,
                    borderColor: state.autoLockEnabled
                        ? PanoColors.amber.withValues(alpha: 0.42)
                        : PanoColors.borderSubtle,
                    child: Text(
                      state.autoLockEnabled ? '自动对准连拍: 开' : '自动对准连拍: 关',
                      style: TextStyle(
                        color: state.autoLockEnabled ? const Color(0xFFFCD34D) : PanoColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: ArTargetsOverlay(
            points: state.points,
            yaw: state.yaw,
            pitch: state.pitch,
            fov: state.fov,
            lockedId: state.lockedTargetId,
          ),
        ),
        CenterReticle(
          roll: state.roll,
          lockProgress: state.lockProgress,
          statusText: status,
          warn: rollWarn,
        ),
        if (state.nearestGuideText != null)
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.28,
            left: 0,
            right: 0,
            child: Center(
              child: GlassPill(
                borderColor: PanoColors.amber.withValues(alpha: 0.55),
                color: const Color(0xDB09090B),
                child: Text(
                  state.nearestGuideText!,
                  style: const TextStyle(
                    color: Color(0xFFFCD34D),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 150,
          child: MiniRadar(
            points: state.points,
            yaw: state.yaw,
            onTap: notifier.slewToNearest,
            onReset: notifier.resetCapture,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 118,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final src in CaptureSource.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GlassPill(
                      onTap: () => notifier.setSource(src),
                      color: state.source == src ? PanoColors.amberDim : PanoColors.bgPill,
                      borderColor: state.source == src ? PanoColors.amber : PanoColors.borderSubtle,
                      child: Text(
                        src.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: state.source == src ? PanoColors.amber : PanoColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                GlassPill(
                  onTap: () => notifier.instantFullStitch(),
                  color: PanoColors.cyanDim,
                  borderColor: PanoColors.cyan.withValues(alpha: 0.4),
                  child: const Text(
                    '一键完成全部点位',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PanoColors.cyan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewOverlays extends StatelessWidget {
  const _PreviewOverlays({required this.state, required this.notifier});
  final PanoSessionState state;
  final PanoSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: MediaQuery.paddingOf(context).top + 64,
          left: 12,
          right: 12,
          child: GlassPill(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tool(
                    '标准视角',
                    state.projectionView == ProjectionView.normal,
                    () => notifier.setProjectionView(ProjectionView.normal),
                  ),
                  _tool(
                    '小行星',
                    state.projectionView == ProjectionView.planet,
                    () => notifier.setProjectionView(ProjectionView.planet),
                  ),
                  _tool('自动巡航', state.autoRotate, notifier.toggleAutoRotate),
                  _tool('体感环顾', state.previewGyroEnabled, notifier.togglePreviewGyro),
                  const SizedBox(width: 8),
                  Text(
                    'FOV ${state.fov.toStringAsFixed(0)}°',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: PanoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 118,
          child: GlassPill(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in ColorFilterId.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => notifier.setFilter(f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: state.filter == f ? PanoColors.amber : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            f.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: state.filter == f ? PanoColors.bgBase : PanoColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tool(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? PanoColors.amber : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? PanoColors.bgBase : PanoColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomDock extends ConsumerWidget {
  const _BottomDock({required this.state, required this.notifier});
  final PanoSessionState state;
  final PanoSessionNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = state.gallery.isNotEmpty ? state.gallery.first.thumbPath : null;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => openGallerySheet(context, ref),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PanoColors.borderStrong),
                        color: PanoColors.bgCard,
                        image: thumb != null
                            ? DecorationImage(
                                image: FileImage(File(thumb)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: thumb == null
                          ? const Icon(Icons.photo_library_outlined, color: PanoColors.textSecondary)
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: PanoColors.amber,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${state.gallery.length}',
                          style: const TextStyle(
                            color: PanoColors.bgBase,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => notifier.handleShutter(),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 3),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.mode == AppMode.capture ? Colors.white : PanoColors.amber,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.mode == AppMode.capture
                        ? '捕捉点位 (${state.capturedCount}/14)'
                        : '返回拍摄',
                    style: const TextStyle(fontSize: 11, color: PanoColors.textSecondary),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (state.mode == AppMode.capture) {
                    notifier.completeStitching();
                  } else {
                    openExportSheet(context, ref);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: PanoColors.amber,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: PanoColors.amber.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    state.mode == AppMode.capture ? '合成预览' : '导出分享',
                    style: const TextStyle(
                      color: PanoColors.bgBase,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StitchingOverlay extends StatelessWidget {
  const _StitchingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xCC09090B),
      child: Center(
        child: GlassPanel(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(color: PanoColors.amber, strokeWidth: 3),
              ),
              SizedBox(height: 14),
              Text(
                '正在合成 360° 全景…',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 120,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: Center(
          child: GlassPill(
            color: const Color(0xE009090B),
            borderColor: PanoColors.amber.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
