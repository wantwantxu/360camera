import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pano_colors.dart';
import '../../../core/utils/compass_utils.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../domain/inspection_point.dart';
import '../inspection_controller.dart';

Future<bool?> openWaypointEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  InspectionPoint? point,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _WaypointEditorSheet(point: point),
  );
}

class _WaypointEditorSheet extends ConsumerStatefulWidget {
  const _WaypointEditorSheet({this.point});

  final InspectionPoint? point;

  @override
  ConsumerState<_WaypointEditorSheet> createState() => _WaypointEditorSheetState();
}

class _WaypointEditorSheetState extends ConsumerState<_WaypointEditorSheet> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _instructions;
  late final TextEditingController _directionName;
  late final TextEditingController _azimuth;
  late final TextEditingController _pitch;
  late final TextEditingController _radius;

  double? _latitude;
  double? _longitude;
  double? _accuracyM;

  String? _referencePath;
  Uint8List? _pickedBytes;
  String? _pickedExtension;
  bool _removeReference = false;

  bool _saving = false;
  bool _locating = false;
  bool _measuringHeading = false;
  String? _error;

  bool get _isEditing => widget.point != null;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _instructions = TextEditingController(text: p?.instructions ?? '');
    _directionName = TextEditingController(text: p?.directionName ?? '');
    _azimuth = TextEditingController(
      text: p?.targetAzimuthDeg == null ? '' : p!.targetAzimuthDeg!.toStringAsFixed(1),
    );
    _pitch = TextEditingController(text: (p?.targetPitchDeg ?? 0).toStringAsFixed(1));
    _radius = TextEditingController(text: (p?.arrivalRadiusM ?? 15).toStringAsFixed(0));
    _latitude = p?.latitude;
    _longitude = p?.longitude;
    _referencePath = p?.referenceImagePath;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    _directionName.dispose();
    _azimuth.dispose();
    _pitch.dispose();
    _radius.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inspection = ref.watch(inspectionProvider);
    final task = inspection.activeTask;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasReference = _pickedBytes != null ||
        (!_removeReference && _referencePath != null);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: PanoColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: PanoColors.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? '编辑点位' : '新建点位',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: PanoColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              if (task != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.assignment_outlined, size: 13, color: PanoColors.cyan),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PanoColors.textMuted, fontSize: 11),
                        ),
                      ),
                      if (task.isSample)
                        const Text(
                          '示例任务 · 请填写真实点位数据',
                          style: TextStyle(color: PanoColors.cyan, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 108,
                            child: _field('点位编号', _code, hint: '如 DB-01'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field('点位名称', _name, hint: '如 坝顶观测点'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _field('点位描述', _description, hint: '现场位置说明', maxLines: 2),
                      const SizedBox(height: 12),
                      _field('拍摄说明', _instructions, hint: '取景要求、注意事项', maxLines: 3),
                      const SizedBox(height: 12),
                      _field(
                        '目标方向说明',
                        _directionName,
                        hint: '如 朝向上游闸门',
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('目标方向'),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              '目标方位角（0–360°）',
                              _azimuth,
                              hint: '如 135',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 116,
                            child: _field(
                              '目标俯仰角',
                              _pitch,
                              hint: '0',
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _smallAction(
                            icon: _measuringHeading
                                ? null
                                : Icons.explore_outlined,
                            label: _measuringHeading ? '读取中…' : '使用当前朝向',
                            onTap: _measuringHeading ? null : _useCurrentHeading,
                          ),
                          const SizedBox(width: 8),
                          _smallAction(
                            icon: Icons.clear,
                            label: '清除方向',
                            onTap: () => setState(() {
                              _azimuth.text = '';
                              _directionName.text = '';
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('目标位置'),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: PanoColors.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _latitude != null && _longitude != null
                                  ? formatCoordinates(_latitude!, _longitude!)
                                  : '未设置坐标（无法计算现场距离）',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: _latitude != null
                                    ? PanoColors.textPrimary
                                    : PanoColors.textMuted,
                              ),
                            ),
                            if (_accuracyM != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '采集精度 ±${_accuracyM!.round()} m（仅用于记录，可稍后在现场重新采集）',
                                  style: const TextStyle(
                                    color: PanoColors.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _smallAction(
                                  icon: _locating ? null : Icons.my_location,
                                  label: _locating ? '定位中…' : '使用当前位置',
                                  onTap: _locating ? null : _useCurrentPosition,
                                ),
                                const SizedBox(width: 8),
                                _smallAction(
                                  icon: Icons.clear,
                                  label: '清除坐标',
                                  onTap: () => setState(() {
                                    _latitude = null;
                                    _longitude = null;
                                    _accuracyM = null;
                                  }),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _sectionTitle('到达判定半径（米）')),
                          SizedBox(
                            width: 90,
                            child: _field(
                              '',
                              _radius,
                              hint: '15',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('参考照片'),
                      const SizedBox(height: 6),
                      if (hasReference)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: _pickedBytes != null
                                ? Image.memory(_pickedBytes!, fit: BoxFit.cover)
                                : Image.file(
                                    File(_referencePath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: PanoColors.bgCard,
                                      alignment: Alignment.center,
                                      child: const Text(
                                        '参考照片文件缺失',
                                        style: TextStyle(color: PanoColors.rose, fontSize: 12),
                                      ),
                                    ),
                                  ),
                          ),
                        )
                      else
                        Container(
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: PanoColors.borderSubtle),
                          ),
                          child: const Text(
                            '暂无参考照片\n不显示虚构参考图，可导入现场实拍图',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: PanoColors.textMuted,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _smallAction(
                            icon: Icons.add_photo_alternate_outlined,
                            label: hasReference ? '更换参考照片' : '选择参考照片',
                            onTap: _pickReference,
                          ),
                          const SizedBox(width: 8),
                          if (hasReference)
                            _smallAction(
                              icon: Icons.delete_outline,
                              label: '移除',
                              danger: true,
                              onTap: () => setState(() {
                                _pickedBytes = null;
                                _pickedExtension = null;
                                _removeReference = true;
                              }),
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(color: PanoColors.rose, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PanoColors.amber,
                          foregroundColor: PanoColors.bgBase,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? '保存中…' : '保存点位',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _saving ? null : _delete,
                          child: const Text(
                            '删除此点位',
                            style: TextStyle(color: PanoColors.rose, fontSize: 12),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        '方位角以磁北为基准，受当地磁偏角与磁场干扰影响；坐标仅在拍摄时用于计算距离，不会上传。',
                        style: TextStyle(
                          color: PanoColors.textMuted,
                          fontSize: 10,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: PanoColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty) ...[
          _sectionTitle(label),
          const SizedBox(height: 4),
        ],
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 13, color: PanoColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: PanoColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: PanoColors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: PanoColors.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: PanoColors.amber),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallAction({
    IconData? icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? PanoColors.rose : PanoColors.cyan;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: PanoColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(icon, size: 14, color: onTap == null ? PanoColors.textMuted : color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? PanoColors.textMuted : color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useCurrentHeading() async {
    setState(() => _measuringHeading = true);
    final heading = await ref.read(inspectionProvider.notifier).measureHeadingForEditor();
    if (!mounted) return;
    setState(() {
      _measuringHeading = false;
      if (heading != null) {
        _azimuth.text = heading.toStringAsFixed(1);
        if (_directionName.text.trim().isEmpty) {
          _directionName.text = '朝向${compassLabel(heading)}（现场采集）';
        }
      }
    });
  }

  Future<void> _useCurrentPosition() async {
    setState(() => _locating = true);
    final pos = await ref.read(inspectionProvider.notifier).acquirePositionForEditor();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _accuracyM = pos.accuracy;
      }
    });
  }

  Future<void> _pickReference() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = '无法读取所选图片');
        return;
      }
      if (!mounted) return;
      setState(() {
        _pickedBytes = bytes;
        _pickedExtension = file.extension;
        _removeReference = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '选择参考照片失败：$e');
    }
  }

  Future<void> _save() async {
    final task = ref.read(inspectionProvider).activeTask;
    if (task == null) {
      setState(() => _error = '请先选择巡检任务');
      return;
    }
    if (_code.text.trim().isEmpty) {
      setState(() => _error = '请填写点位编号');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写点位名称');
      return;
    }
    double? azimuth;
    if (_azimuth.text.trim().isNotEmpty) {
      azimuth = double.tryParse(_azimuth.text.trim());
      if (azimuth == null || azimuth < 0 || azimuth >= 360) {
        setState(() => _error = '目标方位角需在 0–360° 之间');
        return;
      }
    }
    final pitch = double.tryParse(_pitch.text.trim()) ?? 0;
    if (pitch < -90 || pitch > 90) {
      setState(() => _error = '目标俯仰角需在 -90–90° 之间');
      return;
    }
    final radius = double.tryParse(_radius.text.trim()) ?? 15;
    if (radius <= 0 || radius > 500) {
      setState(() => _error = '到达判定半径需在 1–500 米之间');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final controller = ref.read(inspectionProvider.notifier);
    final previousReference = widget.point?.referenceImagePath;
    String? referencePath = _removeReference ? null : _referencePath;
    if (_pickedBytes != null) {
      final stored = await controller.storeReferencePhoto(
        _pickedBytes!,
        extension: _pickedExtension ?? 'jpg',
      );
      if (!mounted) return;
      if (stored == null) {
        setState(() => _saving = false);
        return;
      }
      referencePath = stored;
    }

    bool ok;
    if (_isEditing) {
      final updated = widget.point!.copyWith(
        code: _code.text.trim(),
        name: _name.text.trim(),
        description: _description.text.trim(),
        instructions: _instructions.text.trim(),
        directionName: _directionName.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        targetAzimuthDeg: azimuth,
        targetPitchDeg: pitch,
        arrivalRadiusM: radius,
        referenceImagePath: referencePath,
      );
      ok = await controller.updatePoint(
        updated,
        replacedReferencePath: previousReference,
      );
    } else {
      final added = await controller.addPoint(
        code: _code.text.trim(),
        name: _name.text.trim(),
        description: _description.text.trim(),
        instructions: _instructions.text.trim(),
        directionName: _directionName.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        targetAzimuthDeg: azimuth,
        targetPitchDeg: pitch,
        arrivalRadiusM: radius,
        referenceImagePath: referencePath,
      );
      ok = added != null;
    }

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = '保存失败，请查看提示后重试';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final point = widget.point;
    if (point == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PanoColors.bgCard,
        title: const Text('删除点位'),
        content: Text('确认删除 ${point.code} ${point.name}？历史记录将一并移除，已保存的全景作品仍保留在相册。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: PanoColors.rose)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await ref.read(inspectionProvider.notifier).deletePoint(point.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }
}