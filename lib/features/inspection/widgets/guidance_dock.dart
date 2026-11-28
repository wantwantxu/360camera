import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants.dart';
import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/compass_utils.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../domain/app_enums.dart';
import '../../../domain/inspection_point.dart';
import '../../../widgets/glass.dart';
import '../../gallery/gallery_sheet.dart';
import '../../session/pano_session.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';
import 'waypoint_brief_sheet.dart';
import 'waypoint_editor_sheet.dart';

class GuidanceDock extends ConsumerWidget {
  const GuidanceDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspection = ref.watch(inspectionProvider);
    final pano = ref.watch(panoSessionProvider);
    final point = inspection.activePoint;
    if (point == null || !inspection.stage.isGuidance) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(inspectionProvider.notifier);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: GlassPanel(
            borderRadius: 18,
            opacity: 0.9,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hintRow(context, ref, inspection, point, notifier),
                if (pano.source != CaptureSource.camera || !pano.cameraReady) ...[
                  const SizedBox(height: 6),
                  _cameraRow(context, ref, pano),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _DockAction(
                        icon: point.hasCoordinates
                            ? Icons.my_location
                            : Icons.add_location_alt_outlined,
                        label: point.hasCoordinates ? '重新定位' : '设置坐标',
                        onTap: () {
                          if (!point.hasCoordinates) {
                            openWaypointEditorSheet(context, ref, point: point);
                          } else {
                            notifier.refreshLocation();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DockAction(
                        icon: Icons.compare,
                        label: '参考照片',
                        onTap: () {
                          if (point.referenceImagePath == null) {
                            openWaypointBriefSheet(context, ref);
                          } else {
                            notifier.openReferenceOverlay(ReferenceCompareMode.ghost);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DockAction(
                        icon: Icons.info_outline,
                        label: '点位详情',
                        onTap: () => openWaypointBriefSheet(context, ref),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _DockAction(
                        icon: Icons.photo_library_outlined,
                        label: '拍摄结果',
                        onTap: () => openGallerySheet(context, ref),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                _primaryButton(context, ref, inspection, point, notifier),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintRow(
    BuildContext context,
    WidgetRef ref,
    InspectionState inspection,
    InspectionPoint point,
    InspectionController notifier,
  ) {
    final (text, color) = _hintText(inspection, point);
    Widget? action;
    if (inspection.gpsStatus == LocationUiStatus.serviceDisabled) {
      action = _link(
        '打开定位',
        () => Geolocator.openLocationSettings(),
      );
    } else if (inspection.gpsStatus == LocationUiStatus.permissionDeniedForever) {
      action = _link('去设置', () => Geolocator.openAppSettings());
    } else if (inspection.gpsStatus == LocationUiStatus.permissionDenied ||
        inspection.gpsStatus == LocationUiStatus.error) {
      action = _link('重试定位', () => notifier.refreshLocation());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 7)],
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?action,
      ],
    );
  }

  (String, Color) _hintText(InspectionState inspection, InspectionPoint point) {
    switch (inspection.stage) {
      case InspectionStage.briefing:
        return ('核对点位信息与参考照片，准备前往拍摄位置', PanoColors.textSecondary);
      case InspectionStage.positioning:
        if (!point.hasCoordinates) {
          return ('该点位未设坐标，请按现场说明确认位置', PanoColors.amber);
        }
        if (inspection.gpsStatus == LocationUiStatus.locating) {
          return ('正在获取卫星定位，请稍候…', PanoColors.cyan);
        }
        if (inspection.gpsStatus == LocationUiStatus.serviceDisabled) {
          return ('系统定位未开启，无法计算与点位的距离', PanoColors.rose);
        }
        if (inspection.gpsStatus == LocationUiStatus.permissionDenied ||
            inspection.gpsStatus == LocationUiStatus.permissionDeniedForever) {
          return ('定位权限未授予，可手动确认位置，但无法校验距离', PanoColors.rose);
        }
        if (inspection.gpsStatus == LocationUiStatus.error) {
          return (inspection.gpsError ?? '定位异常，请点击重新定位', PanoColors.rose);
        }
        if (inspection.distanceM == null) {
          return ('尚未获取当前位置，可手动确认位置或重新定位', PanoColors.textSecondary);
        }
        final acc = inspection.gpsAccuracyM;
        final accText = acc == null ? '' : ' · 精度 ±${acc.round()} m';
        if (inspection.withinArrivalRange) {
          return (
            '距离目标 ${formatDistance(inspection.distanceM)}$accText · 已进入到达范围',
            PanoColors.emerald,
          );
        }
        final radius = point.arrivalRadiusM.toStringAsFixed(0);
        return (
          '距离目标 ${formatDistance(inspection.distanceM)}$accText · 到达范围 $radius m',
          inspection.gpsAccuracyGood ? PanoColors.amber : PanoColors.rose,
        );
      case InspectionStage.aligning:
        if (!point.hasTargetAzimuth) {
          return ('该点位未设目标方向，可直接开始拍摄', PanoColors.emerald);
        }
        if (inspection.manualDirectionConfirmed) {
          return ('方向已手动确认（未经传感器校验）', PanoColors.amber);
        }
        if (inspection.compassInterfered) {
          return ('电子罗盘受干扰，无法提供可靠方向，可手动确认', PanoColors.rose);
        }
        if (!inspection.compassReliable || inspection.directionDeltaDeg == null) {
          return ('方向传感器不可用，可使用参考照片对齐后手动确认', PanoColors.amber);
        }
        final turn = describeTurn(
          inspection.directionDeltaDeg!,
          alignedThresholdDeg: PanoConstants.waypointAlignEnterDeg,
          nearThresholdDeg: PanoConstants.waypointAlignNearDeg,
        );
        return (
          '${turn.text} · 偏差 ${formatDelta(inspection.directionDeltaDeg!)}',
          turn.isAligned ? PanoColors.emerald : PanoColors.amber,
        );
      case InspectionStage.ready:
        if (inspection.manualDirectionConfirmed) {
          return ('位置与手动确认的方向已记录，可开始 360° 拍摄', PanoColors.amber);
        }
        return ('位置与目标方向均已确认，可开始 360° 拍摄', PanoColors.emerald);
      case InspectionStage.idle:
      case InspectionStage.panorama:
      case InspectionStage.review:
      case InspectionStage.taskComplete:
        return ('', PanoColors.textSecondary);
    }
  }

  Widget _cameraRow(BuildContext context, WidgetRef ref, PanoSessionState pano) {
    final panoNotifier = ref.read(panoSessionProvider.notifier);
    final message = pano.source != CaptureSource.camera
        ? (pano.cameraError ?? '当前为演示源，巡检拍摄需要真实摄像头')
        : '相机尚未就绪';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: PanoColors.rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PanoColors.rose.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.no_photography_outlined, size: 14, color: PanoColors.rose),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFDA4AF), fontSize: 10, height: 1.35),
            ),
          ),
          _link('重试相机', () => panoNotifier.initCamera()),
          _link('设置', () => openAppSettings()),
        ],
      ),
    );
  }

  Widget _primaryButton(
    BuildContext context,
    WidgetRef ref,
    InspectionState inspection,
    InspectionPoint point,
    InspectionController notifier,
  ) {
    switch (inspection.stage) {
      case InspectionStage.briefing:
        return _primary(
          label: '开始前往点位',
          icon: Icons.navigation_outlined,
          onTap: notifier.beginNavigation,
        );
      case InspectionStage.positioning:
        return _primary(
          label: point.hasCoordinates ? '确认拍摄位置' : '确认在此位置拍摄',
          icon: Icons.place_outlined,
          onTap: () => _confirmArrival(context, ref, inspection, point, notifier),
        );
      case InspectionStage.aligning:
        if (inspection.compassReliable && !inspection.manualDirectionConfirmed) {
          final delta = inspection.directionDeltaDeg;
          final label = delta == null
              ? '等待方向传感器…'
              : describeTurn(
                  delta,
                  alignedThresholdDeg: PanoConstants.waypointAlignEnterDeg,
                  nearThresholdDeg: PanoConstants.waypointAlignNearDeg,
                ).text;
          return _primary(
            label: label,
            icon: Icons.explore_outlined,
            onTap: null,
            disabledHint: '需先按上方罗盘/AR 标记对准目标方向',
          );
        }
        return _primary(
          label: '手动确认拍摄方向',
          icon: Icons.touch_app_outlined,
          onTap: () => _confirmManualDirection(context, notifier),
        );
      case InspectionStage.ready:
        return _primary(
          label: '开始 360° 拍摄',
          icon: Icons.camera_enhance_outlined,
          color: PanoColors.emerald,
          onTap: notifier.beginPanoramaCapture,
        );
      case InspectionStage.idle:
      case InspectionStage.panorama:
      case InspectionStage.review:
      case InspectionStage.taskComplete:
        return const SizedBox.shrink();
    }
  }

  Widget _primary({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color color = PanoColors.amber,
    String? disabledHint,
  }) {
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: PanoColors.bgBase,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: PanoColors.textMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (!enabled && disabledHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              disabledHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PanoColors.textMuted, fontSize: 9),
            ),
          ),
      ],
    );
  }

  Widget _link(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: PanoColors.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmArrival(
    BuildContext context,
    WidgetRef ref,
    InspectionState inspection,
    InspectionPoint point,
    InspectionController notifier,
  ) async {
    final reasons = <String>[];
    if (!point.hasCoordinates) {
      reasons.add('该点位未设置经纬度');
    } else if (inspection.latitude == null || inspection.longitude == null) {
      reasons.add('尚未获取当前位置');
    } else if (!inspection.gpsFixFresh) {
      reasons.add('定位数据已过期');
    } else if (!inspection.gpsAccuracyGood) {
      reasons.add(
        '定位精度 ±${inspection.gpsAccuracyM?.round() ?? '?'} m，未达到 ${PanoConstants.waypointMaxGpsAccuracyM.round()} m 要求',
      );
    } else if (inspection.distanceM == null) {
      reasons.add('无法计算与点位的距离');
    } else if (inspection.distanceM! > point.arrivalRadiusM) {
      reasons.add(
        '距离目标 ${formatDistance(inspection.distanceM)}，超出到达半径 ${point.arrivalRadiusM.round()} m',
      );
    }
    if (reasons.isEmpty) {
      notifier.confirmArrival();
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('无法自动校验拍摄位置'),
        content: Text(
          '${reasons.map((e) => '· $e').join('\n')}\n\n仍要在此位置开始拍摄吗？系统会将该点位位置标记为「人工确认」。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回调整'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '仍确认位置',
              style: TextStyle(color: PanoColors.amber),
            ),
          ),
        ],
      ),
    );
    if (ok == true) notifier.confirmArrival();
  }

  Future<void> _confirmManualDirection(
    BuildContext context,
    InspectionController notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('手动确认拍摄方向'),
        content: const Text(
          '设备未提供可靠的方向读数（传感器不可用、受磁干扰或未获得水平朝向）。\n\n请先使用参考照片或现场标志物完成人工对齐。手动确认后，本点位方向不会被传感器校验。',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '已对准，确认',
              style: TextStyle(color: PanoColors.amber),
            ),
          ),
        ],
      ),
    );
    if (ok == true) notifier.manualConfirmDirection();
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PanoColors.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: PanoColors.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PanoColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}