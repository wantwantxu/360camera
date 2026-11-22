import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/pano_colors.dart';
import '../../domain/export_options.dart';
import '../session/pano_session.dart';
import '../../widgets/glass.dart';

Future<void> openExportSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ExportSheet(),
  );
}

class _ExportSheet extends ConsumerWidget {
  const _ExportSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opts = ref.watch(panoSessionProvider.select((s) => s.exportOptions));
    final exporting = ref.watch(panoSessionProvider.select((s) => s.isExporting));
    final session = ref.watch(panoSessionProvider);
    final notifier = ref.read(panoSessionProvider.notifier);

    return GlassPanel(
      borderRadius: 20,
      opacity: 0.95,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('导出全景', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: PanoColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _SectionLabel('类型'),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    selected: opts.type == ExportType.equirectangular,
                    title: '等距柱状',
                    subtitle: '完整 360°',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(type: ExportType.equirectangular),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Choice(
                    selected: opts.type == ExportType.snapshot,
                    title: '当前视角',
                    subtitle: '平面快照',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(type: ExportType.snapshot),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('分辨率'),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    selected: opts.resolution == ExportResolution.res2k,
                    title: '2K',
                    subtitle: '2048×1024',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(resolution: ExportResolution.res2k),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Choice(
                    selected: opts.resolution == ExportResolution.res4k,
                    title: '4K',
                    subtitle: '4096×2048',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(resolution: ExportResolution.res4k),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('格式'),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    selected: opts.format == ExportFormat.jpeg,
                    title: 'JPEG',
                    subtitle: '体积更小',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(format: ExportFormat.jpeg),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Choice(
                    selected: opts.format == ExportFormat.png,
                    title: 'PNG',
                    subtitle: '无损质量',
                    onTap: () => notifier.updateExportOptions(
                      opts.copyWith(format: ExportFormat.png),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassPill(
              onTap: () => notifier.updateExportOptions(
                opts.copyWith(includeWatermark: !opts.includeWatermark),
              ),
              color: opts.includeWatermark ? PanoColors.amberDim : PanoColors.bgPill,
              borderColor: opts.includeWatermark
                  ? PanoColors.amber.withValues(alpha: 0.45)
                  : PanoColors.borderSubtle,
              child: Row(
                children: [
                  Icon(
                    opts.includeWatermark ? Icons.toggle_on : Icons.toggle_off,
                    color: opts.includeWatermark ? PanoColors.amber : PanoColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    opts.includeWatermark ? '水印：开' : '水印：关',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PanoColors.amber,
                foregroundColor: PanoColors.bgBase,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: exporting
                  ? null
                  : () async {
                      await notifier.exportCurrent(
                        snapshotLon: session.yaw,
                        snapshotLat: session.pitch,
                        snapshotFov: session.fov,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
              child: Text(
                exporting ? '正在导出…' : '立即生成并下载全景文件',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(color: PanoColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? PanoColors.amberDim : PanoColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? PanoColors.amber : PanoColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: PanoColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
