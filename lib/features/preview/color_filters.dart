import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../domain/app_enums.dart';

ColorFilter? flutterColorFilter(ColorFilterId id) {
  switch (id) {
    case ColorFilterId.none:
      return null;
    case ColorFilterId.cinema:
      return const ColorFilter.matrix(<double>[
        1.15, 0.05, -0.05, 0, 8,
        -0.04, 1.08, 0.04, 0, 4,
        -0.08, 0.02, 1.12, 0, -4,
        0, 0, 0, 1, 0,
      ]);
    case ColorFilterId.cyber:
      return const ColorFilter.matrix(<double>[
        1.05, 0.0, 0.2, 0, 6,
        0.0, 1.15, 0.15, 0, 4,
        0.15, 0.05, 1.35, 0, 10,
        0, 0, 0, 1, 0,
      ]);
    case ColorFilterId.warm:
      return const ColorFilter.matrix(<double>[
        1.18, 0.08, 0.0, 0, 10,
        0.04, 1.05, 0.0, 0, 6,
        0.0, 0.0, 0.9, 0, -4,
        0, 0, 0, 1, 0,
      ]);
    case ColorFilterId.bw:
      return const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]);
  }
}

img.Image applyImageFilter(img.Image src, ColorFilterId id) {
  if (id == ColorFilterId.none) return src.clone();
  final out = src.clone();
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      var r = p.r.toDouble();
      var g = p.g.toDouble();
      var b = p.b.toDouble();
      switch (id) {
        case ColorFilterId.none:
          break;
        case ColorFilterId.cinema:
          r = (r * 1.15 + g * 0.05 - b * 0.05 + 8).clamp(0, 255);
          g = (-r * 0.02 + g * 1.08 + b * 0.04 + 4).clamp(0, 255);
          b = (-r * 0.05 + g * 0.02 + b * 1.12 - 4).clamp(0, 255);
          break;
        case ColorFilterId.cyber:
          r = (r * 1.05 + b * 0.2 + 6).clamp(0, 255);
          g = (g * 1.15 + b * 0.15 + 4).clamp(0, 255);
          b = (r * 0.1 + b * 1.35 + 10).clamp(0, 255);
          break;
        case ColorFilterId.warm:
          r = (r * 1.18 + g * 0.08 + 10).clamp(0, 255);
          g = (r * 0.02 + g * 1.05 + 6).clamp(0, 255);
          b = (b * 0.9 - 4).clamp(0, 255);
          break;
        case ColorFilterId.bw:
          final yv = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final c = ((yv - 128) * 1.35 + 128 + 4).clamp(0, 255).toDouble();
          r = c;
          g = c;
          b = c;
          break;
      }
      out.setPixelRgba(x, y, r.round(), g.round(), b.round(), p.a.toInt());
    }
  }
  return out;
}

Future<ui.Image> decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
