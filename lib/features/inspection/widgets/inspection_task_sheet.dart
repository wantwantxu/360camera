import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/compass_utils.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../domain/inspection_point.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';
import 'waypoint_brief_sheet.dart';
import 'waypoint_editor_sheet.dart';

Future<void> openInspectionTaskSheet(BuildContext context, WidgetRef ref) async {
  final shouldOpenBrief = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _InspectionTaskSheet(),
  );
  if (shouldOpenBrief == true && context.mounted) {
    await openWaypointBriefSheet(context, ref);
  }
}

class _InspectionTaskSheet extends ConsumerWidget {
  const _InspectionTaskSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspection = ref.watch(inspectionProvider);
    final notifier = ref.read(inspectionProvider.notifier);
    final task = inspection.activeTask;
    final locked = inspection.stage == InspectionStage.panorama ||
        inspection.stage == InspectionStage.review;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
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
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
              child: Row(
                children: [
                  const Icon(Icons.assignment_outlined, size: 17, color: PanoColors.amber),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      '巡检任务',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: locked ? null : () => _createTask(context, ref),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('新建任务', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: PanoColors.cyan,
                      disabledForegroundColor: PanoColors.textMuted,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18, color: PanoColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (inspection.loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: PanoColors.amber),
                ),
              )
            else if (inspection.loadError != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      inspection.loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PanoColors.rose, fontSize: 12),
                    ),
                  ),
                ),
              )
            else if (inspection.tasks.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '还没有巡检任务',
                          style: TextStyle(color: PanoColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => _createTask(context, ref),
                          style: FilledButton.styleFrom(
                            backgroundColor: PanoColors.amber,
                            foregroundColor: PanoColors.bgBase,
                          ),
                          child: const Text('新建巡检任务'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              if (locked)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: PanoColors.amberDim,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PanoColors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock, size: 14, color: PanoColors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          inspection.stage == InspectionStage.review
                              ? '点位结果等待确认，请先保存、重拍或退出后再切换点位'
                              : '全景拍摄进行中，完成或退出拍摄后才能切换点位或编辑',
                          style: const TextStyle(color: PanoColors.amber, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  itemCount: inspection.tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final t = inspection.tasks[index];
                    final active = t.id == inspection.activeTaskId;
                    return GestureDetector(
                      onTap: () {
                        if (!locked) notifier.selectTask(t.id);
                      },
                      child: Container(
                        width: 168,
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? PanoColors.amberDim : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? PanoColors.amber : PanoColors.borderSubtle,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active ? PanoColors.amber : PanoColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t.isSample
                                  ? '示例 · ${t.completedCount}/${t.points.length} 已完成'
                                  : '${t.completedCount}/${t.points.length} 已完成',
                              style: TextStyle(
                                fontSize: 10,
                                color: active ? PanoColors.amber : PanoColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (task != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.description.isEmpty
                              ? '共 ${task.points.length} 个点位，按现场情况逐点完成拍摄'
                              : task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PanoColors.textMuted,
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (task.isSample)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            '示例数据 · 无真实坐标/照片',
                            style: TextStyle(color: PanoColors.cyan, fontSize: 9),
                          ),
                        ),
                    ],
                  ),
                ),
                if (task.points.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '该任务还没有点位',
                              style: TextStyle(color: PanoColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: locked ? null : () => _addPoint(context, ref),
                              child: const Text('新增点位'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                      itemCount: task.points.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final point = task.points[index];
                        return _PointTile(
                          point: point,
                          index: index,
                          enabled: !locked,
                          onOpen: () {
                            notifier.selectPoint(task.id, point.id);
                            Navigator.pop(context, true);
                          },
                          onEdit: () => _editPoint(context, ref, point),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: locked ? null : () => _addPoint(context, ref),
                          icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                          label: const Text('新增点位'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PanoColors.textPrimary,
                            side: const BorderSide(color: PanoColors.borderStrong),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: locked || task.points.isEmpty
                              ? null
                              : () {
                                  final next = task.nextIncomplete(
                                    afterPointId: inspection.activePointId,
                                  );
                                  if (next == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('该任务全部点位已完成，可新增点位或查看历史记录'),
                                      ),
                                    );
                                    return;
                                  }
                                  notifier.selectPoint(task.id, next.id);
                                  Navigator.pop(context, true);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: PanoColors.amber,
                            foregroundColor: PanoColors.bgBase,
                            disabledBackgroundColor: Colors.white12,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text(
                            '下一个未完成点位',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createTask(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('新建巡检任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '任务名称',
                hintText: '如 大坝月度巡检',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '任务说明（可选）',
                hintText: '巡检范围、注意事项',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final taskTitle = title.text.trim();
    final taskDescription = description.text.trim();
    if (created != true || !context.mounted) return;
    final task = await ref.read(inspectionProvider.notifier).createTask(
          title: taskTitle,
          description: taskDescription,
        );
    if (task == null || !context.mounted) return;
    await _addPoint(context, ref);
  }

  Future<void> _addPoint(BuildContext context, WidgetRef ref) async {
    final task = ref.read(inspectionProvider).activeTask;
    if (task == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择或新建巡检任务')),
      );
      return;
    }
    await openWaypointEditorSheet(context, ref);
  }

  Future<void> _editPoint(
    BuildContext context,
    WidgetRef ref,
    InspectionPoint point,
  ) async {
    await openWaypointEditorSheet(context, ref, point: point);
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({
    required this.point,
    required this.index,
    required this.enabled,
    required this.onOpen,
    required this.onEdit,
  });

  final InspectionPoint point;
  final int index;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (point.hasTargetAzimuth)
        '目标 ${formatAzimuth(point.targetAzimuthDeg)}'
      else
        '未设目标方向',
      if (point.hasCoordinates)
        '坐标 ${formatCoordinates(point.latitude!, point.longitude!)}'
      else
        '未设坐标',
      if (point.referenceImagePath != null) '有参考照片',
    ];

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onOpen : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PanoColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: point.completed
                      ? PanoColors.emeraldDim
                      : PanoColors.amber.withValues(alpha: 0.12),
                  border: Border.all(
                    color: point.completed ? PanoColors.emerald : PanoColors.amber,
                  ),
                ),
                child: point.completed
                    ? const Icon(Icons.check, size: 15, color: PanoColors.emerald)
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: PanoColors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          point.code,
                          style: const TextStyle(
                            color: PanoColors.textMuted,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            point.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (point.completed)
                          Text(
                            '${point.captureCount} 次',
                            style: const TextStyle(
                              color: PanoColors.emerald,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PanoColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: enabled ? onEdit : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: PanoColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}