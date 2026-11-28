abstract final class PanoConstants {
  static const maxCapturePoints = 14;
  static const vrCapturePointCount = 24;
  static const vrPointSpacingM = 2.6;
  static const stitchWidth2k = 2048;
  static const stitchHeight2k = 1024;
  static const stitchWidth4k = 4096;
  static const stitchHeight4k = 2048;
  static const defaultFov = 75.0;
  static const minFov = 40.0;
  static const maxFov = 110.0;
  static const autoLockHoldMs = 650;
  static const alignThresholdDeg = 12.0;
  static const rollWarnDeg = 8.0;

  // 拼接
  /// 相机主摄对角线视场角估计值。camera 插件不暴露焦距，
  /// 用典型手机主摄（约 80° 对角线）按实际照片宽高比换算水平/垂直视场。
  static const cameraDiagonalFovDeg = 80.0;
  static const autoLockStableRateDps = 45.0;
  static const autoLockExitMarginDeg = 8.0;
  static const autoLockMissToleranceMs = 280;
  static const brandName = 'PANO';
  static const brandAccent = '360';
  static const appTitle = 'PANO 360 Pro';

  // 巡检点位引导
  static const waypointArrivalRadiusM = 15.0;
  static const waypointMaxGpsAccuracyM = 30.0;
  static const waypointAlignEnterDeg = 10.0;
  static const waypointAlignExitDeg = 16.0;
  static const waypointAlignNearDeg = 30.0;
  static const compassInterferenceLowUt = 15.0;
  static const compassInterferenceHighUt = 110.0;
  static const compassStartupTimeout = Duration(milliseconds: 2500);
  static const compassSamplePublishMs = 60;
}
