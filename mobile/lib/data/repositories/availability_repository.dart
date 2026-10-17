import '../models/dashboard_models.dart';
import '../models/driver_models.dart';
import 'auth_repository.dart';

abstract interface class AvailabilityRepository {
  Future<ParkingAvailability> getAvailability();
}

class RemoteAvailabilityRepository implements AvailabilityRepository {
  RemoteAvailabilityRepository(this.api);
  final RemoteAuthRepository api;

  @override
  Future<ParkingAvailability> getAvailability() async {
    final data = await api.getAuthenticated('parking/availability');
    try {
      int count(dynamic value) {
        if (value is! int || value < 0) throw const FormatException();
        return value;
      }

      double? occupancy(dynamic value) {
        if (value == null) return null;
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw const FormatException();
        }
        return value.toDouble();
      }

      return ParkingAvailability(
        availableSpaces: count(data['available_spaces']),
        accessibleZoneCount: count(data['accessible_zone_count']),
        levels: [
          for (final level in data['levels'] as List)
            LevelAvailability(
              id: level['id'] as String,
              name: level['name'] as String,
              availableSpaces: count(level['available_spaces']),
              totalSpaces: count(level['total_spaces']),
              occupancy: occupancy(level['occupancy']),
              zones: [
                for (final zone in level['zones'] as List)
                  ZoneAvailability(
                    zone: ParkingZone(
                      id: zone['id'] as String,
                      name: zone['name'] as String,
                      levelId: zone['level_id'] as String,
                      levelName: zone['level_name'] as String,
                      availableCapacity: count(zone['available_spaces']),
                    ),
                    totalSpaces: count(zone['total_spaces']),
                    occupancy: occupancy(zone['occupancy']),
                  ),
              ],
            ),
        ],
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to read parking availability. Please retry.',
      );
    }
  }
}
