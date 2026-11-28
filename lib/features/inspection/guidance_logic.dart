import '../../core/constants.dart';
import 'inspection_state.dart';

/// Whether the current GPS fix is confident enough to tell the user that they
/// have reached the waypoint. Poor accuracy never blocks manual confirmation,
/// it only prevents an automatic "已到达" hint.
bool isWithinArrivalRange({
  required double? distanceM,
  required double? accuracyM,
  required double radiusM,
  double maxAccuracyM = PanoConstants.waypointMaxGpsAccuracyM,
}) {
  if (distanceM == null || accuracyM == null) return false;
  return accuracyM <= maxAccuracyM && distanceM <= radiusM;
}

/// True when the GPS fix is usable for showing a distance at all.
bool hasUsableGpsFix({
  required double? distanceM,
  required double? accuracyM,
  double maxAccuracyM = PanoConstants.waypointMaxGpsAccuracyM,
}) {
  if (distanceM == null || accuracyM == null) return false;
  return accuracyM <= maxAccuracyM * 2;
}

/// Stage transition for the guidance flow after position is arranged.
///
/// Uses hysteresis: entering "ready" requires alignment within
/// [PanoConstants.waypointAlignEnterDeg], leaving requires exceeding
/// [PanoConstants.waypointAlignExitDeg]. No direction is fabricated when the
/// compass is unavailable — the flow waits for sensor data or manual confirm.
InspectionStage evaluateGuidanceStage({
  required InspectionStage current,
  required bool arrivalConfirmed,
  required bool hasTargetAzimuth,
  required bool compassReliable,
  required bool manualDirectionConfirmed,
  required double? deltaDeg,
}) {
  if (!arrivalConfirmed) return InspectionStage.positioning;
  if (!hasTargetAzimuth) return InspectionStage.ready;
  if (manualDirectionConfirmed) return InspectionStage.ready;
  if (!compassReliable || deltaDeg == null) return InspectionStage.aligning;

  final magnitude = deltaDeg.abs();
  if (current == InspectionStage.ready) {
    return magnitude <= PanoConstants.waypointAlignExitDeg
        ? InspectionStage.ready
        : InspectionStage.aligning;
  }
  return magnitude <= PanoConstants.waypointAlignEnterDeg
      ? InspectionStage.ready
      : InspectionStage.aligning;
}

/// Direction quality used by the HUD copy/colors.
enum DirectionQuality { unavailable, noTarget, far, near, aligned }

DirectionQuality directionQuality({
  required bool hasTargetAzimuth,
  required bool compassReliable,
  required double? deltaDeg,
}) {
  if (!hasTargetAzimuth) return DirectionQuality.noTarget;
  if (!compassReliable || deltaDeg == null) return DirectionQuality.unavailable;
  final magnitude = deltaDeg.abs();
  if (magnitude <= PanoConstants.waypointAlignEnterDeg) {
    return DirectionQuality.aligned;
  }
  if (magnitude <= PanoConstants.waypointAlignNearDeg) {
    return DirectionQuality.near;
  }
  return DirectionQuality.far;
}