import 'dart:math' as math;

const double earthRadiusM = 6371000.0;

/// Great-circle distance in meters (haversine).
double distanceMeters({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  final phi1 = lat1 * math.pi / 180.0;
  final phi2 = lat2 * math.pi / 180.0;
  final dPhi = (lat2 - lat1) * math.pi / 180.0;
  final dLambda = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
  return 2 * earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Initial bearing from point 1 to point 2, degrees clockwise from north.
double initialBearingDeg({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  final phi1 = lat1 * math.pi / 180.0;
  final phi2 = lat2 * math.pi / 180.0;
  final dLambda = (lon2 - lon1) * math.pi / 180.0;
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  final deg = math.atan2(y, x) * 180.0 / math.pi;
  return (deg % 360.0 + 360.0) % 360.0;
}

String formatDistance(double? meters) {
  if (meters == null) return '—';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';