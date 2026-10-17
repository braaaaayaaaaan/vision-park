import '../models/driver_models.dart';
import 'auth_repository.dart';

class HistoryPage {
  const HistoryPage({
    required this.sessions,
    required this.vehicles,
    required this.totalSessions,
    this.nextCursor,
  });
  final List<ParkingSession> sessions;
  final List<DriverVehicle> vehicles;
  final int totalSessions;
  final String? nextCursor;
}

abstract interface class HistoryRepository {
  Future<HistoryPage> getHistory({
    required int days,
    String? vehicleId,
    String? cursor,
  });
}

class RemoteHistoryRepository implements HistoryRepository {
  RemoteHistoryRepository(this.api);
  final RemoteAuthRepository api;

  @override
  Future<HistoryPage> getHistory({
    required int days,
    String? vehicleId,
    String? cursor,
  }) async {
    final path = Uri(
      path: 'parking/history',
      queryParameters: {
        'days': '$days',
        'limit': '30',
        'vehicle_id': ?vehicleId,
        'cursor': ?cursor,
      },
    );
    final data = await api.getAuthenticated(path.toString());
    try {
      final body = data as Map<String, dynamic>;
      DateTime? timestamp(dynamic value) {
        if (value == null) return null;
        final time = DateTime.parse(value as String);
        if (!time.isUtc || time.year < 1982) throw const FormatException();
        return time;
      }

      final sessions = (body['sessions'] as List).map((item) {
        final row = item as Map<String, dynamic>;
        if (row['status'] != 'completed') throw const FormatException();
        return ParkingSession(
          id: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          zoneId: row['zone_id'] as String,
          status: ParkingSessionStatus.completed,
          entryTime: timestamp(row['entry_time'])!,
          confirmedAt: timestamp(row['parking_confirmed_at']),
          exitTime: timestamp(row['exit_time']),
          plateNumber: row['plate_number'] as String,
          zoneName: row['zone_name'] as String?,
          levelName: row['level_name'] as String?,
        );
      }).toList();
      final vehicles = (body['vehicles'] as List)
          .map(
            (item) => DriverVehicle(
              id: item['id'] as String,
              plateNumber: item['plate_number'] as String,
              registrationStatus: 'unknown',
            ),
          )
          .toList();
      final total = body['total_sessions'] as int;
      if (total < sessions.length) throw const FormatException();
      return HistoryPage(
        sessions: List.unmodifiable(sessions),
        vehicles: List.unmodifiable(vehicles),
        totalSessions: total,
        nextCursor: body['next_cursor'] as String?,
      );
    } catch (_) {
      throw const AuthFailure('Unable to read parking history. Please retry.');
    }
  }
}
