import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/utils/angle_utils.dart';
import '../../domain/app_enums.dart';

class PanoSphereView extends StatefulWidget {
  const PanoSphereView({
    super.key,
    required this.imageBytes,
    required this.lon,
    required this.lat,
    required this.fov,
    required this.view,
    required this.onAttitudeChanged,
    required this.onFovChanged,
    required this.onDragStart,
    required this.onDragEnd,
    this.colorFilter,
    this.interactive = true,
  });

  final Uint8List? imageBytes;
  final double lon;
  final double lat;
  final double fov;
  final ProjectionView view;
  final ValueChanged<Offset> onAttitudeChanged;
  final ValueChanged<double> onFovChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ColorFilter? colorFilter;
  final bool interactive;

  @override
  State<PanoSphereView> createState() => _PanoSphereViewState();
}

class _PanoSphereViewState extends State<PanoSphereView> {
  ui.Image? _frame;
  Uint8List? _srcRgba;
  int _srcW = 0;
  int _srcH = 0;
  int _gen = 0;
  double _pinchFov = 75;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  @override
  void didUpdateWidget(covariant PanoSphereView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.imageBytes, widget.imageBytes)) {
      _loadSource();
    } else if (oldWidget.lon != widget.lon ||
        oldWidget.lat != widget.lat ||
        oldWidget.fov != widget.fov ||
        oldWidget.view != widget.view) {
      _scheduleRender();
    }
  }

  Future<void> _loadSource() async {
    final bytes = widget.imageBytes;
    if (bytes == null) {
      setState(() {
        _frame = null;
        _srcRgba = null;
      });
      return;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    _srcRgba = data.buffer.asUint8List();
    _srcW = image.width;
    _srcH = image.height;
    _scheduleRender();
  }

  void _scheduleRender() {
    if (!mounted || _srcRgba == null) return;
    final gen = ++_gen;
    final size = MediaQuery.maybeSizeOf(context) ?? const Size(390, 844);
    final rw = math.max(160, (size.width * 0.55).round());
    final rh = math.max(90, (size.height * 0.55).round());
    final args = _RenderArgs(
      src: _srcRgba,
      srcW: _srcW,
      srcH: _srcH,
      outW: rw,
      outH: rh,
      lon: widget.lon,
      lat: widget.lat,
      fov: widget.fov,
      planet: widget.view == ProjectionView.planet,
    );
    compute(_renderEquirect, args).then((rgba) async {
      if (!mounted || gen != _gen || rgba == null) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        args.outW,
        args.outH,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (!mounted || gen != _gen) {
        image.dispose();
        return;
      }
      setState(() => _frame = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ColoredBox(
      color: const Color(0xFF09090B),
      child: _frame == null
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
            )
          : RawImage(image: _frame, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
    );

    if (widget.colorFilter != null) {
      child = ColorFiltered(colorFilter: widget.colorFilter!, child: child);
    }

    if (!widget.interactive) return child;

    return GestureDetector(
      onScaleStart: (_) {
        widget.onDragStart();
        _pinchFov = widget.fov;
      },
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) {
          widget.onFovChanged((_pinchFov / d.scale).clamp(40.0, 110.0));
        } else {
          widget.onAttitudeChanged(
            Offset(-d.focalPointDelta.dx * 0.18, d.focalPointDelta.dy * 0.14),
          );
        }
      },
      onScaleEnd: (_) => widget.onDragEnd(),
      child: child,
    );
  }
}

class _RenderArgs {
  const _RenderArgs({
    required this.src,
    required this.srcW,
    required this.srcH,
    required this.outW,
    required this.outH,
    required this.lon,
    required this.lat,
    required this.fov,
    required this.planet,
  });

  final Uint8List? src;
  final int srcW;
  final int srcH;
  final int outW;
  final int outH;
  final double lon;
  final double lat;
  final double fov;
  final bool planet;
}

Uint8List? _renderEquirect(_RenderArgs a) {
  final src = a.src;
  if (src == null || a.srcW <= 0 || a.srcH <= 0) return null;

  final out = Uint8List(a.outW * a.outH * 4);
  final aspect = a.outW / a.outH;
  final fovY = degToRad(a.planet ? math.min(a.fov * 1.4, 125) : a.fov);
  final fovX = fovY * aspect;
  final yaw0 = degToRad(a.lon);
  final pitch0 = degToRad(a.planet ? -85 : a.lat);

  for (var y = 0; y < a.outH; y++) {
    final ny = (y + 0.5) / a.outH * 2 - 1;
    for (var x = 0; x < a.outW; x++) {
      final nx = (x + 0.5) / a.outW * 2 - 1;
      double dx;
      double dy;
      double dz;

      if (a.planet) {
        final r = math.sqrt(nx * nx + ny * ny);
        final oi = (y * a.outW + x) * 4;
        if (r > 1.02) {
          out[oi] = 9;
          out[oi + 1] = 9;
          out[oi + 2] = 11;
          out[oi + 3] = 255;
          continue;
        }
        final ang = math.atan2(ny, nx);
        final phi = (1 - r.clamp(0.0, 1.0)) * (math.pi / 2);
        dx = math.cos(phi) * math.cos(ang);
        dy = math.sin(phi);
        dz = math.cos(phi) * math.sin(ang);
      } else {
        final dirX = math.tan(nx * fovX / 2);
        final dirY = -math.tan(ny * fovY / 2);
        const dirZ = 1.0;
        final len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ);
        dx = dirX / len;
        dy = dirY / len;
        dz = dirZ / len;
      }

      final cp = math.cos(pitch0);
      final sp = math.sin(pitch0);
      final y2 = dy * cp - dz * sp;
      final z2 = dy * sp + dz * cp;
      dy = y2;
      dz = z2;

      final cy = math.cos(yaw0);
      final sy = math.sin(yaw0);
      final x3 = dx * cy + dz * sy;
      final z3 = -dx * sy + dz * cy;
      dx = x3;
      dz = z3;

      final theta = math.atan2(dx, dz);
      final phi = math.asin(dy.clamp(-1.0, 1.0));
      final u = normalizeDeg360(radToDeg(theta)) / 360.0;
      final v = (0.5 - radToDeg(phi) / 180.0).clamp(0.0, 0.999999);
      final sampleX = (u * a.srcW).floor() % a.srcW;
      final sampleY = (v * a.srcH).floor().clamp(0, a.srcH - 1);
      final si = (sampleY * a.srcW + sampleX) * 4;
      final oi = (y * a.outW + x) * 4;
      out[oi] = src[si];
      out[oi + 1] = src[si + 1];
      out[oi + 2] = src[si + 2];
      out[oi + 3] = 255;
    }
  }
  return out;
}
