import '../../data/models/dashboard_models.dart';
import '../../data/models/driver_models.dart';

/// In-memory state for one signed-in driver, retained across session restoration.
class AllocationNotifications {
  bool _hasBaseline = false;
  final _seen = <String>{};
  final _pending = <String, ActiveParking>{};

  static bool isAllocated(ActiveParking parking) =>
      parking.session.status == ParkingSessionStatus.allocated &&
      parking.session.exitTime == null &&
      parking.session.confirmedAt == null &&
      parking.session.vehicleId == parking.vehicle.id &&
      parking.session.zoneId == parking.zone.id;

  /// Call only with a successful, authoritative session snapshot.
  void update(List<ActiveParking> sessions) {
    final allocated = {
      for (final parking in sessions)
        if (isAllocated(parking)) parking.session.id: parking,
    };
    _pending.removeWhere((id, _) => !allocated.containsKey(id));
    for (final parking in sessions) {
      final id = parking.session.id;
      if (_seen.add(id) && _hasBaseline && allocated.containsKey(id)) {
        _pending[id] = parking;
      } else if (_pending.containsKey(id)) {
        _pending[id] = parking;
      }
    }
    _hasBaseline = true;
  }

  /// Taking a notice consumes it, even if its banner is later hidden/disposed.
  ActiveParking? takeNext(Set<String> paymentSessionIds) {
    while (_pending.isNotEmpty) {
      final id = _pending.keys.first;
      final parking = _pending.remove(id)!;
      if (!paymentSessionIds.contains(id)) return parking;
    }
    return null;
  }
}
