import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/utils/angle_utils.dart';

/// Attitude-based equirectangular projection stitcher (HTML prototype port).
class StitchProjector {
  StitchProjector({
    this.width = 2048,
    this.height = 1024,
  }) {
    reset();
  }

  final int width;
  final int height;
  late img.Image buffer;

  void reset() {
    buffer = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      final t = y / (height - 1);
      final r = (9 + (24 - 9) * (t < 0.5 ? t * 2 : 1)).round();
      final g = (13 + (24 - 13) * (t < 0.5 ? t * 2 : (1 - (t - 0.5) * 2))).round();
      final b = (22 + (27 - 22) * (0.5 - (t - 0.5).abs()) * 2).round();
      for (var x = 0; x < width; x++) {
        buffer.setPixelRgba(x, y, r.clamp(0, 40), g.clamp(0, 40), b.clamp(0, 45), 255);
      }
    }
  }

  void projectFrame(
    img.Image source, {
    required double yawDeg,
    required double pitchDeg,
  }) {
    final u = normalizeDeg360(yawDeg) / 360.0;
    final v = (90.0 - pitchDeg) / 180.0;
    final cx = u * width;
    final cy = v * height;

    final latScale = 1 / math.max(0.45, math.cos(degToRad(pitchDeg)));
    final patchW = ((width / 5.2) * latScale).round().clamp(32, width);
    final patchH = (height / 2.6).round().clamp(32, height);

    final patch = img.copyResize(
      source,
      width: patchW,
      height: patchH,
      interpolation: img.Interpolation.linear,
    );

    final feathered = _applyRadialFeather(patch);

    for (final offsetX in [-width.toDouble(), 0.0, width.toDouble()]) {
      final drawX = (cx - patchW / 2 + offsetX).round();
      final drawY = (cy - patchH / 2).round();
      if (drawX + patchW <= 0 || drawX >= width) continue;
      _blendOnto(feathered, drawX, drawY);
    }
  }

  img.Image _applyRadialFeather(img.Image patch) {
    final out = img.Image(width: patch.width, height: patch.height, numChannels: 4);
    final cx = patch.width / 2;
    final cy = patch.height / 2;
    final inner = patch.width * 0.25;
    final outer = patch.width * 0.52;

    for (var y = 0; y < patch.height; y++) {
      for (var x = 0; x < patch.width; x++) {
        final px = patch.getPixel(x, y);
        final dx = x - cx;
        final dy = y - cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        double alpha;
        if (dist <= inner) {
          alpha = 1;
        } else if (dist >= outer) {
          alpha = 0;
        } else {
          alpha = 1 - (dist - inner) / (outer - inner);
        }
        final a = (px.a * alpha).round().clamp(0, 255);
        out.setPixelRgba(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), a);
      }
    }
    return out;
  }

  void _blendOnto(img.Image src, int ox, int oy) {
    for (var y = 0; y < src.height; y++) {
      final dy = oy + y;
      if (dy < 0 || dy >= height) continue;
      for (var x = 0; x < src.width; x++) {
        final dx = ox + x;
        if (dx < 0 || dx >= width) continue;
        final s = src.getPixel(x, y);
        final a = s.a / 255.0;
        if (a <= 0) continue;
        final d = buffer.getPixel(dx, dy);
        final inv = 1 - a;
        buffer.setPixelRgba(
          dx,
          dy,
          (s.r * a + d.r * inv).round(),
          (s.g * a + d.g * inv).round(),
          (s.b * a + d.b * inv).round(),
          255,
        );
      }
    }
  }

  Uint8List encodeJpeg({int quality = 90}) =>
      Uint8List.fromList(img.encodeJpg(buffer, quality: quality));

  Uint8List encodePng() => Uint8List.fromList(img.encodePng(buffer));

  img.Image cloneBuffer() => buffer.clone();
}
