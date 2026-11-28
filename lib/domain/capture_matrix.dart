import 'capture_point.dart';

/// Standard 14-point spherical capture matrix (matches HTML prototype).
///
/// [yawOffsetDeg] rotates the whole matrix so the first horizontal point
/// matches the current camera direction when an inspection capture starts.
List<CapturePoint> createStandard14Points({double yawOffsetDeg = 0}) {
  final pts = <CapturePoint>[];

  for (var i = 0; i < 8; i++) {
    pts.add(
      CapturePoint(
        id: 'H-0${i + 1}',
        ring: CaptureRing.mid,
        yaw: (i * 45.0 + yawOffsetDeg) % 360.0,
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
        yaw: (upperYaws[i] + yawOffsetDeg) % 360.0,
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
        yaw: (lowerYaws[i] + yawOffsetDeg) % 360.0,
        pitch: -45,
      ),
    );
  }

  return pts;
}

/// 24-frame matrix used by the mobile VR capture flow (8 × 3 rings).
///
/// Upper/lower rings are staggered by 22.5° so seams between equirectangular
/// patches do not line up across the horizon.
List<CapturePoint> createVr24Points({double yawOffsetDeg = 0}) {
  final pts = <CapturePoint>[];

  for (var i = 0; i < 8; i++) {
    pts.add(
      CapturePoint(
        id: 'H-${(i + 1).toString().padLeft(2, '0')}',
        ring: CaptureRing.mid,
        yaw: (i * 45.0 + yawOffsetDeg) % 360.0,
        pitch: 0,
      ),
    );
  }

  for (var i = 0; i < 8; i++) {
    pts.add(
      CapturePoint(
        id: 'U-${(i + 1).toString().padLeft(2, '0')}',
        ring: CaptureRing.upper,
        yaw: (i * 45.0 + yawOffsetDeg) % 360.0,
        pitch: 50,
      ),
    );
  }

  for (var i = 0; i < 8; i++) {
    pts.add(
      CapturePoint(
        id: 'D-${(i + 1).toString().padLeft(2, '0')}',
        ring: CaptureRing.lower,
        yaw: (i * 45.0 + 22.5 + yawOffsetDeg) % 360.0,
        pitch: -50,
      ),
    );
  }

  return pts;
}
