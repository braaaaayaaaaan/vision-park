import '../models/driver_models.dart';
import 'auth_repository.dart';

abstract interface class VehicleRepository {
  Future<List<DriverVehicle>> getVehicles();
  Future<void> register(String plate);
  Future<void> remove(String id);
}

class RemoteVehicleRepository implements VehicleRepository {
  RemoteVehicleRepository(this.api);
  final RemoteAuthRepository api;
  @override
  Future<List<DriverVehicle>> getVehicles() async {
    final data = await api.getAuthenticated('vehicles');
    try {
      return [
        for (final row in data as List) _vehicle(row as Map<String, dynamic>),
      ];
    } catch (_) {
      throw const AuthFailure('Unable to read your vehicles. Please retry.');
    }
  }

  DriverVehicle _vehicle(Map<String, dynamic> row) {
    final active = row['active_session'];
    return DriverVehicle(
      id: row['id'] as String,
      plateNumber: row['plate_number'] as String,
      registrationStatus: row['registration_status'] as String,
      sessionInformationAvailable: row['session_information_available'] as bool,
      removalPermitted: row['removal_permitted'] as bool,
      removalReason: row['removal_reason'] as String?,
      activeSession: active == null
          ? null
          : ParkingSession(
              id: active['id'] as String,
              vehicleId: active['vehicle_id'] as String,
              zoneId: active['zone_id'] as String,
              zoneName: active['zone_name'] as String?,
              levelName: active['level_name'] as String?,
              status: switch (active['status']) {
                'allocated' => ParkingSessionStatus.allocated,
                'occupied' => ParkingSessionStatus.occupied,
                _ => throw const FormatException(),
              },
              entryTime: DateTime.parse(active['entry_time'] as String),
              confirmedAt: active['parking_confirmed_at'] == null
                  ? null
                  : DateTime.parse(active['parking_confirmed_at'] as String),
            ),
    );
  }

  @override
  Future<void> register(String plate) async {
    final data = await api.postAuthenticated(
      'vehicles',
      body: {'plate_number': plate.trim().toUpperCase()},
    );
    if (data is! Map ||
        data['registration_status'] != 'pending' ||
        data['plate_number'] != plate.trim().toUpperCase()) {
      throw const AuthFailure(
        'Registration could not be verified. Refresh your vehicles before retrying.',
      );
    }
  }

  @override
  Future<void> remove(String id) async {
    final data = await api.deleteAuthenticated(
      'vehicles/${Uri.encodeComponent(id)}',
    );
    if (data is! Map ||
        data['status'] != 'removed' ||
        data['vehicle_id'] != id) {
      throw const AuthFailure(
        'Removal could not be verified. Refresh your vehicles before retrying.',
      );
    }
  }
}
