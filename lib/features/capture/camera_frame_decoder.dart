import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Decoded camera frame ready for sphere projection.
class CameraFrameRgba {
  const CameraFrameRgba({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Decodes a captured JPEG at a reduced size and normalises EXIF rotation.
///
/// Full-resolution stills (4:3 sensor crop) decode much faster through the
/// engine codec than through pure Dart. A 4K equirect canvas shows one frame
/// at roughly 600 px wide, so 1600 px keeps useful oversampling for the
/// bilinear resample without holding full 12 MP frames in memory.
Future<CameraFrameRgba?> decodeCameraFrame(
  Uint8List jpeg, {
  int targetWidth = 1600,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: targetWidth,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (data == null) return null;
    var rgba = data.buffer.asUint8List();
    final orientation = _orientationOf(jpeg);
    // Some engine versions already bake the EXIF rotation; only rotate when
    // the decoded buffer still has sensor (landscape) dimensions.
    final quarterTurns = switch (orientation) {
      6 when w > h => 1,
      8 when w > h => 3,
      _ => 0,
    };
    if (quarterTurns == 0) {
      return CameraFrameRgba(rgba: rgba, width: w, height: h);
    }
    final rotated = _rotateRgba(rgba, w, h, quarterTurns);
    return CameraFrameRgba(
      rgba: rotated.rgba,
      width: rotated.width,
      height: rotated.height,
    );
  } catch (_) {
    return null;
  }
}

int _orientationOf(Uint8List jpeg) {
  try {
    return img.decodeJpgExif(jpeg)?.imageIfd.orientation ?? 1;
  } catch (_) {
    return 1;
  }
}

({Uint8List rgba, int width, int height}) _rotateRgba(
  Uint8List src,
  int w,
  int h,
  int quarterTurns,
) {
  if (quarterTurns == 1 || quarterTurns == 3) {
    final out = Uint8List(w * h * 4);
    final dw = h;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final si = (y * w + x) * 4;
        final dx = quarterTurns == 1 ? h - 1 - y : y;
        final dy = quarterTurns == 1 ? x : w - 1 - x;
        final di = (dy * dw + dx) * 4;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    return (rgba: out, width: dw, height: w);
  }
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final si = (y * w + x) * 4;
      final di = ((h - 1 - y) * w + (w - 1 - x)) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = src[si + 3];
    }
  }
  return (rgba: out, width: w, height: h);
}
