import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/pano_theme.dart';
import 'features/home/camera_lifecycle.dart';
import 'features/home/home_page.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const CameraLifecycle(child: HomePage()),
    ),
  ],
);

class PanoApp extends ConsumerWidget {
  const PanoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PANO 360 Pro',
      debugShowCheckedModeBanner: false,
      theme: buildPanoTheme(),
      routerConfig: _router,
    );
  }
}
