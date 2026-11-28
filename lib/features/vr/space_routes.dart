abstract final class SpaceRoutes {
  static const home = '/';

  static String detail(String spaceId) => '/space/$spaceId';

  static String capture(String spaceId) => '/space/$spaceId/capture';

  static String tour(String spaceId, {String? pointId}) {
    final base = '/space/$spaceId/tour';
    if (pointId == null) return base;
    return '$base?point=$pointId';
  }
}