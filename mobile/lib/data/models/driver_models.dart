/// Client-side models, independent of widgets and future API transport details.
class DriverProfile {
  const DriverProfile({
    required this.id,
    this.tenantName,
    this.fullName,
    this.email,
    this.isActive,
  });

  final String id;
  final String? tenantName;

  /// Null personal fields on a successful profile read mean not provided.
  final String? fullName;
  final String? email;

  /// Null means status is unavailable, not inactive.
  final bool? isActive;
}

class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.plateNumber,
    required this.registrationStatus,
    this.lastRecognitionAt,
    this.activeSession,
    this.sessionInformationAvailable = false,
    this.removalPermitted = false,
  });

  final String id;
  final String plateNumber;
  final String registrationStatus;
  final DateTime? lastRecognitionAt;
  final ParkingSession? activeSession;

  /// False means unknown, not a confirmed absence of an active session.
  final bool sessionInformationAvailable;

  /// Future server-authorised permission; the server must recheck on removal.
  final bool removalPermitted;

  String get approvalLabel => switch (registrationStatus) {
    'approved' => 'Approved',
    'pending' => 'Pending Approval',
    'rejected' => 'Rejected',
    _ => 'Approval Status Unavailable',
  };

  bool get hasActiveSession =>
      activeSession?.status == ParkingSessionStatus.allocated ||
      activeSession?.status == ParkingSessionStatus.occupied;

  bool get canRemove =>
      removalPermitted && sessionInformationAvailable && !hasActiveSession;
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
    this.plateNumber,
    this.zoneName,
    this.levelName,
  });

  final String id;
  final String vehicleId;
  final String zoneId;
  final ParkingSessionStatus status;

  /// Instants from the future data source; format only at the UI boundary.
  final DateTime entryTime;
  final DateTime? confirmedAt;
  final DateTime? exitTime;

  /// Optional historical display values, independent of current registrations.
  final String? plateNumber;
  final String? zoneName;
  final String? levelName;
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
    this.label,
    this.nodeType,
  });

  final String id;
  final String levelId;
  final double x;
  final double y;
  final String? label;
  final String? nodeType;
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
