import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../domain/pano_work.dart';
import '../../../widgets/glass.dart';
import '../../session/pano_session.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';
import 'inspection_task_sheet.dart';

class PanoramaReviewDock extends ConsumerStatefulWidget {
  const PanoramaReviewDock({super.key});

  @override
  ConsumerState<PanoramaReviewDock> createState() => _PanoramaReviewDockState();
}

class _PanoramaReviewDockState extends ConsumerState<PanoramaReviewDock> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final inspection = ref.watch(inspectionProvider);
    if (inspection.stage != InspectionStage.review) {
      return const SizedBox.shrink();
    }
    final point = inspection.activePoint;
    final task = inspection.activeTask;
    final work = _findWork(ref.watch(panoSessionProvider.select((s) => s.gallery)));
    final thumbReady = work != null && File(work.thumbPath).existsSync();
    final isLastPoint = task != null && point != null
        ? task.completedCount >= task.points.length - 1
        : false;

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
            opacity: 0.94,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: PanoColors.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: PanoColors.borderSubtle),
                        image: thumbReady
                            ? DecorationImage(
                                image: FileImage(File(work.thumbPath)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: !thumbReady
                          ? const Icon(
                              Icons.panorama,
                              color: PanoColors.textMuted,
                              size: 22,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 15,
                                color: PanoColors.emerald,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  point == null
                                      ? '全景已合成'
                                      : '${point.code} ${point.name} · 全景已合成',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            work == null
                                ? '拍摄结果未在作品库中找到，仍可确认写入点位记录'
                                : '${work.width}×${work.height} · 确认后写入点位记录${isLastPoint ? '并完成任务' : '并前往下一点位'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PanoColors.textMuted,
                              fontSize: 10,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _exitReview,
                      tooltip: '退出确认',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: PanoColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: _busy ? null : _confirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: PanoColors.emerald,
                            foregroundColor: PanoColors.bgBase,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _busy ? '保存中…' : '确认保存并完成点位',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _retake,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PanoColors.textPrimary,
                            side: const BorderSide(color: PanoColors.borderStrong),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('重拍', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PanoWork? _findWork(List<PanoWork> gallery) {
    final id = ref.read(inspectionProvider).pendingWorkId;
    if (id == null) return null;
    for (final work in gallery) {
      if (work.id == id) return work;
    }
    return null;
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    await ref.read(inspectionProvider.notifier).confirmReview();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _exitReview() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('退出本次确认'),
        content: const Text(
          '本次全景已保存在相册，退出后不会写入点位历史记录，该点位仍为未完成。确认退出？',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续确认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: PanoColors.rose)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(inspectionProvider.notifier).exitPoint();
    }
  }

  Future<void> _retake() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('重新拍摄'),
        content: const Text('将删除刚生成的全景作品并重新进行 14 点位拍摄，确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除并重拍', style: TextStyle(color: PanoColors.rose)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(inspectionProvider.notifier).retakePanorama();
    if (!mounted) return;
    setState(() => _busy = false);
  }
}

class InspectionCompletionCard extends ConsumerWidget {
  const InspectionCompletionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspection = ref.watch(inspectionProvider);
    if (inspection.stage != InspectionStage.taskComplete) {
      return const SizedBox.shrink();
    }
    final task = inspection.activeTask;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 64,
      left: 12,
      right: 12,
      child: GlassPanel(
        borderRadius: 14,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, size: 18, color: PanoColors.emerald),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task == null
                    ? '巡检任务已完成'
                    : '任务已完成 · ${task.title}（${task.completedCount}/${task.points.length}）',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PanoColors.emerald,
                ),
              ),
            ),
            TextButton(
              onPressed: () => openInspectionTaskSheet(context, ref),
              child: const Text(
                '查看任务',
                style: TextStyle(color: PanoColors.cyan, fontSize: 11),
              ),
            ),
            GestureDetector(
              onTap: () => ref.read(inspectionProvider.notifier).exitPoint(),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close, size: 15, color: PanoColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}