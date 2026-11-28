import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/constants.dart';
import '../../core/utils/angle_utils.dart';

/// Orientation-driven equirectangular projector for multi-frame panoramas.
///
/// Every frame is placed on the sphere from the measured device attitude
/// (yaw/pitch/roll) and resampled through a pinhole → equirectangular mapping,
/// the same geometry used by OpenCV's spherical warper. Each placement is then
/// refined directly against the pixels already on the canvas: a coarse-to-fine
/// zero-mean normalised cross-correlation search over yaw/pitch/roll (the
/// direct photometric approach from Szeliski's stitching tutorial) absorbs
/// compass drift, while a least-squares per-channel gain+offset match (Brown &
/// Lowe gain compensation) evens out exposure. Overlaps use a narrow seam (the
/// strongest frame wins) instead of averaging the whole overlap, so residual
/// attitude error cannot paint double edges across the image; flat regions
/// fall back to a smooth blend.
class StitchProjector {
  StitchProjector({
    this.width = PanoConstants.stitchWidth4k,
    this.height = PanoConstants.stitchHeight4k,
  }) {
    reset();
  }

  final int width;
  final int height;

  late Uint8List _rgba;
  late Float32List _weights;
  late Float32List _sinLon;
  late Float32List _cosLon;
  double? _referenceLuma;
  bool _hasCoverage = false;

  /// Equivalent pixel shift of the applied pose correction (diagnostics).
  int debugLastShiftX = 0;
  int debugLastShiftY = 0;

  /// Photometric pose correction applied to the last frame (diagnostics).
  double debugLastYawDeltaDeg = 0;
  double debugLastPitchDeltaDeg = 0;
  double debugLastRollDeltaDeg = 0;

  img.Image get buffer => _toImage();

  set buffer(img.Image image) {
    final resized = image.width == width && image.height == height
        ? image
        : img.copyResize(image, width: width, height: height);
    _rgba = Uint8List.fromList(
      resized.getBytes(order: img.ChannelOrder.rgba),
    );
    _weights = Float32List(width * height);
    for (var i = 0; i < _weights.length; i++) {
      _weights[i] = 1;
    }
    _referenceLuma = null;
    _hasCoverage = true;
  }

  void reset() {
    _rgba = Uint8List(width * height * 4);
    _weights = Float32List(width * height);
    _sinLon = Float32List(width);
    _cosLon = Float32List(width);
    for (var x = 0; x < width; x++) {
      final lon = (x + 0.5) / width * math.pi * 2;
      _sinLon[x] = math.sin(lon);
      _cosLon[x] = math.cos(lon);
    }
    for (var y = 0; y < height; y++) {
      final t = y / (height - 1);
      final r = (9 + (24 - 9) * (t < 0.5 ? t * 2 : 1)).round();
      final g =
          (13 + (24 - 13) * (t < 0.5 ? t * 2 : (1 - (t - 0.5) * 2))).round();
      final b = (22 + (27 - 22) * (0.5 - (t - 0.5).abs()) * 2).round();
      var i = y * width * 4;
      for (var x = 0; x < width; x++) {
        _rgba[i] = r.clamp(0, 40);
        _rgba[i + 1] = g.clamp(0, 40);
        _rgba[i + 2] = b.clamp(0, 45);
        _rgba[i + 3] = 255;
        i += 4;
      }
    }
    _referenceLuma = null;
    _hasCoverage = false;
    debugLastShiftX = 0;
    debugLastShiftY = 0;
  }

  /// Projects a decoded image using its EXIF orientation.
  void projectFrame(
    img.Image source, {
    required double yawDeg,
    required double pitchDeg,
    double rollDeg = 0,
  }) {
    final oriented = img.bakeOrientation(source);
    projectRgba(
      rgba: oriented.getBytes(order: img.ChannelOrder.rgba),
      imageWidth: oriented.width,
      imageHeight: oriented.height,
      yawDeg: yawDeg,
      pitchDeg: pitchDeg,
      rollDeg: rollDeg,
    );
  }

