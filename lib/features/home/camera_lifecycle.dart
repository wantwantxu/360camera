import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/pano_session.dart';

/// Pauses/resumes the camera when the app is backgrounded.
class CameraLifecycle extends ConsumerStatefulWidget {
  const CameraLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CameraLifecycle> createState() => _CameraLifecycleState();
}

class _CameraLifecycleState extends ConsumerState<CameraLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(panoSessionProvider.notifier);
    final cam = session.cameraController;
    if (cam == null || !cam.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      cam.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      cam.resumePreview();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
