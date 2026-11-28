import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/compass_utils.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../domain/inspection_point.dart';
import '../../../domain/pano_work.dart';
import '../../gallery/gallery_sheet.dart';
import '../../session/pano_session.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';
import 'waypoint_editor_sheet.dart';

Future<void> openWaypointBriefSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _WaypointBriefSheet(),
  );
}

class _WaypointBriefSheet extends ConsumerWidget {
  const _WaypointBriefSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspection = ref.watch(inspectionProvider);
    final point = inspection.activePoint;
    final task = inspection.activeTask;
    if (point == null || task == null) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(inspectionProvider.notifier);
    final gallery = ref.watch(panoSessionProvider.select((s) => s.gallery));
    final locked = inspection.stage == InspectionStage.panorama;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: PanoColors.bgPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: PanoColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '点位详情',
                      style: TextStyle(
                        color: PanoColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '关闭',
                      style: TextStyle(color: PanoColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: PanoColors.amberDim,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: PanoColors.amber.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            point.code,
                            style: const TextStyle(
                              color: PanoColors.amber,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            point.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            color: PanoColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (task.isSample) ...[
                          const SizedBox(width: 8),
                          const Text(
                            '示例数据',
                            style: TextStyle(color: PanoColors.cyan, fontSize: 10),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          point.completed
                              ? '已完成 ${point.captureCount} 次'
                              : '未完成',
                          style: TextStyle(
                            color: point.completed
                                ? PanoColors.emerald
                                : PanoColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _InfoBlock(
                      icon: Icons.place_outlined,
                      title: '目标位置',
                      lines: [
                        if (point.hasCoordinates)
                          formatCoordinates(point.latitude!, point.longitude!)
                        else
                          '未设置经纬度，无法计算现场距离',
                        if (point.hasCoordinates)
                          _positionDetail(inspection)
                        else
                          '可在点位编辑中使用「当前位置」采集真实坐标',
                      ],
                    ),
                    _InfoBlock(
                      icon: Icons.explore_outlined,
                      title: '目标方向',
                      lines: [
                        if (point.hasTargetAzimuth)
                          '${formatAzimuth(point.targetAzimuthDeg)}${point.directionName.isEmpty ? '' : ' · ${point.directionName}'}'
                        else
                          '未设置目标方位角，可手动确认方向后拍摄',
                        '目标俯仰 ${point.targetPitchDeg.toStringAsFixed(0)}° · 到达半径 ${point.arrivalRadiusM.toStringAsFixed(0)} m',
                        if (inspection.headingDeg != null)
                          '当前设备朝向 ${formatAzimuth(inspection.headingDeg)}'
                              '${inspection.directionDeltaDeg == null ? '' : ' · ${formatDelta(inspection.directionDeltaDeg!)}'}',
                      ],
                      action: !locked && !point.hasTargetAzimuth && inspection.compassReliable
                          ? TextButton.icon(
                              onPressed: () => notifier.captureHeadingAsTarget(),
                              icon: const Icon(Icons.explore, size: 14),
                              label: const Text('用当前朝向设为目标', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                foregroundColor: PanoColors.cyan,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                          : null,
                    ),
                    if (point.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _TextBlock(title: '现场说明', text: point.description),
                    ],
                    if (point.instructions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _TextBlock(title: '拍摄说明', text: point.instructions),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      '参考照片',
                      style: TextStyle(
                        color: PanoColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (point.referenceImagePath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: Image.file(
                            File(point.referenceImagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: PanoColors.bgCard,
                              alignment: Alignment.center,
                              child: const Text(
                                '参考照片文件缺失\n请重新添加',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: PanoColors.rose, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: PanoColors.borderSubtle),
                        ),
                        child: const Text(
                          '该点位没有历史参考照片，因此不显示虚构参考图。\n可前往现场后拍摄并添加参考照片，或用文字说明与目标方向进行对齐。',
                          style: TextStyle(
                            color: PanoColors.textMuted,
                            fontSize: 11,
                            height: 1.6,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (!locked)
                      Row(
                        children: [
                          if (point.referenceImagePath != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  notifier.openReferenceOverlay(
                                    ReferenceCompareMode.ghost,
                                  );
                                },
                                icon: const Icon(Icons.compare, size: 16),
                                label: const Text('查看参考对齐'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: PanoColors.amber,
                                  side: const BorderSide(color: PanoColors.borderStrong),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                ),
                              ),
                            ),
                          if (point.referenceImagePath != null) const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _editPoint(context, ref, point),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('编辑点位'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PanoColors.textPrimary,
                                side: const BorderSide(color: PanoColors.borderStrong),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      '拍摄记录',
                      style: TextStyle(
                        color: PanoColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (point.records.isEmpty)
                      const Text(
                        '暂无拍摄记录',
                        style: TextStyle(color: PanoColors.textMuted, fontSize: 12),
                      )
                    else
                      _HistoryList(
                        records: point.records,
                        gallery: gallery,
                        onOpenGallery: () => openGallerySheet(context, ref),
                      ),
                    const SizedBox(height: 18),
                    if (inspection.stage == InspectionStage.briefing && !locked)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PanoColors.amber,
                          foregroundColor: PanoColors.bgBase,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          notifier.beginNavigation();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          '开始前往点位',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PanoColors.textPrimary,
                          side: const BorderSide(color: PanoColors.borderStrong),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('返回引导'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _positionDetail(InspectionState inspection) {
    final accuracy = inspection.gpsAccuracyM;
    final distance = inspection.distanceM;
    if (distance == null) {
      return inspection.gpsStatus == LocationUiStatus.locating
          ? '正在获取定位…'
          : '尚未获取当前位置';
    }
    final acc = accuracy == null ? '' : ' · GPS ±${accuracy.round()} m';
    return '当前距离 ${formatDistance(distance)}$acc';
  }

  Future<void> _editPoint(
    BuildContext context,
    WidgetRef ref,
    InspectionPoint point,
  ) async {
    final changed = await openWaypointEditorSheet(context, ref, point: point);
    if (changed != true || !context.mounted) return;
    final active = ref.read(inspectionProvider).activePoint;
    if (active == null) {
      Navigator.pop(context);
    }
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.lines,
    this.action,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: PanoColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: PanoColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: PanoColors.textSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PanoColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: PanoColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              color: PanoColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.records,
    required this.gallery,
    required this.onOpenGallery,
  });

  final List<InspectionRecord> records;
  final List<PanoWork> gallery;
  final VoidCallback onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final recent = records.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '累计 ${records.length} 次 · 最近 ${_formatTime(records.last.capturedAt)}',
          style: const TextStyle(color: PanoColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final record in recent) ...[
              GestureDetector(
                onTap: onOpenGallery,
                child: Container(
                  width: 62,
                  height: 44,
                  decoration: BoxDecoration(
                    color: PanoColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PanoColors.borderSubtle),
                    image: _thumb(record) != null
                        ? DecorationImage(
                            image: FileImage(File(_thumb(record)!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _thumb(record) == null
                      ? const Icon(
                          Icons.image_outlined,
                          size: 16,
                          color: PanoColors.textMuted,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            TextButton(
              onPressed: onOpenGallery,
              child: const Text(
                '打开作品库',
                style: TextStyle(color: PanoColors.cyan, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String? _thumb(InspectionRecord record) {
    for (final work in gallery) {
      if (work.id == record.workId) return work.thumbPath;
    }
    return null;
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }
}