import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Camera preview that keeps the sensor aspect ratio and crops to fill the
/// screen, instead of stretching the texture under the HUD overlays.
class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover(this.controller, {super.key});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    final isLandscape =
        MediaQuery.maybeOrientationOf(context) == Orientation.landscape;
    final shortSide = preview.width < preview.height
        ? preview.width
        : preview.height;
    final longSide = preview.width < preview.height
        ? preview.height
        : preview.width;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: isLandscape ? longSide : shortSide,
          height: isLandscape ? shortSide : longSide,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
