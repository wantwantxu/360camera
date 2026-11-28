import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../widgets/glass.dart';
import '../../session/pano_session.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';
import 'waypoint_brief_sheet.dart';

class InspectionCaptureBanner extends ConsumerWidget {
  const InspectionCaptureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspection = ref.watch(inspectionProvider);
    final pano = ref.watch(panoSessionProvider);
    final point = inspection.activePoint;
    if (inspection.stage != InspectionStage.panorama || point == null) {
      return const SizedBox.shrink();
    }

    return GlassPanel(
      borderRadius: 14,
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined, size: 14, color: PanoColors.cyan),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      point.code,
                      style: const TextStyle(
                        color: PanoColors.amber,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        point.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '360° 拍摄 · 已捕捉 ${pano.capturedCount}/14'
                  '${point.referenceImagePath == null ? '' : ' · 有参考照片'}',
                  style: const TextStyle(color: PanoColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => openWaypointBriefSheet(context, ref),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 15, color: PanoColors.textSecondary),
                  Text('点位', style: TextStyle(color: PanoColors.textMuted, fontSize: 8)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _exit(context, ref),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close, size: 15, color: PanoColors.rose),
                  Text('退出', style: TextStyle(color: PanoColors.rose, fontSize: 8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exit(BuildContext context, WidgetRef ref) async {
    final captured = ref.read(panoSessionProvider).capturedCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('退出点位拍摄'),
        content: Text(
          captured == 0
              ? '本次点位尚未捕捉任何画面，确认退出？'
              : '已捕捉 $captured/14 个点位，退出将丢弃本次未合成的画面。确认退出？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续拍摄'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: PanoColors.rose)),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(inspectionProvider.notifier).exitPoint();
    }
  }
}