import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/angle_utils.dart';
import '../../data/space_repository.dart';
import '../../domain/pano_work.dart';
import '../../domain/vr_space.dart';

final spacesProvider =
    StateNotifierProvider<SpacesController, SpacesState>((ref) {
  return SpacesController(ref.watch(spaceRepositoryProvider));
});

class SpacesState {
  const SpacesState({
    this.loading = true,
    this.spaces = const [],
    this.error,
  });

  final bool loading;
  final List<VrSpace> spaces;
  final String? error;

  VrSpace? byId(String? id) {
    if (id == null) return null;
    for (final space in spaces) {
      if (space.id == id) return space;
    }
    return null;
  }

  SpacesState copyWith({
    bool? loading,
    List<VrSpace>? spaces,
    Object? error = _sentinel,
  }) {
    return SpacesState(
      loading: loading ?? this.loading,
      spaces: spaces ?? this.spaces,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class SpacesController extends StateNotifier<SpacesState> {
  SpacesController(this._repo) : super(const SpacesState()) {
    _load();
  }

  final SpaceRepository _repo;
  final _uuid = const Uuid();

  Future<void> _load() async {
    try {
      final spaces = await _repo.loadAll();
      state = SpacesState(loading: false, spaces: spaces);
    } catch (e) {
      state = SpacesState(loading: false, error: '空间数据读取失败：$e');
    }
  }

  Future<void> reload() async {
    state = state.copyWith(loading: true, error: null);
    await _load();
  }

  Future<VrSpace> createSpace({
    required String name,
    required SpaceCategory category,
  }) async {
    if (state.loading) {
      throw StateError('本地空间仍在读取，请稍候');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('请输入空间名称');
    final now = DateTime.now();
    final space = VrSpace(
      id: _uuid.v4(),
      name: trimmed,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
    await _commit(space);
    return space;
  }

  Future<void> renameSpace(String spaceId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('空间名称不能为空');
    final space = _requireSpace(spaceId);
    await _commit(space.copyWith(name: trimmed, updatedAt: DateTime.now()));
  }

  Future<void> deleteSpace(String spaceId) async {
    final next = state.spaces.where((e) => e.id != spaceId).toList();
    await _repo.saveAll(next);
    state = state.copyWith(spaces: next, error: null);
    await _repo.deleteSpaceMedia(spaceId);
  }

  Future<VrPoint> addPointFromWork({
    required String spaceId,
    required PanoWork work,
    required String name,
    double? headingDeg,
  }) async {
    final pointId = _uuid.v4();
    final media = await _repo.copyWorkMedia(
      spaceId: spaceId,
      pointId: pointId,
      work: work,
    );
    return _addPoint(
      spaceId: spaceId,
      pointId: pointId,
      name: name,
      media: media,
      headingDeg: headingDeg,
      source: work.source,
      workId: work.id,
    );
  }

  Future<VrPoint> addPointFromImage({
    required String spaceId,
    required Uint8List bytes,
    required String name,
  }) async {
    final pointId = _uuid.v4();
    final media = await _repo.importImageBytes(
      spaceId: spaceId,
      pointId: pointId,
      bytes: bytes,
    );
    return _addPoint(
      spaceId: spaceId,
      pointId: pointId,
      name: name,
      media: media,
      headingDeg: null,
      source: 'import',
    );
  }

  Future<VrPoint> _addPoint({
    required String spaceId,
    required String pointId,
    required String name,
    required SpaceMedia media,
    required double? headingDeg,
    required String source,
    String? workId,
  }) async {
    final space = _requireSpace(spaceId);
    final trimmed = name.trim();
    final position = nextVrPointPosition(space, headingDeg: headingDeg);
    final point = VrPoint(
      id: pointId,
      name: trimmed.isEmpty ? '点位 ${space.points.length + 1}' : trimmed,
      imagePath: media.imagePath,
      thumbPath: media.thumbPath,
      width: media.width,
      height: media.height,
      headingDeg: headingDeg,
      mapX: position.x,
      mapY: position.y,
      createdAt: DateTime.now(),
      source: source,
      workId: workId,
    );
    final updated = space.copyWith(
      points: [...space.points, point],
      coverPointId: space.coverPointId ?? point.id,
      updatedAt: DateTime.now(),
    );
    await _commit(updated);
    return point;
  }

  Future<void> renamePoint(
    String spaceId,
    String pointId,
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('点位名称不能为空');
    final space = _requireSpace(spaceId);
    final points = space.points
        .map((e) => e.id == pointId ? e.copyWith(name: trimmed) : e)
        .toList();
    await _commit(space.copyWith(points: points, updatedAt: DateTime.now()));
  }

  Future<void> removePoint(String spaceId, String pointId) async {
    final space = _requireSpace(spaceId);
    final points = space.points.where((e) => e.id != pointId).toList();
    var coverId = space.coverPointId;
    if (coverId == pointId) coverId = points.isEmpty ? null : points.first.id;
    await _commit(
      space.copyWith(
        points: points,
        coverPointId: coverId,
        updatedAt: DateTime.now(),
      ),
    );
    await _repo.deletePointMedia(spaceId, pointId);
  }

  Future<void> setCover(String spaceId, String pointId) async {
    final space = _requireSpace(spaceId);
    await _commit(
      space.copyWith(coverPointId: pointId, updatedAt: DateTime.now()),
    );
  }

  Future<SpaceLabel> addLabel({
    required String spaceId,
    required String pointId,
    required String text,
    required double yawDeg,
    required double pitchDeg,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const FormatException('标签内容不能为空');
    final space = _requireSpace(spaceId);
    final label = SpaceLabel(
      id: _uuid.v4(),
      text: trimmed,
      yawDeg: normalizeDeg360(yawDeg),
      pitchDeg: pitchDeg.clamp(-85.0, 85.0),
    );
    final points = space.points.map((point) {
      if (point.id != pointId) return point;
      return point.copyWith(labels: [...point.labels, label]);
    }).toList();
    await _commit(space.copyWith(points: points, updatedAt: DateTime.now()));
    return label;
  }

  Future<void> removeLabel(
    String spaceId,
    String pointId,
    String labelId,
  ) async {
    final space = _requireSpace(spaceId);
    final points = space.points.map((point) {
      if (point.id != pointId) return point;
      return point.copyWith(
        labels: point.labels.where((e) => e.id != labelId).toList(),
      );
    }).toList();
    await _commit(space.copyWith(points: points, updatedAt: DateTime.now()));
  }

  VrSpace _requireSpace(String spaceId) {
    final space = state.byId(spaceId);
    if (space == null) throw StateError('空间不存在或已被删除');
    return space;
  }

  Future<void> _commit(VrSpace updated) async {
    final spaces = [
      updated,
      ...state.spaces.where((e) => e.id != updated.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _repo.saveAll(spaces);
    state = SpacesState(loading: false, spaces: spaces);
  }
}