import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pano_360_pro/features/capture/stitch_projector.dart';

Uint8List _solid(int width, int height, int r, int g, int b) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}

const _srcW = 240;
const _srcH = 320;

/// Deterministic block noise. Periodic patterns would make the photometric
/// pose search ambiguous (several yaw offsets fit equally well).
Uint8List _noiseTexture() {
  const block = 12;
  final cols = (_srcW / block).ceil();
  final rows = (_srcH / block).ceil();
  final values = <int>[];
  var seed = 20261128;
  for (var i = 0; i < cols * rows; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    values.add(40 + seed % 180);
  }
  final rgba = Uint8List(_srcW * _srcH * 4);
  for (var y = 0; y < _srcH; y++) {
    for (var x = 0; x < _srcW; x++) {
      final v = values[(y ~/ block) * cols + (x ~/ block)];
      final i = (y * _srcW + x) * 4;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

void main() {
  group('StitchProjector', () {
    test('places a frame at the commanded yaw and leaves the far side empty',
        () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      final image = projector.buffer;
      final center = image.getPixel(0, 240);
      expect(center.r, greaterThan(200));
      expect(center.g, lessThan(60));
      final opposite = image.getPixel(480, 240);
      expect(opposite.r, lessThan(50));
    });

    test('handles yaw wrap-around near 360°', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 350,
        pitchDeg: 0,
      );
      final image = projector.buffer;
      expect(image.getPixel(933, 240).r, greaterThan(200));
      expect(image.getPixel(453, 240).r, lessThan(50));
    });

    test('maps pitch to latitude', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 50,
      );
      final image = projector.buffer;
      expect(image.getPixel(0, 107).r, greaterThan(200));
      expect(image.getPixel(0, 240).r, lessThan(50));
    });

    test('covers the overlap with the stronger frame', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 30, 40, 220),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 45,
        pitchDeg: 0,
      );
      final image = projector.buffer;
      final seam = image.getPixel(60, 240);
      expect(seam.b, greaterThan(150));
      expect(seam.r, lessThan(80));
      final blueCenter = image.getPixel(120, 240);
      expect(blueCenter.b, greaterThan(180));
    });

    test('normalises exposure so bright frames do not over-brighten', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 60, 60, 60),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 200, 200, 200),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      final blended = projector.buffer.getPixel(0, 240).r;
      expect(blended, greaterThan(70));
      expect(blended, lessThan(115));
    });

    test('does not warp a correctly placed duplicate frame', () {
      final projector = StitchProjector(width: 960, height: 480);
      final rgba = _solid(_srcW, _srcH, 200, 180, 60);
      projector.projectRgba(
        rgba: rgba,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 30,
        pitchDeg: 10,
      );
      projector.projectRgba(
        rgba: rgba,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 30,
        pitchDeg: 10,
      );
      expect(projector.debugLastShiftX, 0);
      expect(projector.debugLastShiftY, 0);
    });

    test('leaves uncovered polar caps dark instead of smearing rows', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 50,
      );
      final image = projector.buffer;
      expect(image.getPixel(0, 0).r, lessThan(50));
      expect(image.getPixel(0, 107).r, greaterThan(200));
    });

    test('keeps the seam narrow instead of averaging the overlap', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 30, 40, 220),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 45,
        pitchDeg: 0,
      );
      final image = projector.buffer;
      // 21.75° has a clearly stronger red weight; the old full-overlap
      // average would paint a purple ghost here.
      final redSide = image.getPixel(58, 240);
      expect(redSide.r, greaterThan(150));
      expect(redSide.b, lessThan(80));
      final blueSide = image.getPixel(62, 240);
      expect(blueSide.b, greaterThan(150));
      expect(blueSide.r, lessThan(80));
    });

    test('corrects a large compass yaw error', () {
      final projector = StitchProjector(width: 960, height: 480);
      final texture = _noiseTexture();
      projector.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 10,
        pitchDeg: 0,
      );
      // 10° at 960 px is 26.7 px; the widened photometric search must
      // recover it as a −10° pose correction.
      expect(projector.debugLastYawDeltaDeg, inInclusiveRange(-11.5, -8.5));
      expect(
        projector.debugLastShiftX.toDouble(),
        inInclusiveRange(-31, -23),
      );
    });

    test('refines roll against the overlap', () {
      final projector = StitchProjector(width: 960, height: 480);
      final texture = _noiseTexture();
      projector.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
        rollDeg: 4,
      );
      expect(projector.debugLastRollDeltaDeg, inInclusiveRange(-5.5, -2.5));
      expect(projector.debugLastYawDeltaDeg.abs(), lessThan(1.5));
      expect(projector.debugLastPitchDeltaDeg.abs(), lessThan(1.5));
    });

    test('matches per-channel exposure on the overlap', () {
      final texture = _noiseTexture();
      final reference = StitchProjector(width: 960, height: 480);
      reference.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      final expected = reference.buffer.getPixel(0, 240).r;

      final dim = Uint8List(texture.length);
      for (var i = 0; i < texture.length; i += 4) {
        dim[i] = (texture[i] * 0.8).round();
        dim[i + 1] = (texture[i + 1] * 0.8).round();
        dim[i + 2] = (texture[i + 2] * 0.8).round();
        dim[i + 3] = 255;
      }
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: texture,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      projector.projectRgba(
        rgba: dim,
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 0,
        pitchDeg: 0,
      );
      final blended = projector.buffer.getPixel(0, 240).r;
      // Without exposure matching the overlap would average to ~90% of the
      // reference brightness.
      expect((blended - expected).abs(), lessThan(12));
    });

    test('roll keeps the lens centre stable', () {
      final projector = StitchProjector(width: 960, height: 480);
      projector.projectRgba(
        rgba: _solid(_srcW, _srcH, 220, 30, 20),
        imageWidth: _srcW,
        imageHeight: _srcH,
        yawDeg: 90,
        pitchDeg: 0,
        rollDeg: 30,
      );
      expect(projector.buffer.getPixel(240, 240).r, greaterThan(200));
    });
  });
}
