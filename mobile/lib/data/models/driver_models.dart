/// Client-side models, independent of widgets and future API transport details.
class DriverProfile {
  const DriverProfile({required this.id, this.tenantName});

  final String id;
  final String? tenantName;
}

class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.plateNumber,
    required this.registrationStatus,
  });

  final String id;
  final String plateNumber;
  final String registrationStatus;
}

enum ParkingSessionStatus { allocated, occupied, completed }

class ParkingSession {
  const ParkingSession({
    required this.id,
    required this.vehicleId,
    required this.zoneId,
    required this.status,
    required this.entryTime,
    this.confirmedAt,
    this.exitTime,
  });

  final String id;
  final String vehicleId;
  final String zoneId;
  final ParkingSessionStatus status;

  /// Instants from the future data source; format only at the UI boundary.
  final DateTime entryTime;
  final DateTime? confirmedAt;
  final DateTime? exitTime;
}

class ParkingZone {
  const ParkingZone({
    required this.id,
    required this.name,
    required this.levelId,
    required this.levelName,
    required this.availableCapacity,
  });

  final String id;
  final String name;
  final String levelId;
  final String levelName;

  /// Supplied by the backend, not recalculated from partial client records.
  final int availableCapacity;
}

class RouteNode {
  const RouteNode({
    required this.id,
    required this.levelId,
    required this.x,
    required this.y,
  });

  final String id;
  final String levelId;
  final double x;
  final double y;
}

class ParkingRoute {
  ParkingRoute({
    required this.sessionId,
    required this.distanceMetres,
    required List<RouteNode> nodes,
  }) : nodes = List.unmodifiable(nodes);

  final String sessionId;
  final double distanceMetres;

  /// Ordered path; coordinate units must be agreed during API integration.
  final List<RouteNode> nodes;
}