  /// Projects raw RGBA pixels (already orientation-normalised).
  void projectRgba({
    required Uint8List rgba,
    required int imageWidth,
    required int imageHeight,
    required double yawDeg,
    required double pitchDeg,
    double rollDeg = 0,
  }) {
    if (imageWidth < 8 ||
        imageHeight < 8 ||
        rgba.length < imageWidth * imageHeight * 4) {
      return;
    }
    debugLastShiftX = 0;
    debugLastShiftY = 0;
    debugLastYawDeltaDeg = 0;
    debugLastPitchDeltaDeg = 0;
    debugLastRollDeltaDeg = 0;

    final diagonalTan =
        math.tan(degToRad(PanoConstants.cameraDiagonalFovDeg) / 2);
    final hypot = math.sqrt(imageWidth * imageWidth + imageHeight * imageHeight);
    final hFov = 2 * math.atan(diagonalTan * imageWidth / hypot);
    final vFov = 2 * math.atan(diagonalTan * imageHeight / hypot);
    final tanH = math.tan(hFov / 2);
    final tanV = math.tan(vFov / 2);

    final fallbackGain = _frameGain(rgba, imageWidth, imageHeight);
    final base = _geometryFor(yawDeg, pitchDeg, rollDeg, tanH, tanV);
    if (base.bw < 4 || base.bh < 4) return;

    var fix = _OrientationFix(
      gainR: fallbackGain,
      gainG: fallbackGain,
      gainB: fallbackGain,
    );
    if (_hasCoverage) {
      fix = _refineOrientation(
        base: base,
        yawDeg: yawDeg,
        pitchDeg: pitchDeg,
        rollDeg: rollDeg,
        tanH: tanH,
        tanV: tanV,
        rgba: rgba,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        fallbackGain: fallbackGain,
      );
    }
    debugLastYawDeltaDeg = fix.dYawDeg;
    debugLastPitchDeltaDeg = fix.dPitchDeg;
    debugLastRollDeltaDeg = fix.dRollDeg;
    debugLastShiftX = (fix.dYawDeg / 360 * width).round();
    debugLastShiftY = (-fix.dPitchDeg / 180 * height).round();

    final geo = fix.dYawDeg == 0 && fix.dPitchDeg == 0 && fix.dRollDeg == 0
        ? base
        : _geometryFor(
            yawDeg + fix.dYawDeg,
            pitchDeg + fix.dPitchDeg,
            rollDeg + fix.dRollDeg,
            tanH,
            tanV,
          );
    if (geo.bw < 4 || geo.bh < 4) return;

    const edge = 1.06;
    final patchRgb = Uint8List(geo.bw * geo.bh * 3);
    final patchAlpha = Uint8List(geo.bw * geo.bh);

    var valid = 0;
    for (var py = 0; py < geo.bh; py++) {
      final lat = 90 - (geo.y0 + py + 0.5) / height * 180;
      final latR = degToRad(lat);
      final sinLat = math.sin(latR);
      final cosLat = math.cos(latR);
      final rowBase = py * geo.bw;
      for (var px = 0; px < geo.bw; px++) {
        final cx = geo.x0 + px;
        final xi = ((cx % width) + width) % width;
        final sinLon = _sinLon[xi];
        final cosLon = _cosLon[xi];
        final dx = cosLat * sinLon;
        final dz = cosLat * cosLon;
        final fwd = dx * geo.fx + sinLat * geo.fy + dz * geo.fz;
        if (fwd <= 0.05) continue;
        final camX = (dx * geo.r1x + sinLat * geo.r1y + dz * geo.r1z) / fwd;
        final camY = (dx * geo.u1x + sinLat * geo.u1y + dz * geo.u1z) / fwd;
        final u = camX / tanH;
        final v = camY / tanV;
        if (u.abs() > edge || v.abs() > edge) continue;
        final weight = _axisWeight(u) * _axisWeight(v);
        if (weight < 0.02) continue;
        final r =
            _sample(rgba, imageWidth, imageHeight, u, v, 0, fix.gainR, fix.offsetR);
        final g =
            _sample(rgba, imageWidth, imageHeight, u, v, 1, fix.gainG, fix.offsetG);
        final b =
            _sample(rgba, imageWidth, imageHeight, u, v, 2, fix.gainB, fix.offsetB);
        final pi = rowBase + px;
        patchRgb[pi * 3] = r;
        patchRgb[pi * 3 + 1] = g;
        patchRgb[pi * 3 + 2] = b;
        patchAlpha[pi] = (weight * 255).round().clamp(1, 255);
        valid++;
      }
    }
    if (valid < 200) return;

    // Colour disagreement between this patch and the mosaic. Flat regions
    // (ceiling, blank wall) can be blended smoothly to hide exposure steps and
    // seams; textured regions keep the narrow winner-take-all seam so a small
    // attitude error cannot create double edges. The 5×5 box blur keeps the
    // decision from flickering on single noisy pixels.
    Uint8List? diffMap;
    if (_hasCoverage) {
      final diffs = Uint8List(geo.bw * geo.bh);
      var hasOverlap = false;
      for (var py = 0; py < geo.bh; py++) {
        final wy = geo.y0 + py;
        if (wy < 0 || wy >= height) continue;
        final rowBase = py * geo.bw;
        for (var px = 0; px < geo.bw; px++) {
          if (patchAlpha[rowBase + px] == 0) continue;
          final wx = ((geo.x0 + px) % width + width) % width;
          final ci = wy * width + wx;
          if (_weights[ci] <= 0) continue;
          final pi = (rowBase + px) * 3;
          final oi = ci * 4;
          final dr = (patchRgb[pi] - _rgba[oi]).abs();
          final dg = (patchRgb[pi + 1] - _rgba[oi + 1]).abs();
          final db = (patchRgb[pi + 2] - _rgba[oi + 2]).abs();
          diffs[rowBase + px] = math.max(dr, math.max(dg, db));
          hasOverlap = true;
        }
      }
      if (hasOverlap) diffMap = _blurBox5(diffs, geo.bw, geo.bh);
    }

    for (var py = 0; py < geo.bh; py++) {
      final wy = geo.y0 + py;
      if (wy < 0 || wy >= height) continue;
      final rowBase = py * geo.bw;
      for (var px = 0; px < geo.bw; px++) {
        final a = patchAlpha[rowBase + px];
        if (a == 0) continue;
        final wx = ((geo.x0 + px) % width + width) % width;
        final ci = wy * width + wx;
        final w = a / 255.0;
        final prevW = _weights[ci];
        final pi = (rowBase + px) * 3;
        final oi = ci * 4;
        if (prevW <= 0) {
          _rgba[oi] = patchRgb[pi];
          _rgba[oi + 1] = patchRgb[pi + 1];
          _rgba[oi + 2] = patchRgb[pi + 2];
        } else {
          // Winner-take-all with a narrow transition band, so a few degrees of
          // residual attitude error cannot paint a wide double image.
          final t = (0.5 + (w - prevW) / 0.12).clamp(0.0, 1.0);
          final seam = t * t * (3 - 2 * t);
          final smooth = w / (prevW + w);
          final diff = diffMap == null ? 255 : diffMap[rowBase + px];
          double f;
          if (diff <= 14) {
            f = smooth;
          } else if (diff >= 42) {
            f = seam;
          } else {
            final m = (42 - diff) / 28.0;
            final sm = m * m * (3 - 2 * m);
            f = seam + (smooth - seam) * sm;
          }
          _rgba[oi] = (_rgba[oi] * (1 - f) + patchRgb[pi] * f)
              .round()
              .clamp(0, 255);
          _rgba[oi + 1] = (_rgba[oi + 1] * (1 - f) + patchRgb[pi + 1] * f)
              .round()
              .clamp(0, 255);
          _rgba[oi + 2] = (_rgba[oi + 2] * (1 - f) + patchRgb[pi + 2] * f)
              .round()
              .clamp(0, 255);
        }
        // Keep the strongest coverage, not the sum: with seam compositing a
        // summed weight would let early frames permanently outrank later,
        // better-aligned ones.
        _weights[ci] = math.max(prevW, w);
      }
    }
    _hasCoverage = true;
  }

