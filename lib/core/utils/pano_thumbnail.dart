import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Renders a perspective 16:9 crop from the centre of an equirectangular image.
///
/// Space project covers and point chips use this instead of squashing the whole
/// 2:1 panorama, which looks distorted in a portrait card.
Uint8List createPerspectiveThumbnail(
  img.Image source, {
  int width = 640,
  double fovYDeg = 72,
}) {
  final outputHeight = (width * 9 / 16).round();
  final out = img.Image(width: width, height: outputHeight, numChannels: 4);
  final fovX =
      fovYDeg * (width / outputHeight);
  final tanX = math.tan(fovX * math.pi / 360);
  final tanY = math.tan(fovYDeg * math.pi / 360);

  for (var y = 0; y < outputHeight; y++) {
    final ny = (y + 0.5) / outputHeight * 2 - 1;
    final dy = -ny * tanY;
    for (var x = 0; x < width; x++) {
      final nx = (x + 0.5) / width * 2 - 1;
      final dx = nx * tanX;
      final len = math.sqrt(dx * dx + dy * dy + 1);
      final vx = dx / len;
      final vy = dy / len;
      final vz = 1 / len;
      final lon = math.atan2(vx, vz);
      final lat = math.asin(vy.clamp(-1.0, 1.0));
      final u = ((lon / (2 * math.pi)) + 1) % 1;
      final v = (0.5 - lat / math.pi).clamp(0.0, 0.999999);
      final sx = (u * source.width).floor().clamp(0, source.width - 1);
      final sy = (v * source.height).floor().clamp(0, source.height - 1);
      final pixel = source.getPixel(sx, sy);
      out.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        255,
      );
    }
  }

  return Uint8List.fromList(img.encodeJpg(out, quality: 84));
}