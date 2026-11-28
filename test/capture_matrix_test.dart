import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pano_360_pro/domain/capture_matrix.dart';
import 'package:pano_360_pro/domain/capture_point.dart';
import 'package:pano_360_pro/features/capture/stitch_projector.dart';

void main() {
  test('standard matrix has 14 points across three rings', () {
    final pts = createStandard14Points();
    expect(pts.length, 14);
    expect(pts.where((e) => e.ring == CaptureRing.mid).length, 8);
    expect(pts.where((e) => e.ring == CaptureRing.upper).length, 3);
    expect(pts.where((e) => e.ring == CaptureRing.lower).length, 3);
  });

  test('stitch projector blends a frame into buffer', () {
    final stitcher = StitchProjector(width: 256, height: 128);
    final frame = img.Image(width: 64, height: 48, numChannels: 4);
    img.fill(frame, color: img.ColorRgba8(255, 128, 0, 255));
    stitcher.projectFrame(frame, yawDeg: 180, pitchDeg: 0);
    // yaw 180° maps to horizontal center of equirectangular buffer
    final sample = stitcher.buffer.getPixel(128, 64);
    expect(sample.r.toInt() > 100, isTrue);
  });

  test('yaw offset rotates the whole matrix and wraps at 360°', () {
    final rotated = createStandard14Points(yawOffsetDeg: 350);
    final mids = rotated.where((e) => e.ring == CaptureRing.mid).toList();
    expect(mids.first.yaw, closeTo(350, 1e-9));
    expect(mids[1].yaw, closeTo(35, 1e-9));
    expect(mids[7].yaw, closeTo(305, 1e-9));

    final uppers = rotated.where((e) => e.ring == CaptureRing.upper).toList();
    expect(uppers.map((e) => e.pitch), everyElement(45));
    final lowers = rotated.where((e) => e.ring == CaptureRing.lower).toList();
    expect(lowers.map((e) => e.pitch), everyElement(-45));
  });

  test('capture point ids stay unique after rotation', () {
    final pts = createStandard14Points(yawOffsetDeg: 17.5);
    expect(pts.map((e) => e.id).toSet(), hasLength(pts.length));
    expect(
      pts.map((e) => e.yaw).every((yaw) => yaw >= 0 && yaw < 360),
      isTrue,
    );
  });
}
