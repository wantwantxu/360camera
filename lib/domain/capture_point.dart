enum CaptureRing { upper, mid, lower }

extension CaptureRingX on CaptureRing {
  String get label => switch (this) {
        CaptureRing.upper => '仰拍环',
        CaptureRing.mid => '水平环',
        CaptureRing.lower => '俯拍环',
      };
}

class CapturePoint {
  CapturePoint({
    required this.id,
    required this.ring,
    required this.yaw,
    required this.pitch,
    this.captured = false,
    this.framePath,
  });

  final String id;
  final CaptureRing ring;
  final double yaw;
  final double pitch;
  bool captured;
  String? framePath;

  CapturePoint copyWith({
    bool? captured,
    String? framePath,
  }) {
    return CapturePoint(
      id: id,
      ring: ring,
      yaw: yaw,
      pitch: pitch,
      captured: captured ?? this.captured,
      framePath: framePath ?? this.framePath,
    );
  }
}
