import '../models/dashboard_models.dart';
import '../models/driver_models.dart';
import '../models/navigation_models.dart';
import 'active_session_repository.dart';
import 'auth_repository.dart';

abstract interface class AssignedRouteRepository {
  Future<List<ActiveParking>> getSessions();
  Future<NavigationData> getRoute(ActiveParking parking);
}

abstract interface class ParkingConfirmationRepository {
  Future<ParkingSession> confirmParking(ActiveParking parking);
}

class RemoteAssignedRouteRepository
    implements AssignedRouteRepository, ParkingConfirmationRepository {
  RemoteAssignedRouteRepository(this.api);
  final RemoteAuthRepository api;

  @override
  Future<ParkingSession> confirmParking(ActiveParking parking) async {
    final result = await api.postAuthenticated(
      'parking/driver/sessions/${Uri.encodeComponent(parking.session.id)}/confirm',
    );
    try {
      if (result['parking_session_id'] != parking.session.id ||
          result['vehicle_id'] != parking.vehicle.id ||
          result['zone_id'] != parking.zone.id ||
          result['status'] != 'occupied') {
        throw const FormatException();
      }
      final time = DateTime.parse(result['parking_confirmed_at'] as String);
      if (!time.isUtc) throw const FormatException();
      return ParkingSession(
        id: parking.session.id,
        vehicleId: parking.session.vehicleId,
        zoneId: parking.session.zoneId,
        status: ParkingSessionStatus.occupied,
        entryTime: parking.session.entryTime,
        confirmedAt: time,
        plateNumber: parking.session.plateNumber,
        zoneName: parking.session.zoneName,
        levelName: parking.session.levelName,
      );
    } catch (_) {
      throw const AuthFailure(
        'Confirmation could not be verified. Refresh the session before retrying.',
      );
    }
  }

  @override
  Future<List<ActiveParking>> getSessions() =>
      RemoteActiveSessionRepository(api).getActiveSessions();

  @override
  Future<NavigationData> getRoute(ActiveParking parking) async {
    final data = await api.getAuthenticated(
      'parking/sessions/${Uri.encodeComponent(parking.session.id)}/route',
    );
    try {
      if (data['session_id'] != parking.session.id ||
          data['vehicle_id'] != parking.vehicle.id ||
          data['zone_id'] != parking.zone.id) {
        throw const FormatException();
      }
      final nodes = [
        for (final node in data['nodes'] as List)
          RouteNode(
            id: node['id'] as String,
            levelId: node['level_id'] as String,
            x: (node['x'] as num).toDouble(),
            y: (node['y'] as num).toDouble(),
            label: node['label'] as String,
            nodeType: node['node_type'] as String,
          ),
      ];
      final byId = {for (final node in nodes) node.id: node};
      final ids = (data['route_node_ids'] as List).cast<String>();
      if (ids.isEmpty ||
          ids.first != data['entrance_node_id'] ||
          ids.last != data['destination_node_id'] ||
          byId[ids.first]?.nodeType != 'building_entrance' ||
          byId[ids.last]?.nodeType != 'zone_entrance' ||
          byId[ids.last]?.levelId != parking.zone.levelId) {
        throw const FormatException();
      }
      return NavigationData(
        confirmationAllowed:
            parking.session.status == ParkingSessionStatus.allocated &&
            parking.session.confirmedAt == null &&
            parking.session.exitTime == null,
        destinationNodeId: data['destination_node_id'] as String,
        parking: ActiveParking(
          session: parking.session,
          vehicle: parking.vehicle,
          zone: parking.zone,
          route: ParkingRoute(
            sessionId: parking.session.id,
            distanceMetres: (data['distance_meters'] as num).toDouble(),
            nodes: [for (final id in ids) byId[id]!],
          ),
        ),
        graph: ParkingGraph(
          levels: [
            for (final level in data['levels'] as List)
              MapLevel(
                id: level['id'] as String,
                name: level['name'] as String,
              ),
          ],
          nodes: nodes,
          edges: [
            for (final edge in data['edges'] as List)
              GraphEdge(
                fromId: edge['from_id'] as String,
                toId: edge['to_id'] as String,
              ),
          ],
        ),
      );
    } catch (_) {
      throw const AuthFailure(
        'Route and map information could not be verified. Please retry.',
      );
    }
  }
}
