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
}