  /// Separable 5×5 box blur for the 0–255 disagreement map.
  Uint8List _blurBox5(Uint8List src, int w, int h) {
    const radius = 2;
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var sum = 0;
      var count = 0;
      for (var x = -radius; x <= radius; x++) {
        if (x < 0 || x >= w) continue;
        sum += src[row + x];
        count++;
      }
      for (var x = 0; x < w; x++) {
        tmp[row + x] = sum ~/ count;
        final add = x + radius + 1;
        final sub = x - radius;
        if (add < w) {
          sum += src[row + add];
          count++;
        }
        if (sub >= 0) {
          sum -= src[row + sub];
          count--;
        }
      }
    }
    for (var x = 0; x < w; x++) {
      var sum = 0;
      var count = 0;
      for (var y = -radius; y <= radius; y++) {
        if (y < 0 || y >= h) continue;
        sum += tmp[y * w + x];
        count++;
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = sum ~/ count;
        final add = y + radius + 1;
        final sub = y - radius;
        if (add < h) {
          sum += tmp[add * w + x];
          count++;
        }
        if (sub >= 0) {
          sum -= tmp[sub * w + x];
          count--;
        }
      }
    }
    return out;
  }

  double _frameGain(Uint8List rgba, int w, int h) {
    final step = math.max(2, math.sqrt(w * h / 50000).ceil());
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < h; y += step) {
      var i = y * w * 4;
      for (var x = 0; x < w; x += step) {
        sum += rgba[i] * 0.299 + rgba[i + 1] * 0.587 + rgba[i + 2] * 0.114;
        count++;
        i += step * 4;
      }
    }
    if (count == 0) return 1;
    final mean = sum / count;
    final reference = _referenceLuma;
    if (reference == null) {
      _referenceLuma = mean;
      return 1;
    }
    if (mean < 8) return 1;
    return math
        .pow((reference / mean).clamp(0.55, 1.8), 0.7)
        .toDouble()
        .clamp(0.72, 1.45);
  }

  /// Weight feathering: full weight in the middle of the frame, smoothly
  /// falling to ~10% just outside the nominal rectangle. The small edge
  /// margin fills sub-degree coverage slivers without a hard seam.
  double _axisWeight(double t) {
    final a = t.abs();
    if (a <= 0.7) return 1;
    final k = ((a - 0.7) / 0.36).clamp(0.0, 1.0);
    final s = k * k * (3 - 2 * k);
    return 1 - 0.9 * s;
  }

  int _sample(
    Uint8List rgba,
    int w,
    int h,
    double u,
    double v,
    int channel,
    double gain,
    double offset,
  ) {
    final uc = u.clamp(-1.0, 1.0);
    final vc = v.clamp(-1.0, 1.0);
    final fx = (uc + 1) * 0.5 * (w - 1);
    final fy = (1 - vc) * 0.5 * (h - 1);
    final x0 = fx.floor().clamp(0, w - 1);
    final y0 = fy.floor().clamp(0, h - 1);
    final x1 = math.min(x0 + 1, w - 1);
    final y1 = math.min(y0 + 1, h - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final i00 = (y0 * w + x0) * 4 + channel;
    final i10 = (y0 * w + x1) * 4 + channel;
    final i01 = (y1 * w + x0) * 4 + channel;
    final i11 = (y1 * w + x1) * 4 + channel;
    final top = rgba[i00] * (1 - tx) + rgba[i10] * tx;
    final bottom = rgba[i01] * (1 - tx) + rgba[i11] * tx;
    final value = top * (1 - ty) + bottom * ty;
    return (value * gain + offset).round().clamp(0, 255);
  }

  /// Bilinear luma at normalised sensor coordinates, or null outside the frame.
  double? _sampleLuma(
    Uint8List rgba,
    int w,
    int h,
    double u,
    double v,
  ) {
    if (u < -1 || u > 1 || v < -1 || v > 1) return null;
    final fx = (u + 1) * 0.5 * (w - 1);
    final fy = (1 - v) * 0.5 * (h - 1);
    final x0 = fx.floor().clamp(0, w - 1);
    final y0 = fy.floor().clamp(0, h - 1);
    final x1 = math.min(x0 + 1, w - 1);
    final y1 = math.min(y0 + 1, h - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final i00 = (y0 * w + x0) * 4;
    final i10 = (y0 * w + x1) * 4;
    final i01 = (y1 * w + x0) * 4;
    final i11 = (y1 * w + x1) * 4;
    final r = (rgba[i00] * (1 - tx) + rgba[i10] * tx) * (1 - ty) +
        (rgba[i01] * (1 - tx) + rgba[i11] * tx) * ty;
    final g = (rgba[i00 + 1] * (1 - tx) + rgba[i10 + 1] * tx) * (1 - ty) +
        (rgba[i01 + 1] * (1 - tx) + rgba[i11 + 1] * tx) * ty;
    final b = (rgba[i00 + 2] * (1 - tx) + rgba[i10 + 2] * tx) * (1 - ty) +
        (rgba[i01 + 2] * (1 - tx) + rgba[i11 + 2] * tx) * ty;
    return r * 0.299 + g * 0.587 + b * 0.114;
  }

  /// Bilinear RGB at normalised sensor coordinates, or null outside the frame.
  ({double r, double g, double b})? _sampleRgb(
    Uint8List rgba,
    int w,
    int h,
    double u,
    double v,
  ) {
    if (u < -1 || u > 1 || v < -1 || v > 1) return null;
    final fx = (u + 1) * 0.5 * (w - 1);
    final fy = (1 - v) * 0.5 * (h - 1);
    final x0 = fx.floor().clamp(0, w - 1);
    final y0 = fy.floor().clamp(0, h - 1);
    final x1 = math.min(x0 + 1, w - 1);
    final y1 = math.min(y0 + 1, h - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final i00 = (y0 * w + x0) * 4;
    final i10 = (y0 * w + x1) * 4;
    final i01 = (y1 * w + x0) * 4;
    final i11 = (y1 * w + x1) * 4;
    double channel(int c) =>
        (rgba[i00 + c] * (1 - tx) + rgba[i10 + c] * tx) * (1 - ty) +
        (rgba[i01 + c] * (1 - tx) + rgba[i11 + c] * tx) * ty;
    return (r: channel(0), g: channel(1), b: channel(2));
  }

  _Basis _basisFor(double yawDeg, double pitchDeg, double rollDeg) {
    final yaw = degToRad(normalizeDeg360(yawDeg));
    final pitch = degToRad(clampPitch(pitchDeg));
    final roll = degToRad(rollDeg);
    final sy = math.sin(yaw);
    final cy = math.cos(yaw);
    final sp = math.sin(pitch);
    final cp = math.cos(pitch);
    final fx = sy * cp;
    final fy = sp;
    final fz = cy * cp;
    final rx = cy;
    const ry = 0.0;
    final rz = -sy;
    final ux = -sp * sy;
    final uy = cp;
    final uz = -sp * cy;
    final cr = math.cos(roll);
    final sr = math.sin(roll);
    return (
      fx: fx,
      fy: fy,
      fz: fz,
      r1x: rx * cr - ux * sr,
      r1y: ry * cr - uy * sr,
      r1z: rz * cr - uz * sr,
      u1x: ux * cr + rx * sr,
      u1y: uy * cr + ry * sr,
      u1z: uz * cr + rz * sr,
    );
  }

  /// Projects the framing rectangle of a pose onto the canvas and returns the
  /// camera basis with the pixel bounds. The 6% margin lets polar rings avoid
  /// a full-width scan while still covering sub-degree slivers.
  _PoseGeometry _geometryFor(
    double yawDeg,
    double pitchDeg,
    double rollDeg,
    double tanH,
    double tanV,
  ) {
    final b = _basisFor(yawDeg, pitchDeg, rollDeg);
    const edge = 1.06;
    var latMin = 90.0;
    var latMax = -90.0;
    var lonHalf = 0.0;
    for (final u in [-edge, 0.0, edge]) {
      for (final v in [-edge, 0.0, edge]) {
        var dx = b.fx + u * tanH * b.r1x + v * tanV * b.u1x;
        var dy = b.fy + u * tanH * b.r1y + v * tanV * b.u1y;
        var dz = b.fz + u * tanH * b.r1z + v * tanV * b.u1z;
        final len = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (len < 1e-6) continue;
        dx /= len;
        dy /= len;
        dz /= len;
        final lat = radToDeg(math.asin(dy.clamp(-1.0, 1.0)));
        final lon = radToDeg(math.atan2(dx, dz));
        latMin = math.min(latMin, lat);
        latMax = math.max(latMax, lat);
        lonHalf = math.max(lonHalf, normalizeDeg180(lon - yawDeg).abs());
      }
    }
    latMin = (latMin - 1.5).clamp(-89.9, 89.9);
    latMax = (latMax + 1.5).clamp(-89.9, 89.9);
    lonHalf = (lonHalf + 1.5).clamp(0.0, 180.0);

    final y0 = ((90 - latMax) / 180 * height).floor().clamp(0, height - 1);
    final y1 = ((90 - latMin) / 180 * height).ceil().clamp(1, height);
    if (y1 <= y0) {
      return _PoseGeometry(
        fx: b.fx,
        fy: b.fy,
        fz: b.fz,
        r1x: b.r1x,
        r1y: b.r1y,
        r1z: b.r1z,
        u1x: b.u1x,
        u1y: b.u1y,
        u1z: b.u1z,
        y0: y0,
        x0: 0,
        bw: 0,
        bh: 0,
      );
    }
    final xCenter = normalizeDeg360(yawDeg) / 360 * width;
    final halfPx = lonHalf / 360 * width;
    final x0 = (xCenter - halfPx).floor() - 1;
    final bw = (halfPx * 2).ceil() + 3;
    final bh = y1 - y0;
    return _PoseGeometry(
      fx: b.fx,
      fy: b.fy,
      fz: b.fz,
      r1x: b.r1x,
      r1y: b.r1y,
      r1z: b.r1z,
      u1x: b.u1x,
      u1y: b.u1y,
      u1z: b.u1z,
      y0: y0,
      x0: x0,
      bw: bw,
      bh: bh,
    );
  }

  /// Refines yaw/pitch/roll and exposure against the pixels already projected.
  ///
  /// The search maximises zero-mean normalised cross-correlation (ZNCC) of
  /// luma between the frame and the mosaic over pose offsets — the direct
  /// photometric alignment of Szeliski's tutorial, insensitive to exposure.
  /// Roll is included because a translation-only shift cannot align the frame
  /// corners once the device has rolled by a couple of degrees. Exposure is a
  /// per-channel least-squares gain+offset fit on the same overlap, following
  /// Brown & Lowe's gain compensation. A correction is only accepted when it
  /// explains noticeably more of the overlap, which stops low-texture or
  /// repetitive walls from inventing one.
  _OrientationFix _refineOrientation({
    required _PoseGeometry base,
    required double yawDeg,
    required double pitchDeg,
    required double rollDeg,
    required double tanH,
    required double tanV,
    required Uint8List rgba,
    required int imageWidth,
    required int imageHeight,
    required double fallbackGain,
  }) {
    final fallback = _OrientationFix(
      gainR: fallbackGain,
      gainG: fallbackGain,
      gainB: fallbackGain,
    );
    final stride = math.max(2, math.sqrt(base.bw * base.bh / 6000.0).floor());
    final rayX = <double>[];
    final rayY = <double>[];
    final rayZ = <double>[];
    final canvasLuma = <double>[];
    final canvasIndex = <int>[];
    for (var py = 0; py < base.bh; py += stride) {
      final cy = base.y0 + py;
      if (cy < 0 || cy >= height) continue;
      final lat = 90 - (cy + 0.5) / height * 180;
      final latR = degToRad(lat);
      final sinLat = math.sin(latR);
      final cosLat = math.cos(latR);
      for (var px = 0; px < base.bw; px += stride) {
        final cx = ((base.x0 + px) % width + width) % width;
        final ci = cy * width + cx;
        if (_weights[ci] < 0.25) continue;
        rayX.add(cosLat * _sinLon[cx]);
        rayY.add(sinLat);
        rayZ.add(cosLat * _cosLon[cx]);
        canvasLuma.add(_rgbaLuma(ci).toDouble());
        canvasIndex.add(ci);
      }
    }
    final total = rayX.length;
    if (total < 150) return fallback;

    ({double corr, int used, double varC, double varS})? evaluate(
      double yawC,
      double pitchC,
      double rollC,
    ) {
      final b = _basisFor(yawC, pitchC, rollC);
      var n = 0;
      var sumC = 0.0;
      var sumS = 0.0;
      var sumCC = 0.0;
      var sumSS = 0.0;
      var sumCS = 0.0;
      for (var k = 0; k < total; k++) {
        final dx = rayX[k];
        final dy = rayY[k];
        final dz = rayZ[k];
        final fwd = dx * b.fx + dy * b.fy + dz * b.fz;
        if (fwd <= 0.05) continue;
        final camX = (dx * b.r1x + dy * b.r1y + dz * b.r1z) / fwd;
        final camY = (dx * b.u1x + dy * b.u1y + dz * b.u1z) / fwd;
        final u = camX / tanH;
        final v = camY / tanV;
        if (u.abs() > 0.96 || v.abs() > 0.96) continue;
        final s = _sampleLuma(rgba, imageWidth, imageHeight, u, v);
        if (s == null) continue;
        final c = canvasLuma[k];
        n++;
        sumC += c;
        sumS += s;
        sumCC += c * c;
        sumSS += s * s;
        sumCS += c * s;
      }
      if (n < 120) return null;
      final meanC = sumC / n;
      final meanS = sumS / n;
      final varC = sumCC / n - meanC * meanC;
      final varS = sumSS / n - meanS * meanS;
      final denom = math.sqrt(math.max(0.0, varC) * math.max(0.0, varS));
      final corr = denom < 1e-6 ? 0.0 : (sumCS / n - meanC * meanS) / denom;
      return (corr: corr, used: n, varC: varC, varS: varS);
    }

    final zero = evaluate(yawDeg, pitchDeg, rollDeg);
    if (zero == null || zero.varC < 9 || zero.varS < 9) return fallback;
    final minUsed = (zero.used * 0.7).ceil();

    var bestCorr = zero.corr;
    var bestYaw = 0.0;
    var bestPitch = 0.0;
    var bestRoll = 0.0;
    void consider(double dYaw, double dPitch, double dRoll) {
      if (dYaw == 0 && dPitch == 0 && dRoll == 0) return;
      final result =
          evaluate(yawDeg + dYaw, pitchDeg + dPitch, rollDeg + dRoll);
      if (result == null || result.used < minUsed) return;
      if (result.corr > bestCorr + 1e-9) {
        bestCorr = result.corr;
        bestYaw = dYaw;
        bestPitch = dPitch;
        bestRoll = dRoll;
      }
    }

    for (var dYaw = -10.0; dYaw <= 10.01; dYaw += 2.5) {
      for (var dPitch = -6.0; dPitch <= 6.01; dPitch += 3.0) {
        for (var dRoll = -5.0; dRoll <= 5.01; dRoll += 2.5) {
          consider(dYaw, dPitch, dRoll);
        }
      }
    }
    var stepYaw = 1.2;
    var stepPitch = 1.0;
    var stepRoll = 0.8;
    for (var round = 0; round < 3; round++) {
      final centerYaw = bestYaw;
      final centerPitch = bestPitch;
      final centerRoll = bestRoll;
      for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
          for (var k = -1; k <= 1; k++) {
            consider(
              (centerYaw + i * stepYaw).clamp(-12.0, 12.0),
              (centerPitch + j * stepPitch).clamp(-7.0, 7.0),
              (centerRoll + k * stepRoll).clamp(-5.0, 5.0),
            );
          }
        }
      }
      stepYaw *= 0.35;
      stepPitch *= 0.35;
      stepRoll *= 0.35;
    }
    if (bestCorr <= zero.corr + 0.01) {
      bestYaw = 0;
      bestPitch = 0;
      bestRoll = 0;
    }

    // Per-channel gain+offset on the overlap at the refined pose.
    final b =
        _basisFor(yawDeg + bestYaw, pitchDeg + bestPitch, rollDeg + bestRoll);
    final gains = <double>[fallbackGain, fallbackGain, fallbackGain];
    final offsets = <double>[0.0, 0.0, 0.0];
    final sumS = <double>[0.0, 0.0, 0.0];
    final sumC = <double>[0.0, 0.0, 0.0];
    final sumSS = <double>[0.0, 0.0, 0.0];
    final sumSC = <double>[0.0, 0.0, 0.0];
    var used = 0;
    for (var k = 0; k < total; k++) {
      final dx = rayX[k];
      final dy = rayY[k];
      final dz = rayZ[k];
      final fwd = dx * b.fx + dy * b.fy + dz * b.fz;
      if (fwd <= 0.05) continue;
      final camX = (dx * b.r1x + dy * b.r1y + dz * b.r1z) / fwd;
      final camY = (dx * b.u1x + dy * b.u1y + dz * b.u1z) / fwd;
      final u = camX / tanH;
      final v = camY / tanV;
      if (u.abs() > 0.96 || v.abs() > 0.96) continue;
      final sample = _sampleRgb(rgba, imageWidth, imageHeight, u, v);
      if (sample == null) continue;
      final ci = canvasIndex[k] * 4;
      used++;
      sumS[0] += sample.r;
      sumS[1] += sample.g;
      sumS[2] += sample.b;
      sumC[0] += _rgba[ci];
      sumC[1] += _rgba[ci + 1];
      sumC[2] += _rgba[ci + 2];
      sumSS[0] += sample.r * sample.r;
      sumSS[1] += sample.g * sample.g;
      sumSS[2] += sample.b * sample.b;
      sumSC[0] += sample.r * _rgba[ci];
      sumSC[1] += sample.g * _rgba[ci + 1];
      sumSC[2] += sample.b * _rgba[ci + 2];
    }
    if (used >= 150) {
      for (var c = 0; c < 3; c++) {
        final meanS = sumS[c] / used;
        final meanC = sumC[c] / used;
        final varS = sumSS[c] / used - meanS * meanS;
        if (varS <= 4) continue;
        var gain = (sumSC[c] / used - meanS * meanC) / varS;
        gain = gain.clamp(0.6, 1.6);
        final offset = (meanC - gain * meanS).clamp(-45.0, 45.0);
        gains[c] = gain;
        offsets[c] = offset;
      }
    }

    return _OrientationFix(
      dYawDeg: bestYaw,
      dPitchDeg: bestPitch,
      dRollDeg: bestRoll,
      gainR: gains[0],
      offsetR: offsets[0],
      gainG: gains[1],
      offsetG: offsets[1],
      gainB: gains[2],
      offsetB: offsets[2],
    );
  }

  int _rgbaLuma(int pixelIndex) {
    final o = pixelIndex * 4;
    return (_rgba[o] * 0.299 + _rgba[o + 1] * 0.587 + _rgba[o + 2] * 0.114)
        .round();
  }

  img.Image _toImage() {
    // Uncovered polar caps stay dark on purpose: replicating the nearest row
    // produced long vertical smears at the top/bottom of the panorama.
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: Uint8List.fromList(_rgba).buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  }

  /// Raw RGBA snapshot so the JPEG step can run on a background isolate.
  Uint8List snapshotRgba() => Uint8List.fromList(_rgba);

  Uint8List encodeJpeg({int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(_toImage(), quality: quality));
  }

  Uint8List encodePng() {
    return Uint8List.fromList(img.encodePng(_toImage()));
  }

  img.Image cloneBuffer() => _toImage().clone();
}

