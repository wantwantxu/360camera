import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/space_theme.dart';
import '../../domain/vr_space.dart';
import 'space_routes.dart';
import 'spaces_controller.dart';
import 'widgets/space_widgets.dart';

class SpacesHomePage extends ConsumerWidget {
  const SpacesHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spacesProvider);

    return Theme(
      data: buildSpaceTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: SpaceColors.bg,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: SpaceColors.accent,
              onRefresh: () => ref.read(spacesProvider.notifier).reload(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final horizontal = wide ? 32.0 : 18.0;
                  final columns = wide
                      ? 3
                      : constraints.maxWidth >= 350
                          ? 2
                          : 1;
                  final gap = wide ? 16.0 : 12.0;
                  final cardWidth = (constraints.maxWidth -
                          horizontal * 2 -
                          gap * (columns - 1)) /
                      columns;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(
                              onGuide: () => _openGuide(context),
                            ),
                            const SizedBox(height: 18),
                            _Hero(
                              onStart: () => _createSpace(context, ref),
                            ),
                            const SizedBox(height: 14),
                            _StatsStrip(state: state),
                            const SizedBox(height: 26),
                            SpaceSectionHeader(
                              title: '我的空间',
                              subtitle: state.loading
                                  ? '正在读取本地空间…'
                                  : '${state.spaces.length} 个空间 · ${state.spaces.fold<int>(0, (sum, e) => sum + e.points.length)} 个点位',
                              trailing: IconButton.filledTonal(
                                onPressed: () => _createSpace(context, ref),
                                style: IconButton.styleFrom(
                                  backgroundColor: SpaceColors.surface,
                                  foregroundColor: SpaceColors.ink,
                                  side: const BorderSide(color: SpaceColors.line),
                                ),
                                tooltip: '创建空间',
                                icon: const Icon(Icons.add_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (state.loading)
                              const _LoadingPanel()
                            else if (state.error != null)
                              _ErrorPanel(
                                message: state.error!,
                                onRetry: () => ref
                                    .read(spacesProvider.notifier)
                                    .reload(),
                              )
                            else if (state.spaces.isEmpty)
                              SpaceEmptyPanel(
                                onCreate: () => _createSpace(context, ref),
                                onGuide: () => _openGuide(context),
                              )
                            else
                              Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  for (final space in state.spaces)
                                    SizedBox(
                                      width: cardWidth,
                                      child: _SpaceCard(
                                        space: space,
                                        onTap: () => context.push(
                                          SpaceRoutes.detail(space.id),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 26),
                            const _FooterNote(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createSpace(BuildContext context, WidgetRef ref) async {
    final space = await showModalBottomSheet<VrSpace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateSpaceSheet(),
    );
    if (space != null && context.mounted) {
      context.push(SpaceRoutes.detail(space.id));
    }
  }

  void _openGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuideSheet(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onGuide});

  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SpaceColors.accent, Color(0xFFFF8A56)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: SpaceColors.accent.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.view_in_ar_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              PanoConstants.appTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '手机拍 VR · 空间采集',
              style: TextStyle(
                fontSize: 10,
                color: SpaceColors.inkMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: onGuide,
          tooltip: '拍摄教程',
          style: IconButton.styleFrom(
            backgroundColor: SpaceColors.surface,
            side: const BorderSide(color: SpaceColors.line),
          ),
          icon: const Icon(Icons.help_outline_rounded, size: 20),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 198,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF191B22), Color(0xFF262124)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F101218),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeroPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 12,
                        color: Color(0xFFFFA98B),
                      ),
                      SizedBox(width: 5),
                      Text(
                        '24 方向采集 · 自动拼接',
                        style: TextStyle(
                          color: Color(0xFFECD8D2),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  '用手机拍出\n整个空间',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: SpaceColors.ink,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        '开始拍摄',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '站到点位中央，跟随屏幕指示转动手机即可',
                        maxLines: 2,
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          SpaceColors.accent.withValues(alpha: 0.34),
          SpaceColors.accent.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.9, size.height * 0.18),
          radius: size.width * 0.55,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.11);
    final center = Offset(size.width * 0.86, size.height * 0.52);
    for (var i = 0; i < 9; i++) {
      final angle = -1.25 + i * 0.3;
      final end = center +
          Offset.fromDirection(angle, size.width * (0.22 + (i % 3) * 0.05));
      canvas.drawLine(center, end, line);
    }
    canvas.drawCircle(
      center,
      size.width * 0.15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      center,
      size.width * 0.08,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = SpaceColors.accent.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      center,
      2.5,
      Paint()..color = SpaceColors.accent.withValues(alpha: 0.9),
    );

    final grid = Paint()
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 1; i < 4; i++) {
      final y = size.height * (0.55 + i * 0.1);
      canvas.drawLine(Offset(size.width * 0.45, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.state});

  final SpacesState state;

  @override
  Widget build(BuildContext context) {
    final points =
        state.spaces.fold<int>(0, (sum, space) => sum + space.points.length);
    final labels =
        state.spaces.fold<int>(0, (sum, space) => sum + space.labelCount);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Row(
        children: [
          _stat('${state.spaces.length}', '空间'),
          _divider(),
          _stat('$points', '点位'),
          _divider(),
          _stat('$labels', '标签'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: SpaceColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 24, color: SpaceColors.line);
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({required this.space, required this.onTap});

  final VrSpace space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpaceColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SpaceColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SpaceCover(point: space.coverPoint, borderRadius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: SpaceCategoryBadge(
                        category: space.category,
                        light: true,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          space.points.isEmpty
                              ? '待拍摄'
                              : '${space.points.length} 点位',
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            space.points.isEmpty
                                ? '尚未采集，点击开始'
                                : formatSpaceDate(space.updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: SpaceColors.inkMuted,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: SpaceColors.inkMuted,
                        ),
                      ],
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

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceColors.line),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: SpaceColors.accent,
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpaceColors.line),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpaceColors.inkSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重新读取')),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 12, color: SpaceColors.inkMuted),
        SizedBox(width: 5),
        Flexible(
          child: Text(
            '所有空间与全景照片仅保存在本机；示意图基于拍摄顺序，非实测户型。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpaceColors.inkMuted,
              fontSize: 9.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: const BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
          child: Column(
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
                '手机拍 VR · 拍摄指南',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '无需专业设备。一个点位约 1–2 分钟，建议每个房间采集 1–3 个点位。',
                style: TextStyle(
                  color: SpaceColors.inkSecondary,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 22),
              const _GuideStep(
                index: '01',
                title: '站到空间中央',
                body: '保持手机竖直，尽量避开强逆光和镜面反射。每个点位保持身体位置不动。',
                icon: Icons.accessibility_new_rounded,
              ),
              const _GuideStep(
                index: '02',
                title: '跟随指示环采集 24 个方向',
                body: '缓慢转动手机，对准屏幕上的圆点后会自动拍摄。水平、仰拍、俯拍共三圈。',
                icon: Icons.threesixty_rounded,
              ),
              const _GuideStep(
                index: '03',
                title: '移动 2–3 米继续下一点位',
                body: '沿房间主要通道移动，避免原地重复。点位越连贯，漫游路径越自然。',
                icon: Icons.directions_walk_rounded,
              ),
              const _GuideStep(
                index: '04',
                title: '保存点位并进入 VR',
                body: '所有点位自动串联。可添加空间标签，拖动查看四周，点击入口热点切换点位。',
                icon: Icons.panorama_photosphere_rounded,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: SpaceColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SpaceColors.line),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: SpaceColors.inkMuted,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '室内定位不可靠，因此迷你地图与点位方位来自拍摄朝向和顺序，仅作导航示意，不代表实测户型。',
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: SpaceColors.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: SpaceColors.accent,
                  ),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.index,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String index;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFFFC9BB),
                height: 1,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: SpaceColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: SpaceColors.accentDark),
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
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: SpaceColors.inkSecondary,
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateSpaceSheet extends ConsumerStatefulWidget {
  const _CreateSpaceSheet();

  @override
  ConsumerState<_CreateSpaceSheet> createState() => _CreateSpaceSheetState();
}

class _CreateSpaceSheetState extends ConsumerState<_CreateSpaceSheet> {
  final _nameController = TextEditingController(text: '我的空间');
  var _category = SpaceCategory.residence;
  var _busy = false;
  var _nameTouched = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入空间名称')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final space = await ref.read(spacesProvider.notifier).createSpace(
            name: name,
            category: _category,
          );
      if (!mounted) return;
      Navigator.pop(context, space);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: SpaceColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
            child: Column(
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
                  '创建空间',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  '给这次全景采集起一个名字，稍后还可以修改。',
                  style: TextStyle(
                    fontSize: 12,
                    color: SpaceColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 24,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _nameTouched = true,
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  },
                  decoration: const InputDecoration(
                    labelText: '空间名称',
                    counterText: '',
                    prefixIcon: Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '空间类型',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SpaceColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in SpaceCategory.values)
                      _CategoryChip(
                        category: category,
                        selected: category == _category,
                        onTap: () {
                          setState(() {
                            _category = category;
                            if (!_nameTouched) {
                              _nameController.text = '我的${category.label}空间';
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SpaceColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.camera_alt_outlined,
                        size: 16,
                        color: SpaceColors.inkSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _category.hint,
                          style: const TextStyle(
                            color: SpaceColors.inkSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: SpaceColors.accent,
                        ),
                        child: Text(_busy ? '创建中…' : '创建并开始采集'),
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
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SpaceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? SpaceColors.accentSoft : SpaceColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? SpaceColors.accent : SpaceColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              spaceCategoryIcon(category),
              size: 14,
              color: selected ? SpaceColors.accentDark : SpaceColors.inkMuted,
            ),
            const SizedBox(width: 5),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? SpaceColors.accentDark : SpaceColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}