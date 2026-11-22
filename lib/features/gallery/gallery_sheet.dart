import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/pano_colors.dart';
import '../../domain/pano_work.dart';
import '../session/pano_session.dart';
import '../../widgets/glass.dart';

Future<void> openGallerySheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _GallerySheet(),
  );
}

class _GallerySheet extends ConsumerWidget {
  const _GallerySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(panoSessionProvider.select((s) => s.gallery));
    final activeId = ref.watch(panoSessionProvider.select((s) => s.activeWorkId));

    return GlassPanel(
      borderRadius: 20,
      opacity: 0.94,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    '作品相册',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: PanoColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: gallery.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有作品，去拍摄一张吧',
                          style: TextStyle(color: PanoColors.textSecondary),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.5,
                        ),
                        itemCount: gallery.length,
                        itemBuilder: (context, i) {
                          final work = gallery[i];
                          return _GalleryTile(
                            work: work,
                            active: work.id == activeId,
                            onTap: () {
                              ref.read(panoSessionProvider.notifier).loadWork(work.id);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.work,
    required this.active,
    required this.onTap,
  });

  final PanoWork work;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? PanoColors.amber : PanoColors.borderSubtle,
            width: active ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(work.thumbPath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: PanoColors.bgCard),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
