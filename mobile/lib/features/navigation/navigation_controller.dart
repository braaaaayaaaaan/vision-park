import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/models/dashboard_models.dart';
import '../../data/repositories/assigned_route_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/navigation_models.dart';
import '../../data/repositories/driver_repository.dart';
import 'route_geometry.dart';

enum NavigationStatus { disconnected, loading, ready, error }

class NavigationController extends ChangeNotifier {
  NavigationController({this.repository, this.routeRepository});
  final AssignedRouteRepository? routeRepository;
  List<ActiveParking> sessions = const [];
  String? selectedSessionId;
  String? message;
  bool confirming = false;
  String? confirmationMessage;
  bool get hasConfirmationService =>
      routeRepository is ParkingConfirmationRepository;
  final DriverRepository? repository;
  NavigationStatus status = NavigationStatus.disconnected;
  NavigationData? data;
  String? selectedLevelId;
  bool _disposed = false;

  bool get hasActiveSession =>
      data?.parking != null &&
      data!.parking!.session.status != ParkingSessionStatus.completed;

  RouteGeometry? get geometry {
    final graph = data?.graph;
    final route = data?.parking?.route;
    return graph == null || route == null
        ? null
        : RouteGeometry(graph, route.nodes.map((node) => node.id).toList());
  }

  String? get routeError {
    final parking = data?.parking;
    final route = parking?.route;
    if (route == null || geometry == null) {
      return 'Route or map information is unavailable.';
    }
    if (route.sessionId != parking!.session.id ||
        parking.vehicle.id != parking.session.vehicleId ||
        parking.zone.id != parking.session.zoneId ||
        !route.distanceMetres.isFinite ||
        route.distanceMetres < 0) {
      return 'Route and session information do not match.';
    }
    final issue = geometry!.error;
    if (issue != null) return issue;
    if (geometry!.orderedNodes.last.levelId != parking.zone.levelId) {
      return 'The route does not reach the allocated level.';
    }
    if (data!.destinationNodeId != null &&
        geometry!.orderedNodes.last.id != data!.destinationNodeId) {
      return 'The route does not reach the assigned zone entrance.';
    }
    return null;
  }

  bool get canConfirm =>
      !_disposed &&
      !confirming &&
      status == NavigationStatus.ready &&
      hasActiveSession &&
      data!.confirmationAllowed &&
      data!.parking!.session.status == ParkingSessionStatus.allocated &&
      data!.parking!.session.exitTime == null &&
      data!.parking!.session.confirmedAt == null &&
      data!.parking!.session.vehicleId == data!.parking!.vehicle.id &&
      data!.parking!.session.zoneId == data!.parking!.zone.id;

  void selectLevel(String value) {
    if (data?.graph?.levels.any((level) => level.id == value) != true) return;
    selectedLevelId = value;
    notifyListeners();
  }

  Future<void> load() async {
    if (confirming) return;
    if (routeRepository != null) {
      await _loadAssigned(refreshSessions: true);
      return;
    }
    final repository = this.repository;
    if (repository == null || _disposed || status == NavigationStatus.loading) {
      return;
    }
    status = NavigationStatus.loading;
    data = null;
    selectedLevelId = null;
    notifyListeners();
    try {
      final result = await repository.getNavigation();
      if (_disposed) return;
      data = result;
      final levels = result.graph?.levels ?? [];
      final startLevel = geometry?.orderedNodes.firstOrNull?.levelId;
      selectedLevelId = startLevel ?? levels.firstOrNull?.id;
      status = NavigationStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = NavigationStatus.error;
    }
    notifyListeners();
  }

  Future<void> selectSession(String id) async {
    if (confirming ||
        status == NavigationStatus.loading ||
        !sessions.any((item) => item.session.id == id)) {
      return;
    }
    selectedSessionId = id;
    await _loadAssigned(refreshSessions: false);
  }

  Future<void> _loadAssigned({required bool refreshSessions}) async {
    if (_disposed || status == NavigationStatus.loading) return;
    status = NavigationStatus.loading;
    data = null;
    message = null;
    confirmationMessage = null;
    selectedLevelId = null;
    notifyListeners();
    try {
      if (refreshSessions) {
        final result = await routeRepository!.getSessions();
        if (_disposed) return;
        sessions = result;
      }
      final parking =
          sessions
              .where((item) => item.session.id == selectedSessionId)
              .firstOrNull ??
          sessions
              .where(
                (item) => item.session.status == ParkingSessionStatus.allocated,
              )
              .firstOrNull ??
          sessions.firstOrNull;
      selectedSessionId = parking?.session.id;
      final result =
          parking == null ||
              parking.session.status != ParkingSessionStatus.allocated
          ? NavigationData(parking: parking)
          : await routeRepository!.getRoute(parking);
      if (_disposed) return;
      data = result;
      selectedLevelId =
          geometry?.orderedNodes.firstOrNull?.levelId ??
          result.graph?.levels.firstOrNull?.id;
      status = NavigationStatus.ready;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      message = error.message;
      status = NavigationStatus.error;
    } catch (_) {
      if (_disposed) return;
      message =
          'Unable to load navigation. Check your connection and try again.';
      status = NavigationStatus.error;
    }
    notifyListeners();
  }

  Future<bool> confirmSelected(String sessionId) async {
    if (!canConfirm ||
        !hasConfirmationService ||
        data!.parking!.session.id != sessionId) {
      return false;
    }
    final previous = data!;
    final parking = previous.parking!;
    confirming = true;
    confirmationMessage = null;
    notifyListeners();
    try {
      final session = await (routeRepository as ParkingConfirmationRepository)
          .confirmParking(parking);
      if (_disposed) return false;
      final updated = ActiveParking(
        session: session,
        vehicle: DriverVehicle(
          id: parking.vehicle.id,
          plateNumber: parking.vehicle.plateNumber,
          registrationStatus: parking.vehicle.registrationStatus,
          lastRecognitionAt: parking.vehicle.lastRecognitionAt,
          activeSession: session,
          sessionInformationAvailable: true,
          removalPermitted: parking.vehicle.removalPermitted,
        ),
        zone: parking.zone,
        route: parking.route,
        anprInformation: parking.anprInformation,
        anprVerifiedAt: parking.anprVerifiedAt,
      );
      data = NavigationData(
        parking: updated,
        graph: previous.graph,
        destinationNodeId: previous.destinationNodeId,
        instructions: previous.instructions,
      );
      sessions = [
        for (final item in sessions)
          item.session.id == session.id ? updated : item,
      ];
      confirmationMessage = 'Parking confirmed. Your session is now occupied.';
      return true;
    } on AuthFailure catch (error) {
      if (!_disposed) confirmationMessage = error.message;
      return false;
    } catch (_) {
      if (!_disposed) confirmationMessage = 'Unable to confirm parking. Refresh the session to check its status before retrying.';
      return false;
    } finally {
      confirming = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
