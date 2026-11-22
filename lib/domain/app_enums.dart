enum AppMode { capture, preview }

enum CaptureSource { camera, sunset, cyberpunk, starry }

enum ProjectionView { normal, planet }

enum ColorFilterId { none, cinema, cyber, warm, bw }

extension ColorFilterIdX on ColorFilterId {
  String get label => switch (this) {
        ColorFilterId.none => '原图直出',
        ColorFilterId.cinema => '电影青橙',
        ColorFilterId.cyber => '赛博霓虹',
        ColorFilterId.warm => '暖阳胶片',
        ColorFilterId.bw => '黑白纪实',
      };

  String get badge => switch (this) {
        ColorFilterId.none => 'RAW',
        ColorFilterId.cinema => 'CINE',
        ColorFilterId.cyber => 'NEON',
        ColorFilterId.warm => 'FILM',
        ColorFilterId.bw => 'MONO',
      };
}

extension CaptureSourceX on CaptureSource {
  String get label => switch (this) {
        CaptureSource.camera => '真实摄像头',
        CaptureSource.sunset => '日落海滩',
        CaptureSource.cyberpunk => '赛博都市',
        CaptureSource.starry => '星空雪山',
      };
}