typedef _Basis = ({
  double fx,
  double fy,
  double fz,
  double r1x,
  double r1y,
  double r1z,
  double u1x,
  double u1y,
  double u1z,
});

class _PoseGeometry {
  const _PoseGeometry({
    required this.fx,
    required this.fy,
    required this.fz,
    required this.r1x,
    required this.r1y,
    required this.r1z,
    required this.u1x,
    required this.u1y,
    required this.u1z,
    required this.y0,
    required this.x0,
    required this.bw,
    required this.bh,
  });

  final double fx;
  final double fy;
  final double fz;
  final double r1x;
  final double r1y;
  final double r1z;
  final double u1x;
  final double u1y;
  final double u1z;
  final int y0;
  final int x0;
  final int bw;
  final int bh;
}

class _OrientationFix {
  const _OrientationFix({
    this.dYawDeg = 0,
    this.dPitchDeg = 0,
    this.dRollDeg = 0,
    this.gainR = 1,
    this.offsetR = 0,
    this.gainG = 1,
    this.offsetG = 0,
    this.gainB = 1,
    this.offsetB = 0,
  });

  final double dYawDeg;
  final double dPitchDeg;
  final double dRollDeg;
  final double gainR;
  final double offsetR;
  final double gainG;
  final double offsetG;
  final double gainB;
  final double offsetB;
}
