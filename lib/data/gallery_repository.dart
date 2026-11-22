import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/pano_work.dart';

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  return GalleryRepository();
});

class GalleryRepository {
  Directory? _root;

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'pano_gallery'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final images = Directory(p.join(root.path, 'images'));
    final thumbs = Directory(p.join(root.path, 'thumbs'));
    if (!await images.exists()) await images.create(recursive: true);
    if (!await thumbs.exists()) await thumbs.create(recursive: true);
    _root = root;
    return root;
  }

  Future<File> get indexFile async {
    final root = await _ensureRoot();
    return File(p.join(root.path, 'index.json'));
  }

  Future<String> imagesDir() async {
    final root = await _ensureRoot();
    return p.join(root.path, 'images');
  }

  Future<String> thumbsDir() async {
    final root = await _ensureRoot();
    return p.join(root.path, 'thumbs');
  }

  Future<List<PanoWork>> loadAll() async {
    final file = await indexFile;
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PanoWork.fromJson(e as Map<String, dynamic>))
          .where((w) => File(w.imagePath).existsSync())
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<PanoWork> works) async {
    final file = await indexFile;
    final encoded = jsonEncode(works.map((e) => e.toJson()).toList());
    await file.writeAsString(encoded);
  }

  Future<void> upsert(PanoWork work) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.id == work.id);
    if (idx >= 0) {
      all[idx] = work;
    } else {
      all.insert(0, work);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    PanoWork? removed;
    all.removeWhere((e) {
      if (e.id == id) {
        removed = e;
        return true;
      }
      return false;
    });
    await saveAll(all);
    if (removed != null) {
      final img = File(removed!.imagePath);
      final thumb = File(removed!.thumbPath);
      if (await img.exists()) await img.delete();
      if (await thumb.exists()) await thumb.delete();
    }
  }
}
