import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/space_theme.dart';
import '../../data/gallery_repository.dart';
import '../../domain/pano_work.dart';
import '../../domain/vr_space.dart';
import 'space_routes.dart';
import 'spaces_controller.dart';
import 'widgets/space_minimap.dart';
import 'widgets/space_widgets.dart';

enum _AddPointAction { capture, importPhoto, fromGallery }

class SpaceDetailPage extends ConsumerWidget {
  const SpaceDetailPage({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spacesProvider);
    final space = state.byId(spaceId);

    return Theme(
      data: buildSpaceTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: SpaceColors.bg,
          body: SafeArea(
            bottom: false,
            child: state.loading && space == null
                ? const Center(
                    child: CircularProgressIndicator(color: SpaceColors.accent),
                  )
                : space == null
                    ? _MissingSpace(
                        onBack: () => _goBack(context),
                      )
                    : _SpaceDetailBody(space: space),
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(SpaceRoutes.home);
    }
  }
}

class _SpaceDetailBody extends ConsumerWidget {
  const _SpaceDetailBody({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 720 ? 32.0 : 18.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(space: space),
                  const SizedBox(height: 14),
                  _CoverHero(space: space),
                  const SizedBox(height: 14),
                  _PrimaryActions(space: space),
                  const SizedBox(height: 14),
                  _Stats(space: space),
                  const SizedBox(height: 22),
                  SpaceSectionHeader(
                    title: '空间点位',
                    subtitle: space.points.isEmpty
                        ? '从一个点位开始，移动 2–3 米再采集下一个'
                        : '点击可进入对应位置漫游',
                    trailing: TextButton.icon(
                      onPressed: () => _showAddPoint(context, ref),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('添加'),
                      style: TextButton.styleFrom(
                        foregroundColor: SpaceColors.accentDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (space.points.isEmpty)
                    _EmptyPoints(
                      onCapture: () =>
                          context.push(SpaceRoutes.capture(space.id)),
                      onImport: () => _importPhoto(context, ref),
                    )
                  else
                    for (var i = 0; i < space.points.length; i++) ...[
                      _PointTile(
                        space: space,
                        index: i,
                        point: space.points[i],
                        onOpen: () => context.push(
                          SpaceRoutes.tour(
                            space.id,
                            pointId: space.points[i].id,
                          ),
                        ),
                      ),
                      if (i != space.points.length - 1)
                        const SizedBox(height: 9),
                    ],
                  if (space.points.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _MapCard(space: space),
                  ],
                  const SizedBox(height: 22),
                  _TipsCard(hasPoints: space.points.isNotEmpty),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddPoint(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_AddPointAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddPointSheet(),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _AddPointAction.capture:
        context.push(SpaceRoutes.capture(space.id));
        return;
      case _AddPointAction.importPhoto:
        await _importPhoto(context, ref);
        return;
      case _AddPointAction.fromGallery:
        await _importFromGallery(context, ref);
        return;
    }
  }

  Future<void> _importPhoto(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !context.mounted) return;
    try {
      final bytes = await files.first.readAsBytes();
      if (!context.mounted) return;
      final name = await _askPointName(
        context,
        title: '导入全景图',
        initial: _stripExtension(files.first.name),
      );
      if (name == null || !context.mounted) return;
      await ref.read(spacesProvider.notifier).addPointFromImage(
            spaceId: space.id,
            bytes: bytes,
            name: name,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全景图已加入空间')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _importFromGallery(BuildContext context, WidgetRef ref) async {
    List<PanoWork> works;
    try {
      works = await ref.read(galleryRepositoryProvider).loadAll();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取作品库失败：$e')),
      );
      return;
    }
    if (!context.mounted) return;
    if (works.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('作品库暂无全景，请先拍摄或导入图片')),
      );
      return;
    }
    final work = await showModalBottomSheet<PanoWork>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkPickerSheet(works: works),
    );
    if (work == null || !context.mounted) return;
    try {
      final name = await _askPointName(
        context,
        title: '添加到空间',
        initial: work.title,
      );
      if (name == null || !context.mounted) return;
      await ref.read(spacesProvider.notifier).addPointFromWork(
            spaceId: space.id,
            work: work,
            name: name,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('作品已加入空间')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：$e')),
      );
    }
  }

  Future<String?> _askPointName(
    BuildContext context, {
    required String title,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '点位名称',
              counterText: '',
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(dialogContext, value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  String _stripExtension(String name) {
    final index = name.lastIndexOf('.');
    if (index <= 0) return name;
    return name.substring(0, index);
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(SpaceRoutes.home);
            }
          },
          style: IconButton.styleFrom(
            backgroundColor: SpaceColors.surface,
            side: const BorderSide(color: SpaceColors.line),
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${space.category.label} · 更新于 ${formatSpaceDate(space.updatedAt)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: SpaceColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<_SpaceMenuAction>(
          tooltip: '空间操作',
          onSelected: (action) => _onAction(context, ref, action),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          color: SpaceColors.surface,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _SpaceMenuAction.rename,
              child: Text('重命名空间'),
            ),
            PopupMenuItem(
              value: _SpaceMenuAction.guide,
              child: Text('查看拍摄指南'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: _SpaceMenuAction.delete,
              child: Text(
                '删除空间',
                style: TextStyle(color: Color(0xFFE5484D)),
              ),
            ),
          ],
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SpaceColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SpaceColors.line),
            ),
            child: const Icon(Icons.more_horiz_rounded, size: 20),
          ),
        ),
      ],
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _SpaceMenuAction action,
  ) async {
    switch (action) {
      case _SpaceMenuAction.rename:
        final name = await _renameDialog(context, space.name);
        if (name == null || !context.mounted) return;
        try {
          await ref
              .read(spacesProvider.notifier)
              .renameSpace(space.id, name);
        } catch (e) {
          if (context.mounted) _showError(context, '重命名失败：$e');
        }
        return;
      case _SpaceMenuAction.guide:
        await showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _QuickGuideSheet(),
        );
        return;
      case _SpaceMenuAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除空间？'),
            content: Text(
              '将删除「${space.name}」及其项目内的 ${space.points.length} 个点位副本。作品库中的原始全景不会被删除。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await ref.read(spacesProvider.notifier).deleteSpace(space.id);
          if (context.mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(SpaceRoutes.home);
            }
          }
        } catch (e) {
          if (context.mounted) _showError(context, '删除失败：$e');
        }
        return;
    }
  }

  Future<String?> _renameDialog(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名空间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _SpaceMenuAction { rename, guide, delete }

class _CoverHero extends StatelessWidget {
  const _CoverHero({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context) {
    final ready = space.points.isNotEmpty;
    return GestureDetector(
      onTap: () {
        if (ready) {
          context.push(SpaceRoutes.tour(space.id));
        } else {
          context.push(SpaceRoutes.capture(space.id));
        }
      },
      child: AspectRatio(
        aspectRatio: 1.62,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SpaceCover(point: space.coverPoint, showPlay: ready),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.64),
                    ],
                    stops: const [0.45, 1],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 14,
                child: SpaceCategoryBadge(
                  category: space.category,
                  light: true,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ready ? '点击进入 VR 漫游' : '点击开始采集第一个点位',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ready
                                ? '${space.points.length} 个点位 · ${space.labelCount} 个空间标签 · 步进式漫游'
                                : '跟随 24 方向引导完成拍摄，自动拼接与串联',
                            style: const TextStyle(
                              color: Color(0xBFFFFFFF),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        ready
                            ? Icons.play_arrow_rounded
                            : Icons.camera_alt_rounded,
                        color: SpaceColors.ink,
                        size: 23,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context) {
    final ready = space.points.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.push(SpaceRoutes.capture(space.id)),
            style: FilledButton.styleFrom(
              backgroundColor: SpaceColors.accent,
              minimumSize: const Size(0, 52),
            ),
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: Text(ready ? '继续拍摄点位' : '开始拍摄'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: ready
                ? () => context.push(SpaceRoutes.tour(space.id))
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: SpaceColors.ink,
              disabledBackgroundColor: SpaceColors.line,
              disabledForegroundColor: SpaceColors.inkMuted,
              minimumSize: const Size(0, 52),
            ),
            icon: const Icon(Icons.view_in_ar_rounded, size: 18),
            label: const Text('进入 VR'),
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _stat(
            icon: Icons.location_on_outlined,
            value: '${space.points.length}',
            label: '点位',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(
            icon: Icons.sell_outlined,
            value: '${space.labelCount}',
            label: '标签',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(
            icon: Icons.straighten_rounded,
            value: '示意',
            label: '空间位置',
          ),
        ),
      ],
    );
  }

  Widget _stat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: SpaceColors.inkSecondary),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: SpaceColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointTile extends ConsumerWidget {
  const _PointTile({
    required this.space,
    required this.index,
    required this.point,
    required this.onOpen,
  });

  final VrSpace space;
  final int index;
  final VrPoint point;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: SpaceColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SpaceColors.line),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: 92,
                    height: 68,
                    child: SpaceCover(point: point, borderRadius: 11),
                  ),
                  Positioned(
                    left: 5,
                    top: 5,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
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
                        const SizedBox(width: 6),
                        PointSourceBadge(source: point.source),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${point.width}×${point.height}',
                        if (point.labels.isNotEmpty) '${point.labels.length} 个标签',
                        if (point.headingDeg == null) '方位未记录',
                        formatSpaceDate(point.createdAt),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: SpaceColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PointMenuAction>(
                tooltip: '点位操作',
                onSelected: (action) => _onAction(context, ref, action),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                color: SpaceColors.surface,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _PointMenuAction.rename,
                    child: Text('重命名点位'),
                  ),
                  if (space.coverPointId != point.id)
                    const PopupMenuItem(
                      value: _PointMenuAction.cover,
                      child: Text('设为空间封面'),
                    ),
                  const PopupMenuItem(
                    value: _PointMenuAction.delete,
                    child: Text(
                      '删除点位',
                      style: TextStyle(color: Color(0xFFE5484D)),
                    ),
                  ),
                ],
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: SpaceColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _PointMenuAction action,
  ) async {
    switch (action) {
      case _PointMenuAction.rename:
        final controller = TextEditingController(text: point.name);
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('重命名点位'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(counterText: ''),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) {
                    Navigator.pop(dialogContext, value);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (name == null || !context.mounted) return;
        try {
          await ref.read(spacesProvider.notifier).renamePoint(
                space.id,
                point.id,
                name,
              );
        } catch (e) {
          if (context.mounted) _error(context, '重命名失败：$e');
        }
        return;
      case _PointMenuAction.cover:
        try {
          await ref.read(spacesProvider.notifier).setCover(space.id, point.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已设为空间封面')),
            );
          }
        } catch (e) {
          if (context.mounted) _error(context, '设置失败：$e');
        }
        return;
      case _PointMenuAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除点位？'),
            content: Text(
              '将从空间中移除「${point.name}」。作品库中的原始全景不会被删除。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        try {
          await ref
              .read(spacesProvider.notifier)
              .removePoint(space.id, point.id);
        } catch (e) {
          if (context.mounted) _error(context, '删除失败：$e');
        }
        return;
    }
  }

  void _error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _PointMenuAction { rename, cover, delete }

class _MapCard extends StatelessWidget {
  const _MapCard({required this.space});

  final VrSpace space;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 14, 13, 10),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '空间位置示意',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Spacer(),
              Text(
                '非实测户型',
                style: TextStyle(
                  fontSize: 9,
                  color: SpaceColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SpaceMinimap(
            space: space,
            height: 172,
            onTapPoint: (point) => context.push(
              SpaceRoutes.tour(space.id, pointId: point.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPoints extends StatelessWidget {
  const _EmptyPoints({required this.onCapture, required this.onImport});

  final VoidCallback onCapture;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 34,
            color: SpaceColors.inkMuted,
          ),
          const SizedBox(height: 8),
          const Text(
            '空间里还没有点位',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '采集第一个点位后，即可进入 VR 并继续添加相邻点位。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpaceColors.inkSecondary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onCapture,
                  style: FilledButton.styleFrom(
                    backgroundColor: SpaceColors.accent,
                    minimumSize: const Size(0, 46),
                  ),
                  child: const Text('开始采集'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onImport,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                  ),
                  child: const Text('导入全景图'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.hasPoints});

  final bool hasPoints;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: SpaceColors.accentSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.tips_and_updates_outlined,
            size: 18,
            color: SpaceColors.accentDark,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              hasPoints
                  ? '移动 2–3 米再拍下一个点位，保持手机竖直并让相邻点位能看到同一片区域，漫游时会更容易辨认方向。'
                  : '选择光线均匀、空间开阔的位置站立；拍摄过程中保持身体位置不动，只转动手机。',
              style: const TextStyle(
                color: Color(0xFF96402C),
                fontSize: 11,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPointSheet extends StatelessWidget {
  const _AddPointSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SpaceColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '添加空间点位',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                '每个点位是一张可环顾的 360° 全景。',
                style: TextStyle(
                  fontSize: 11,
                  color: SpaceColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _action(
                context,
                icon: Icons.camera_alt_rounded,
                title: '现场采集',
                subtitle: '24 方向引导拍摄并自动拼接',
                accent: true,
                value: _AddPointAction.capture,
              ),
              const SizedBox(height: 8),
              _action(
                context,
                icon: Icons.add_photo_alternate_outlined,
                title: '从相册导入全景图',
                subtitle: '支持 2:1 等距柱状全景图片',
                value: _AddPointAction.importPhoto,
              ),
              const SizedBox(height: 8),
              _action(
                context,
                icon: Icons.photo_library_outlined,
                title: '从作品库选择',
                subtitle: '复用已经拍摄或导入的全景作品',
                value: _AddPointAction.fromGallery,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required _AddPointAction value,
    bool accent = false,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: accent ? SpaceColors.accentSoft : SpaceColors.surfaceAlt,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: accent ? const Color(0xFFFFC8BA) : SpaceColors.line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent ? SpaceColors.accent : SpaceColors.surface,
                borderRadius: BorderRadius.circular(11),
                border: accent ? null : Border.all(color: SpaceColors.line),
              ),
              child: Icon(
                icon,
                size: 19,
                color: accent ? Colors.white : SpaceColors.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SpaceColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: SpaceColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkPickerSheet extends StatelessWidget {
  const _WorkPickerSheet({required this.works});

  final List<PanoWork> works;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SpaceColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text(
                    '选择全景作品',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                shrinkWrap: true,
                itemCount: works.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final work = works[index];
                  return InkWell(
                    onTap: () => Navigator.pop(context, work),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SpaceColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: SpaceColors.line),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.file(
                              File(work.thumbPath),
                              width: 86,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 86,
                                height: 56,
                                color: SpaceColors.line,
                                child: const Icon(
                                  Icons.panorama_photosphere,
                                  size: 20,
                                  color: SpaceColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  work.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${work.width}×${work.height} · ${formatSpaceDate(work.createdAt)}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: SpaceColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 19,
                            color: SpaceColors.accent,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickGuideSheet extends StatelessWidget {
  const _QuickGuideSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SpaceColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '这个空间怎么拍',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const _MiniTip(
                icon: Icons.accessibility_new_rounded,
                text: '到达点位后站定，身体不要平移，只转动手机。',
              ),
              const _MiniTip(
                icon: Icons.threesixty_rounded,
                text: '水平 8 张、仰拍 8 张、俯拍 8 张，共 24 个方向。',
              ),
              const _MiniTip(
                icon: Icons.directions_walk_rounded,
                text: '用底部“完成采集”合成本点位，再移动到 2–3 米外的下一个位置。',
              ),
              const _MiniTip(
                icon: Icons.moving_rounded,
                text: '尽量保持相邻点位朝向一致，入口热点会更准确。',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: SpaceColors.accent,
                  ),
                  child: const Text('开始采集'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTip extends StatelessWidget {
  const _MiniTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: SpaceColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: SpaceColors.accentDark),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: SpaceColors.inkSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingSpace extends StatelessWidget {
  const _MissingSpace({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_off_outlined,
            size: 40,
            color: SpaceColors.inkMuted,
          ),
          const SizedBox(height: 10),
          const Text(
            '空间不存在或已删除',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onBack, child: const Text('返回空间列表')),
        ],
      ),
    );
  }
}