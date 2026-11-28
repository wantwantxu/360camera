import '../domain/inspection_point.dart';
import '../domain/inspection_task.dart';

/// 仅用于首次启动时演示巡检流程的示例数据。
///
/// 示例点位刻意不包含经纬度和参考照片，避免伪造真实定位与现场影像；
/// 用户可在点位编辑器中填入当前位置坐标、真实方位角和本机参考照片。
InspectionTask buildSampleInspectionTask() {
  final now = DateTime.now();
  return InspectionTask(
    id: 'task-sample-dam-inspection',
    title: '水库大坝巡检（示例）',
    description: '演示「点位定位 → 位置确认 → 方向引导 → 360°拍摄 → 结果确认」完整流程。'
        '示例数据不含真实坐标与照片，请在点位管理中补充现场数据后使用。',
    createdAt: now,
    isSample: true,
    points: [
      InspectionPoint(
        id: 'point-sample-01',
        code: 'DB-01',
        name: '坝顶观测点01',
        description: '坝顶西侧起点，护栏内侧安全区域。',
        instructions: '面向坝顶闸门方向站立，保持机身竖直，确认四周无遮挡后开始拍摄。',
        directionName: '朝向上游闸门',
        targetAzimuthDeg: 45,
        targetPitchDeg: 0,
      ),
      InspectionPoint(
        id: 'point-sample-02',
        code: 'DB-02',
        name: '坝顶观测点02',
        description: '坝顶中部，坝体与溢洪道交界处。',
        instructions: '面向坝体迎水面，注意将溢洪道结构置于画面参考位置。',
        directionName: '朝向坝体迎水面',
        targetAzimuthDeg: 180,
        targetPitchDeg: 0,
      ),
      InspectionPoint(
        id: 'point-sample-03',
        code: 'DB-03',
        name: '坝顶观测点03',
        description: '坝顶东侧指定位置，护栏内侧。',
        instructions: '朝向下游拍摄，以闸门与坝体轮廓作为参考物对齐。',
        directionName: '朝向下游',
        targetAzimuthDeg: 135,
        targetPitchDeg: 0,
      ),
    ],
  );
}