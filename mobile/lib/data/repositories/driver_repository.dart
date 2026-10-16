import '../models/driver_models.dart';
import '../models/navigation_models.dart';

/// Future read contracts, not HTTP endpoints.
///
/// There is deliberately no implementation or fake fallback. The app currently
/// shows an explicit unconnected state. Later implementations must distinguish
/// loading, connection/authentication failures, and successful empty results.
/// Identity and ownership must come from authenticated context, not UI IDs.
abstract interface class DriverRepository {
  Future<DriverProfile> getProfile();

  /// Complete authenticated driver's list, including available recognition and
  /// session information. UI overview counts refer to this complete list.
  /// Unknown session/removal permission must remain unknown, not default to safe.
  Future<List<DriverVehicle>> getVehicles();

  Future<List<ParkingZone>> getAuthorisedZones();

  Future<ParkingSession?> getActiveSession();

  Future<ParkingRoute?> getActiveRoute();

  /// Future coherent session/route/graph read contract, not an HTTP endpoint.
  /// Confirmation permission must come from authenticated driver context.
  Future<NavigationData> getNavigation();

  /// Driver-scoped pages in a stable order. An empty page signals completion.
  /// Include historical plate/zone/level labels where available. History UI
  /// analytics require the complete result, not just the first page.
  Future<List<ParkingSession>> getParkingHistory({
    required int offset,
    required int limit,
  });
}
