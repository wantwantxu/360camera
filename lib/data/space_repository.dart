import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/pano_thumbnail.dart';
import '../domain/pano_work.dart';
import '../domain/vr_space.dart';

final spaceRepositoryProvider = Provider<SpaceRepository>((ref) {
  return SpaceRepository();
});

class SpaceMedia {
  const SpaceMedia({
    required this.imagePath,
    required this.thumbPath,
    required this.width,
    required this.height,
  });

  final String imagePath;
  final String thumbPath;
  final int width;
  final int height;
}

class SpaceRepository {
  static const _dataVersion = 1;

  Directory? _root;

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'pano_spaces'));
    if (!await root.exists()) await root.create(recursive: true);
    _root = root;
    return root;
  }

  Future<File> get _dataFile async {
    final root = await _ensureRoot();
    return File(p.join(root.path, 'spaces.json'));
  }

  Future<String> _spaceMediaDir(String spaceId) async {
    final root = await _ensureRoot();
    final dir = Directory(p.join(root.path, 'media', spaceId));
    if (!await dir.exists()) await dir.create(recursive: true);
    final thumbs = Directory(p.join(dir.path, 'thumbs'));
    if (!await thumbs.exists()) await thumbs.create(recursive: true);
    return dir.path;
  }

  Future<List<VrSpace>> loadAll() async {
    final file = await _dataFile;
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic>
          ? decoded['spaces'] as List<dynamic>? ?? const []
          : decoded as List<dynamic>;
      final spaces = list
          .map((e) => VrSpace.fromJson(e as Map<String, dynamic>))
          .toList();
      spaces.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return spaces;
    } on FormatException {
      await _backupCorruptFile(file);
      return [];
    } on TypeError {
      await _backupCorruptFile(file);
      return [];
    }
  }

  Future<void> _backupCorruptFile(File file) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.copy('${file.path}.corrupt-$stamp');
      await file.delete();
    } catch (_) {
      // Keep the original file when the backup cannot be written.
    }
  }

  Future<void> saveAll(List<VrSpace> spaces) async {
    final file = await _dataFile;
    final payload = jsonEncode({
      'version': _dataVersion,
      'spaces': spaces.map((e) => e.toJson()).toList(),
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  Future<SpaceMedia> copyWorkMedia({
    required String spaceId,
    required String pointId,
    required PanoWork work,
  }) async {
    final dir = await _spaceMediaDir(spaceId);
    final image = File(work.imagePath);
    if (!await image.exists()) {
      throw const FileSystemException('全景文件不存在');
    }
    final imagePath = p.join(dir, '$pointId.jpg');
    final thumbPath = p.join(dir, 'thumbs', '$pointId.jpg');
    await image.copy(imagePath);

    try {
      final decoded = img.decodeImage(await image.readAsBytes());
      if (decoded == null) throw const FormatException('无法解析全景图片');
      await File(thumbPath).writeAsBytes(
        createPerspectiveThumbnail(decoded),
        flush: true,
      );
    } catch (_) {
      final thumb = File(work.thumbPath);
      if (!await thumb.exists()) rethrow;
      await thumb.copy(thumbPath);
    }

    return SpaceMedia(
      imagePath: imagePath,
      thumbPath: thumbPath,
      width: work.width,
      height: work.height,
    );
  }

  Future<SpaceMedia> importImageBytes({
    required String spaceId,
    required String pointId,
    required Uint8List bytes,
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('不支持的图片格式');
    final dir = await _spaceMediaDir(spaceId);
    final imagePath = p.join(dir, '$pointId.jpg');
    final thumbPath = p.join(dir, 'thumbs', '$pointId.jpg');
    await File(imagePath).writeAsBytes(
      img.encodeJpg(decoded, quality: 92),
      flush: true,
    );
    await File(thumbPath).writeAsBytes(
      createPerspectiveThumbnail(decoded),
      flush: true,
    );
    return SpaceMedia(
      imagePath: imagePath,
      thumbPath: thumbPath,
      width: decoded.width,
      height: decoded.height,
    );
  }

  Future<void> deleteSpaceMedia(String spaceId) async {
    try {
      final root = await _ensureRoot();
      final mediaRoot = p.normalize(p.join(root.path, 'media'));
      final target = p.normalize(p.join(mediaRoot, spaceId));
      if (!p.isWithin(mediaRoot, target)) return;
      final dir = Directory(target);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Orphaned media is preferable to deleting unrelated files.
    }
  }

  Future<void> deletePointMedia(String spaceId, String pointId) async {
    try {
      final root = await _ensureRoot();
      final mediaRoot = p.normalize(p.join(root.path, 'media', spaceId));
      for (final path in [
        p.normalize(p.join(mediaRoot, '$pointId.jpg')),
        p.normalize(p.join(mediaRoot, 'thumbs', '$pointId.jpg')),
      ]) {
        if (!p.isWithin(mediaRoot, path)) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Media cleanup is best-effort.
    }
  }
}