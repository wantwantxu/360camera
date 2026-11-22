# PANO 360 Pro

专业全景相机与预览工坊（Flutter · Android / iOS）。

## 功能

- 14 点位三层环带引导拍摄（水平 8 / 仰拍 3 / 俯拍 3）
- 陀螺仪云台 / 虚拟拖拽云台、自动对准连拍、AR HUD、迷你雷达
- 姿态投影 equirectangular 拼接（对齐 HTML 原型算法）
- 球体预览、小行星视角、自动巡航、体感环顾、五款滤镜
- 本地作品相册、导入、2K/4K JPEG/PNG 导出与分享

## 运行

```bash
flutter pub get
flutter run
```

真机调试建议使用物理设备（相机 + 陀螺仪）。无相机时可选用「日落海滩 / 赛博都市 / 星空雪山」演示源，或点「一键完成全部点位」。

Android Debug APK：

```bash
flutter build apk --debug
# 输出: build/app/outputs/flutter-apk/app-debug.apk
```

国内网络可设置：

```bash
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 权限

- 相机：拍摄点位
- 相册：导入 / 导出
- 运动传感器：陀螺仪云台与体感环顾

## 结构

- `lib/features/capture` — 14 点矩阵、姿态投影拼接
- `lib/features/preview` — 球体 / 小行星预览与滤镜
- `lib/features/gallery` / `export` — 本地作品库与导出
- `lib/features/session` — 全局会话状态（Riverpod）
