import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/inspection_task.dart';

final inspectionRepositoryProvider = Provider<InspectionRepository>((ref) {
  return InspectionRepository();
});

class InspectionRepository {
  static const _dataVersion = 1;

  Directory? _root;
  final _uuid = const Uuid();

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'pano_inspection'));
    if (!await root.exists()) await root.create(recursive: true);
    final refs = Directory(p.join(root.path, 'refs'));
    if (!await refs.exists()) await refs.create(recursive: true);
    _root = root;
    return root;
  }

  Future<File> get _dataFile async {
    final root = await _ensureRoot();
    return File(p.join(root.path, 'inspection_data.json'));
  }

  Future<String> refsDir() async {
    final root = await _ensureRoot();
    return p.join(root.path, 'refs');
  }

  /// Returns null when no data file exists yet. Corrupt files are moved aside
  /// (never silently overwritten) and null is returned so the caller can seed.
  Future<List<InspectionTask>?> loadTasks() async {
    final file = await _dataFile;
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic>
          ? decoded['tasks'] as List<dynamic>? ?? const []
          : decoded as List<dynamic>;
      return list
          .map((e) => InspectionTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      await _backupCorruptFile(file);
      return null;
    } on TypeError {
      await _backupCorruptFile(file);
      return null;
    }
  }

  Future<void> _backupCorruptFile(File file) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.copy('${file.path}.corrupt-$stamp');
      await file.delete();
    } catch (_) {
      // Keep the original file if the backup cannot be written.
    }
  }

  Future<void> saveTasks(List<InspectionTask> tasks) async {
    final file = await _dataFile;
    final payload = jsonEncode({
      'version': _dataVersion,
      'tasks': tasks.map((e) => e.toJson()).toList(),
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

  Future<String> saveReferencePhoto(Uint8List bytes, {String extension = 'jpg'}) async {
    var ext = extension.toLowerCase().replaceAll('.', '');
    if (!const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)) {
      ext = 'jpg';
    }
    final dir = await refsDir();
    final path = p.join(dir, '${_uuid.v4()}.$ext');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> deleteReferencePhoto(String? path) async {
    if (path == null) return;
    try {
      final dir = p.normalize(await refsDir());
      final full = p.normalize(p.absolute(path));
      if (!p.isWithin(dir, full)) return;
      final file = File(full);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Reference photo cleanup is best-effort.
    }
  }
}