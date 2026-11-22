import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../domain/app_enums.dart';

img.Image generateProceduralEquirectangular(
  CaptureSource preset, {
  int width = 2048,
  int height = 1024,
}) {
  final out = img.Image(width: width, height: height, numChannels: 4);
  final rnd = math.Random(preset.index + 42);

  for (var y = 0; y < height; y++) {
    final v = y / (height - 1);
    for (var x = 0; x < width; x++) {
      final u = x / (width - 1);
      late int r, g, b;
      switch (preset) {
        case CaptureSource.sunset:
        case CaptureSource.camera:
          final sky = _lerpColor(
            const [18, 24, 68],
            const [252, 163, 84],
            (1 - (v - 0.35).abs() * 1.8).clamp(0.0, 1.0),
          );
          final sea = _lerpColor(
            const [12, 48, 78],
            const [6, 18, 36],
            ((v - 0.55) / 0.45).clamp(0.0, 1.0),
          );
          final mix = v < 0.55 ? sky : sea;
          final sun = math.exp(-math.pow((u - 0.72) * 18, 2) - math.pow((v - 0.48) * 22, 2));
          r = (mix[0] + sun * 200).round().clamp(0, 255);
          g = (mix[1] + sun * 140).round().clamp(0, 255);
          b = (mix[2] + sun * 40).round().clamp(0, 255);
          break;
        case CaptureSource.cyberpunk:
          final neon = (math.sin(u * math.pi * 12) * 0.5 + 0.5) *
              (math.sin(v * math.pi * 8) * 0.5 + 0.5);
          r = (20 + neon * 180 + (1 - v) * 40).round().clamp(0, 255);
          g = (10 + neon * 40).round().clamp(0, 255);
          b = (40 + neon * 200 + v * 30).round().clamp(0, 255);
          if (rnd.nextDouble() > 0.992) {
            r = 255;
            g = 220;
            b = 80;
          }
          break;
        case CaptureSource.starry:
          final night = _lerpColor(const [4, 8, 28], const [18, 28, 48], 1 - v);
          r = night[0];
          g = night[1];
          b = night[2];
          if (rnd.nextDouble() > 0.997) {
            final bright = 180 + rnd.nextInt(75);
            r = bright;
            g = bright;
            b = bright;
          }
          final snow = (v > 0.72)
              ? ((v - 0.72) / 0.28 * 160).round()
              : 0;
          r = (r + snow).clamp(0, 255);
          g = (g + snow).clamp(0, 255);
          b = (b + snow).clamp(0, 255);
          break;
      }
      out.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return out;
}

List<int> _lerpColor(List<int> a, List<int> b, double t) {
  final tt = t.clamp(0.0, 1.0);
  return [
    (a[0] + (b[0] - a[0]) * tt).round(),
    (a[1] + (b[1] - a[1]) * tt).round(),
    (a[2] + (b[2] - a[2]) * tt).round(),
  ];
}
