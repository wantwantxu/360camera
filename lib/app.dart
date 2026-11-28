import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/pano_theme.dart';
import 'features/home/camera_lifecycle.dart';
import 'features/vr/space_capture_page.dart';
import 'features/vr/space_detail_page.dart';
import 'features/vr/spaces_home_page.dart';
import 'features/vr/vr_tour_page.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SpacesHomePage(),
    ),
    GoRoute(
      path: '/space/:spaceId',
      builder: (context, state) {
        final spaceId = state.pathParameters['spaceId']!;
        return SpaceDetailPage(spaceId: spaceId);
      },
    ),
    GoRoute(
      path: '/space/:spaceId/capture',
      builder: (context, state) {
        final spaceId = state.pathParameters['spaceId']!;
        return CameraLifecycle(child: SpaceCapturePage(spaceId: spaceId));
      },
    ),
    GoRoute(
      path: '/space/:spaceId/tour',
      builder: (context, state) {
        final spaceId = state.pathParameters['spaceId']!;
        return VrTourPage(
          spaceId: spaceId,
          initialPointId: state.uri.queryParameters['point'],
        );
      },
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