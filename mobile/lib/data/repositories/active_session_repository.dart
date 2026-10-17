import '../models/dashboard_models.dart';
import '../models/driver_models.dart';
import 'auth_repository.dart';

abstract interface class ActiveSessionRepository {
  Future<List<ActiveParking>> getActiveSessions();
}

class RemoteActiveSessionRepository implements ActiveSessionRepository {
  RemoteActiveSessionRepository(this.api);
  final RemoteAuthRepository api;

  @override
  Future<List<ActiveParking>> getActiveSessions() async {
    final data = await api.getAuthenticated('parking/sessions/active');
    try {
      final rows = (data as Map<String, dynamic>)['sessions'] as List;
      return List.unmodifiable(
        rows.map((value) {
          final row = value as Map<String, dynamic>;
          String text(String key) {
            final value = row[key] as String;
            if (value.trim().isEmpty) throw const FormatException();
            return value;
          }

          DateTime timestamp(String key) {
            final value = DateTime.parse(text(key));
            if (!value.isUtc) throw const FormatException();
            return value;
          }

          final session = ParkingSession(
            id: text('id'),
            vehicleId: text('vehicle_id'),
            zoneId: text('zone_id'),
            status: switch (text('status')) {
              'allocated' => ParkingSessionStatus.allocated,
              'occupied' => ParkingSessionStatus.occupied,
              _ => throw const FormatException(),
            },
            entryTime: timestamp('entry_time'),
            confirmedAt: row['parking_confirmed_at'] == null
                ? null
                : timestamp('parking_confirmed_at'),
            exitTime: row['exit_time'] == null ? null : timestamp('exit_time'),
          );
          return ActiveParking(
            session: session,
            vehicle: DriverVehicle(
              id: session.vehicleId,
              plateNumber: text('plate_number'),
              registrationStatus: text('registration_status'),
              activeSession: session,
              sessionInformationAvailable: true,
            ),
            zone: ParkingZone(
              id: session.zoneId,
              name: text('zone_name'),
              levelId: text('level_id'),
              levelName: text('level_name'),
            ),
            // This endpoint supplies neither capacity, ANPR evidence nor a route.
          );
        }),
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to read active parking sessions. Please retry.',
      );
    }
  }
}
