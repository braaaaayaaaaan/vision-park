import 'driver_models.dart';

/// Authoritative tenant-scoped figures. Never sum zones to infer company quotas.
class ParkingAvailability {
  ParkingAvailability({
    required this.availableSpaces,
    required this.accessibleZoneCount,
    required List<LevelAvailability> levels,
  }) : levels = List.unmodifiable(levels);

  final int availableSpaces;
  final int accessibleZoneCount;
  final List<LevelAvailability> levels;
}

class LevelAvailability {
  LevelAvailability({
    required this.id,
    required this.name,
    required this.availableSpaces,
    required this.totalSpaces,
    required this.occupancy,
    required List<ZoneAvailability> zones,
  }) : zones = List.unmodifiable(zones);

  final String id;
  final String name;
  final int availableSpaces;
  final int totalSpaces;

  /// Backend-provided occupied proportion, from 0 to 1; null if unavailable.
  final double? occupancy;
  final List<ZoneAvailability> zones;
}

class ZoneAvailability {
  const ZoneAvailability({
    required this.zone,
    required this.totalSpaces,
    required this.occupancy,
  });

  final ParkingZone zone;
  final int totalSpaces;
  final double? occupancy;
}

class ActiveParking {
  const ActiveParking({
    required this.session,
    required this.vehicle,
    required this.zone,
    this.route,
    this.anprInformation,
    this.anprVerifiedAt,
  });

  final ParkingSession session;
  final DriverVehicle vehicle;
  final ParkingZone zone;
  final ParkingRoute? route;
  final String? anprInformation;
  final DateTime? anprVerifiedAt;

  bool get hasValidRoute {
    final candidate = route;
    return session.status == ParkingSessionStatus.allocated &&
        session.vehicleId == vehicle.id &&
        session.zoneId == zone.id &&
        candidate != null &&
        candidate.sessionId == session.id &&
        candidate.distanceMetres.isFinite &&
        candidate.distanceMetres >= 0 &&
        candidate.nodes.isNotEmpty &&
        candidate.nodes.last.levelId == zone.levelId &&
        candidate.nodes.every(
          (node) =>
              node.id.isNotEmpty &&
              node.levelId.isNotEmpty &&
              node.x.isFinite &&
              node.y.isFinite,
        );
  }
}

class DashboardData {
  const DashboardData({
    required this.profile,
    required this.availability,
    required this.activeParking,
  });

  final DriverProfile profile;
  final ParkingAvailability availability;

  /// Null means a successful read confirmed no active session.
  final ActiveParking? activeParking;
}
