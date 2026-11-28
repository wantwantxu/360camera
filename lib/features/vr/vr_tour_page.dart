import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/space_theme.dart';
import '../../core/utils/angle_utils.dart';
import '../../domain/app_enums.dart';
import '../../domain/vr_space.dart';
import '../preview/pano_sphere_view.dart';
import 'space_routes.dart';
import 'spaces_controller.dart';
import 'widgets/space_minimap.dart';

class VrTourPage extends ConsumerStatefulWidget {
  const VrTourPage({
    super.key,
    required this.spaceId,
    this.initialPointId,
  });

  final String spaceId;
  final String? initialPointId;

  @override
  ConsumerState<VrTourPage> createState() => _VrTourPageState();
}

class _VrTourPageState extends ConsumerState<VrTourPage> {
  String? _initializedSpaceId;
  String? _currentPointId;
  Uint8List? _bytes;
  bool _imageLoading = false;
  String? _loadError;
  int _loadGeneration = 0;
  bool _repairScheduled = false;

  double _lon = 0;
  double _lat = 0;
  double _fov = 74;
  bool _dragging = false;
  bool _autoRotate = false;
  Timer? _autoTimer;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _currentPointId = widget.initialPointId;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider);
    final space = spaces.byId(widget.spaceId);

    if (space == null) {
      return _Shell(
        child: spaces.loading
            ? const CircularProgressIndicator(color: SpaceColors.accent)
            : _EmptyTour(
                title: '空间不存在',
                message: '该空间可能已被删除。',
                onBack: _goBack,
              ),
      );
    }

    if (space.points.isEmpty) {
      return _Shell(
        child: _EmptyTour(
          title: '还没有可漫游的点位',
          message: '先拍摄一个点位并合成全景，再进入 VR 漫游。',
          onCapture: () => context.push(SpaceRoutes.capture(space.id)),
          onBack: _goBack,
        ),
      );
    }

    if (_initializedSpaceId != space.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initSpace(space));
      return const _Shell(
        child: CircularProgressIndicator(color: SpaceColors.accent),
      );
    }

    final point = space.pointById(_currentPointId);
    if (point == null) {
      if (!_repairScheduled) {
        _repairScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _repairScheduled = false;
          final latest = ref.read(spacesProvider).byId(widget.spaceId);
          if (latest != null && latest.points.isNotEmpty) {
            _selectPoint(latest.points.first);
          }
        });
      }
      return const _Shell(
        child: CircularProgressIndicator(color: SpaceColors.accent),
      );
    }

    final index = space.indexOfPoint(point.id);
    final hasNext = index >= 0 && index < space.points.length - 1;
    final hotspots = buildSequentialHotspots(space, point);

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
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _bytes == null
                    ? const ColoredBox(
                        key: ValueKey('tour-empty'),
                        color: Color(0xFF09090B),
                      )
                    : PanoSphereView(
                        key: ValueKey('tour-$_currentPointId'),
                        imageBytes: _bytes,
                        lon: _lon,
                        lat: _lat,
                        fov: _fov,
                        view: ProjectionView.normal,
                        interactive: true,
                        onDragStart: () => _dragging = true,
                        onDragEnd: () => _dragging = false,
                        onAttitudeChanged: (delta) {
                          if (!mounted) return;
                          setState(() {
                            _lon = normalizeDeg360(_lon + delta.dx);
                            _lat = clampPitch(_lat + delta.dy);
                          });
                        },
                        onFovChanged: (value) {
                          if (!mounted) return;
                          setState(() => _fov = value);
                        },
                      ),
              ),
              if (!_imageLoading && _bytes != null)
                _TourOverlayLayer(
                  hotspots: hotspots,
                  labels: point.labels,
                  lon: _lon,
                  lat: _lat,
                  fov: _fov,
                  onHotspotTap: (targetId) {
                    final target = space.pointById(targetId);
                    if (target != null) _selectPoint(target);
                  },
                  onLabelTap: (label) =>
                      _showLabelActions(space, point, label),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xCC000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                      stops: [0, 0.22, 0.7, 1],
                    ),
                  ),
                ),
              ),
              _TopBar(
                spaceName: space.name,
                pointName: point.name,
                index: index + 1,
                total: space.points.length,
                orientationKnown: point.orientationKnown,
                onBack: _goBack,
                onShare: () => _sharePanorama(space, point),
              ),
              _ToolRail(
                autoRotate: _autoRotate,
                showMap: _showMap,
                hasNext: hasNext,
                onToggleAutoRotate: _toggleAutoRotate,
                onAddLabel: () => _addLabel(space, point),
                onToggleMap: () => setState(() => _showMap = !_showMap),
                onNext: hasNext
                    ? () => _selectPoint(space.points[index + 1])
                    : null,
              ),
              if (_showMap && space.points.length > 1)
                Positioned(
                  left: 14,
                  bottom: MediaQuery.paddingOf(context).bottom + 118,
                  width: 232,
                  child: _MapCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpaceMinimap(
                          space: space,
                          currentPointId: point.id,
                          dark: true,
                          height: 148,
                          viewWorldYawDeg: point.headingDeg == null
                              ? null
                              : normalizeDeg360(point.headingDeg! + _lon),
                          onTapPoint: (target) => _selectPoint(target),
                        ),
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 11,
                              color: Colors.white38,
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '空间位置示意 · 按采集顺序估算，非实测户型',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PointStrip(
                  space: space,
                  currentPointId: point.id,
                  onSelect: _selectPoint,
                ),
              ),
              if (_imageLoading)
                const IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: SpaceColors.accent,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 14),
                        Text(
                          '正在载入全景…',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_imageLoading && _loadError != null)
                _LoadError(
                  message: _loadError!,
                  onRetry: () => _loadPointImage(point),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initSpace(VrSpace space) async {
    if (!mounted || _initializedSpaceId == space.id) return;
    _initializedSpaceId = space.id;
    final initial = space.pointById(widget.initialPointId) ??
        space.coverPoint ??
        space.points.first;
    await _selectPoint(initial);
  }

  Future<void> _selectPoint(VrPoint point) async {
    if (!mounted) return;
    final changed = _currentPointId != point.id;
    if (!changed && _bytes != null && !_imageLoading) return;
    if (changed) {
      _autoTimer?.cancel();
      _autoTimer = null;
      _autoRotate = false;
      _lon = 0;
      _lat = 0;
      _fov = 74;
    }
    setState(() {
      _currentPointId = point.id;
      _bytes = changed ? null : _bytes;
      _imageLoading = true;
      _loadError = null;
    });
    await _loadPointImage(point);
  }

  Future<void> _loadPointImage(VrPoint point) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _imageLoading = true;
        _loadError = null;
      });
    }
    try {
      final file = File(point.imagePath);
      if (!await file.exists()) {
        throw const FileSystemException('全景文件不存在');
      }
      final bytes = await file.readAsBytes();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bytes = bytes;
        _imageLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bytes = null;
        _imageLoading = false;
        _loadError = '全景载入失败：$e';
      });
    }
  }

  void _toggleAutoRotate() {
    final next = !_autoRotate;
    _autoTimer?.cancel();
    _autoTimer = null;
    setState(() => _autoRotate = next);
    if (!next) return;
    _autoTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || _dragging) return;
      setState(() => _lon = normalizeDeg360(_lon + 0.28));
    });
  }

  Future<void> _sharePanorama(VrSpace space, VrPoint point) async {
    final file = File(point.imagePath);
    if (!await file.exists()) {
      _showSnack('全景文件不存在，无法分享');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${space.name} · ${point.name} · PANO 360 Pro',
        ),
      );
    } catch (e) {
      _showSnack('分享失败：$e');
    }
  }

  Future<void> _addLabel(VrSpace space, VrPoint point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '标签会固定在当前视角，用于标记空间内的物品、设施或说明。',
              style: TextStyle(fontSize: 12.5, height: 1.55),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 18,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '例如：落地窗 / 消防栓 / 展示柜',
                counterText: '',
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                Navigator.of(ctx).pop(trimmed.isEmpty ? null : trimmed);
              },
            ),
            const SizedBox(height: 6),
            Text(
              '位置：水平 ${normalizeDeg360(_lon).round()}° · '
              '俯仰 ${_lat.round()}°',
              style: const TextStyle(
                color: SpaceColors.inkMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.of(ctx).pop(trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await ref.read(spacesProvider.notifier).addLabel(
            spaceId: space.id,
            pointId: point.id,
            text: text,
            yawDeg: _lon,
            pitchDeg: _lat,
          );
      _showSnack('已添加标签“$text”');
    } catch (e) {
      _showSnack('添加标签失败：$e');
    }
  }

  Future<void> _showLabelActions(
    VrSpace space,
    VrPoint point,
    SpaceLabel label,
  ) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Theme(
        data: buildSpaceTheme(),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: SpaceColors.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: SpaceColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label.text,
                        style: const TextStyle(
                          color: SpaceColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${point.name} · 水平 ${label.yawDeg.round()}° · '
                  '俯仰 ${label.pitchDeg.round()}°',
                  style: const TextStyle(
                    color: SpaceColors.inkMuted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('关闭'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFE5484D),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('删除标签'),
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
    if (remove != true || !mounted) return;
    try {
      await ref.read(spacesProvider.notifier).removeLabel(
            space.id,
            point.id,
            label.id,
          );
      _showSnack('标签已删除');
    } catch (e) {
      _showSnack('删除标签失败：$e');
    }
  }

  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(SpaceRoutes.detail(widget.spaceId));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildSpaceTheme(),
      child: Scaffold(
        backgroundColor: SpaceColors.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 14,
                top: 6,
                child: Material(
                  color: SpaceColors.surface,
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(SpaceRoutes.home);
                      }
                    },
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: SpaceColors.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Center(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTour extends StatelessWidget {
  const _EmptyTour({
    required this.title,
    required this.message,
    required this.onBack,
    this.onCapture,
  });

  final String title;
  final String message;
  final VoidCallback onBack;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: SpaceColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.panorama_photosphere_rounded,
              color: SpaceColors.inkMuted,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpaceColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpaceColors.inkSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          if (onCapture != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SpaceColors.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: onCapture,
              icon: const Icon(Icons.add_a_photo_rounded, size: 18),
              label: const Text('去拍摄点位'),
            ),
            const SizedBox(height: 8),
          ],
          TextButton(onPressed: onBack, child: const Text('返回')),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.spaceName,
    required this.pointName,
    required this.index,
    required this.total,
    required this.orientationKnown,
    required this.onBack,
    required this.onShare,
  });

  final String spaceName;
  final String pointName;
  final int index;
  final int total;
  final bool orientationKnown;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '返回空间',
                onTap: onBack,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '$pointName · $index/$total',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                        if (!orientationKnown) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              '方位未知',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 8.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GlassIconButton(
                icon: Icons.ios_share_rounded,
                tooltip: '分享全景原图',
                onTap: onShare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? SpaceColors.accent
            : Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 19,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({
    required this.autoRotate,
    required this.showMap,
    required this.hasNext,
    required this.onToggleAutoRotate,
    required this.onAddLabel,
    required this.onToggleMap,
    required this.onNext,
  });

  final bool autoRotate;
  final bool showMap;
  final bool hasNext;
  final VoidCallback onToggleAutoRotate;
  final VoidCallback onAddLabel;
  final VoidCallback onToggleMap;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 14,
      top: 120,
      bottom: 132,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlassIconButton(
                icon: Icons.threesixty_rounded,
                tooltip: autoRotate ? '停止自动环视' : '自动环视',
                active: autoRotate,
                onTap: onToggleAutoRotate,
              ),
              const SizedBox(height: 7),
              _GlassIconButton(
                icon: Icons.new_label_rounded,
                tooltip: '在当前视角添加标签',
                onTap: onAddLabel,
              ),
              const SizedBox(height: 7),
              _GlassIconButton(
                icon: Icons.map_rounded,
                tooltip: showMap ? '隐藏空间示意图' : '显示空间示意图',
                active: showMap,
                onTap: onToggleMap,
              ),
              if (hasNext && onNext != null) ...[
                const SizedBox(height: 7),
                _GlassIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: '按采集顺序前往下一点位',
                  onTap: onNext!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PointStrip extends StatelessWidget {
  const _PointStrip({
    required this.space,
    required this.currentPointId,
    required this.onSelect,
  });

  final VrSpace space;
  final String currentPointId;
  final ValueChanged<VrPoint> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.swipe_rounded,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 5),
                Text(
                  '滑动切换点位 · 当前 ${space.indexOfPoint(currentPointId) + 1}/${space.points.length}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: space.points.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final point = space.points[i];
                final selected = point.id == currentPointId;
                return GestureDetector(
                  onTap: () => onSelect(point),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 116,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: selected ? SpaceColors.accent : Colors.white12,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                            width: 54,
                            height: double.infinity,
                            child: _PointThumb(point: point),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: selected
                                      ? SpaceColors.accent
                                      : Colors.white38,
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                point.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 10.5,
                                  height: 1.25,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

class _PointThumb extends StatelessWidget {
  const _PointThumb({required this.point});

  final VrPoint point;

  @override
  Widget build(BuildContext context) {
    final file = File(point.thumbPath);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ThumbFallback(),
      );
    }
    return const _ThumbFallback();
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF23262E),
      child: Icon(
        Icons.panorama_photosphere_rounded,
        color: Colors.white24,
        size: 20,
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              color: Colors.white38,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重新载入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourOverlayLayer extends StatelessWidget {
  const _TourOverlayLayer({
    required this.hotspots,
    required this.labels,
    required this.lon,
    required this.lat,
    required this.fov,
    required this.onHotspotTap,
    required this.onLabelTap,
  });

  final List<VrHotspot> hotspots;
  final List<SpaceLabel> labels;
  final double lon;
  final double lat;
  final double fov;
  final ValueChanged<String> onHotspotTap;
  final ValueChanged<SpaceLabel> onLabelTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final children = <Widget>[];
        for (final label in labels) {
          final pos = _project(label.yawDeg, label.pitchDeg, size);
          if (pos == null) continue;
          final left = (pos.dx - 70).clamp(8.0, size.width - 148.0);
          children.add(
            Positioned(
              left: left,
              top: (pos.dy - 15).clamp(76.0, size.height - 160.0),
              width: 140,
              child: Center(
                child: GestureDetector(
                  onTap: () => onLabelTap(label),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: SpaceColors.accent.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: SpaceColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        for (final hotspot in hotspots) {
          final pos = _project(hotspot.yawDeg, hotspot.pitchDeg, size);
          if (pos == null) continue;
          final left = (pos.dx - 76).clamp(8.0, size.width - 160.0);
          children.add(
            Positioned(
              left: left,
              top: (pos.dy - 30).clamp(82.0, size.height - 210.0),
              width: 152,
              child: _HotspotMarker(
                hotspot: hotspot,
                onTap: () => onHotspotTap(hotspot.targetPointId),
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  Offset? _project(double yaw, double pitch, Size size) {
    final dy = normalizeDeg180(yaw - lon);
    final dp = pitch - lat;
    final halfFovX = fov * (size.width / size.height) / 2;
    final halfFovY = fov / 2;
    if (dy.abs() > halfFovX || dp.abs() > halfFovY) return null;
    final x = size.width / 2 + (dy / halfFovX) * (size.width / 2) * 0.86;
    final y = size.height / 2 - (dp / halfFovY) * (size.height / 2) * 0.86;
    return Offset(x, y);
  }
}

class _HotspotMarker extends StatelessWidget {
  const _HotspotMarker({required this.hotspot, required this.onTap});

  final VrHotspot hotspot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = hotspot.isNext;
    final color = accent ? SpaceColors.accent : Colors.white70;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(
              hotspot.isNext
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_back_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              hotspot.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}