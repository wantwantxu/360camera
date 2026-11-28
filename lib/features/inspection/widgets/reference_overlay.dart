import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../domain/inspection_point.dart';
import '../../../widgets/glass.dart';
import '../inspection_controller.dart';
import '../inspection_state.dart';

class ReferenceCompareOverlay extends ConsumerWidget {
  const ReferenceCompareOverlay({
    super.key,
    required this.point,
    required this.mode,
    required this.opacity,
  });

  final InspectionPoint point;
  final ReferenceCompareMode mode;
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(inspectionProvider.notifier);
    final path = point.referenceImagePath;
    if (path == null) return const SizedBox.shrink();

    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: PanoColors.bgBase,
        child: Center(
          child: Text(
            '参考照片文件缺失\n请在点位详情中重新添加',
            textAlign: TextAlign.center,
            style: TextStyle(color: PanoColors.rose, fontSize: 12, height: 1.5),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        if (mode == ReferenceCompareMode.split) ...[
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: MediaQuery.sizeOf(context).width / 2,
            child: IgnorePointer(child: image),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: MediaQuery.sizeOf(context).width / 2,
            width: 1,
            child: const IgnorePointer(
              child: ColoredBox(color: PanoColors.amber),
            ),
          ),
        ] else
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(opacity: opacity, child: image),
            ),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 64,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: GlassPill(
                  color: const Color(0xE009090B),
                  borderColor: PanoColors.amber.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.compare, size: 15, color: PanoColors.amber),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '参考对齐 · ${point.code} ${point.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Text(
                        '参考照片 · 非实时',
                        style: TextStyle(color: PanoColors.textMuted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassPill(
                onTap: notifier.closeReferenceOverlay,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: const Icon(Icons.close, size: 16, color: PanoColors.textSecondary),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 20,
          child: SafeArea(
            top: false,
            child: GlassPanel(
              borderRadius: 16,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _modeButton(
                        '残影叠加',
                        mode == ReferenceCompareMode.ghost,
                        () => notifier.setReferenceMode(ReferenceCompareMode.ghost),
                      ),
                      const SizedBox(width: 8),
                      _modeButton(
                        '左右分屏',
                        mode == ReferenceCompareMode.split,
                        () => notifier.setReferenceMode(ReferenceCompareMode.split),
                      ),
                      const Spacer(),
                      Text(
                        mode == ReferenceCompareMode.split ? '左侧参考 / 右侧实时' : '叠加透明度',
                        style: const TextStyle(color: PanoColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                  if (mode == ReferenceCompareMode.ghost) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.opacity, size: 15, color: PanoColors.textSecondary),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: PanoColors.amber,
                              inactiveTrackColor: Colors.white12,
                              thumbColor: PanoColors.amber,
                              overlayShape: SliderComponentShape.noOverlay,
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: opacity,
                              min: 0.15,
                              max: 0.85,
                              onChanged: notifier.setReferenceOpacity,
                            ),
                          ),
                        ),
                        Text(
                          '${(opacity * 100).round()}%',
                          style: const TextStyle(
                            color: PanoColors.amber,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    '将参考照片中的标志物与实时画面对齐后，关闭对比并开始 360° 拍摄。参考照片不包含实时位置信息。',
                    style: TextStyle(
                      color: PanoColors.textMuted,
                      fontSize: 10,
                      height: 1.4,
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

  Widget _modeButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? PanoColors.amberDim : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? PanoColors.amber : PanoColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? PanoColors.amber : PanoColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}