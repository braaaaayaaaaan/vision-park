import '../models/driver_models.dart';

/// Future read contracts, not HTTP endpoints.
///
/// There is deliberately no implementation or fake fallback. The app currently
/// shows an explicit unconnected state. Later implementations must distinguish
/// loading, connection/authentication failures, and successful empty results.
/// Identity and ownership must come from authenticated context, not UI IDs.
abstract interface class DriverRepository {
  Future<DriverProfile> getProfile();

  Future<List<DriverVehicle>> getVehicles();

  Future<List<ParkingZone>> getAuthorisedZones();

  Future<ParkingSession?> getActiveSession();

  Future<ParkingRoute?> getActiveRoute();

  Future<List<ParkingSession>> getParkingHistory({
    required int offset,
    required int limit,
  });
}
