import 'capture_point.dart';

/// Standard 14-point spherical capture matrix (matches HTML prototype).
List<CapturePoint> createStandard14Points() {
  final pts = <CapturePoint>[];

  for (var i = 0; i < 8; i++) {
    pts.add(
      CapturePoint(
        id: 'H-0${i + 1}',
        ring: CaptureRing.mid,
        yaw: i * 45.0,
        pitch: 0,
      ),
    );
  }

  const upperYaws = [0.0, 120.0, 240.0];
  for (var i = 0; i < upperYaws.length; i++) {
    pts.add(
      CapturePoint(
        id: 'U-0${i + 1}',
        ring: CaptureRing.upper,
        yaw: upperYaws[i],
        pitch: 45,
      ),
    );
  }

  const lowerYaws = [60.0, 180.0, 300.0];
  for (var i = 0; i < lowerYaws.length; i++) {
    pts.add(
      CapturePoint(
        id: 'D-0${i + 1}',
        ring: CaptureRing.lower,
        yaw: lowerYaws[i],
        pitch: -45,
      ),
    );
  }

  return pts;
}
