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
  bool confirmationSucceeded = false;
  bool get hasConfirmationService =>
      routeRepository is ParkingConfirmationRepository;
  final DriverRepository? repository;
  NavigationStatus status = NavigationStatus.disconnected;
  NavigationData? data;
  String? selectedLevelId;
  bool _disposed = false;
  bool _loadingAssigned = false;
  bool get refreshing => _loadingAssigned;
  DateTime? verifiedAt;
  Future<void>? _assignedRead;
  ActiveParking? _requestedAllocation;

  void clearAllocationTarget() => _requestedAllocation = null;

  /// Revalidate an explicit notification target before fetching any route.
  Future<void> openAllocation(ActiveParking allocation) async {
    await _assignedRead;
    if (_disposed || confirming || routeRepository == null) return;
    _requestedAllocation = allocation;
    await _trackAssigned(
      _loadAssigned(refreshSessions: true, requireAllocated: true),
    );
  }

  /// A current session card may also point to an already parked vehicle.
  Future<void> openSession(ActiveParking parking) async {
    if (parking.session.status == ParkingSessionStatus.allocated) {
      return openAllocation(parking);
    }
    await _assignedRead;
    if (_disposed || confirming || routeRepository == null) return;
    _requestedAllocation = parking;
    await _trackAssigned(_loadAssigned(refreshSessions: true));
  }

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
      return 'Route and map information are unavailable.';
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
      !refreshing &&
      message == null &&
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

  Future<void> load({bool background = false}) async {
    if (confirming) return;
    if (routeRepository != null) {
      final current = _assignedRead;
      if (current != null) return current;
      final work = _loadAssigned(refreshSessions: true, background: background);
      await _trackAssigned(work);
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
    await _assignedRead;
    if (_disposed ||
        confirming ||
        status == NavigationStatus.loading ||
        !sessions.any((item) => item.session.id == id)) {
      return;
    }
    selectedSessionId = id;
    _requestedAllocation = null;
    await _trackAssigned(_loadAssigned(refreshSessions: false));
  }

  Future<void> _trackAssigned(Future<void> work) async {
    _assignedRead = work;
    try {
      await work;
    } finally {
      if (identical(_assignedRead, work)) _assignedRead = null;
    }
  }

  Future<void> refreshAfterChange() async {
    await _assignedRead;
    if (!_disposed) await load(background: true);
  }

  // The shared transport owns bounded retries; never multiply them here.
  Future<T> _readNavigation<T>(Future<T> Function() read) => read();

  Future<void> _loadAssigned({
    required bool refreshSessions,
    bool background = false,
    bool requireAllocated = false,
  }) async {
    if (_disposed || _loadingAssigned || status == NavigationStatus.loading) {
      return;
    }
    _loadingAssigned = true;
    final previous = data;
    final previousLevel = selectedLevelId;
    final keepData =
        status == NavigationStatus.ready &&
        previous != null &&
        (selectedSessionId == null ||
            selectedSessionId == previous.parking?.session.id) &&
        (_requestedAllocation == null ||
            _requestedAllocation!.session.id == previous.parking?.session.id);
    var retainPrevious = keepData;
    if (!keepData) {
      status = NavigationStatus.loading;
      data = null;
      selectedLevelId = null;
      message = null;
      confirmationMessage = null;
      confirmationSucceeded = false;
    }
    message = null;
    notifyListeners();
    try {
      if (refreshSessions) {
        final result = await _readNavigation(routeRepository!.getSessions);
        if (_disposed) return;
        sessions = result;
      }
      final requested = _requestedAllocation;
      final parking = requested != null
          ? sessions
                .where(
                  (item) =>
                      item.session.id == requested.session.id &&
                      item.session.vehicleId == requested.session.vehicleId &&
                      item.session.zoneId == requested.session.zoneId &&
                      item.vehicle.id == requested.vehicle.id &&
                      item.zone.id == requested.zone.id &&
                      item.session.exitTime == null &&
                      (!requireAllocated ||
                          (item.session.status ==
                                  ParkingSessionStatus.allocated &&
                              item.session.confirmedAt == null)),
                )
                .firstOrNull
          : sessions
                    .where((item) => item.session.id == selectedSessionId)
                    .firstOrNull ??
                sessions
                    .where(
                      (item) =>
                          item.session.status == ParkingSessionStatus.allocated,
                    )
                    .firstOrNull ??
                sessions.firstOrNull;
      selectedSessionId = parking?.session.id;
      final oldParking = previous?.parking;
      retainPrevious =
          keepData &&
          parking?.session.id == oldParking?.session.id &&
          parking?.session.zoneId == oldParking?.session.zoneId &&
          parking?.session.status == oldParking?.session.status;
      if (keepData &&
          parking != null &&
          oldParking != null &&
          previous.graph != null &&
          oldParking.route?.nodes.every(
                (node) => previous.graph!.levels.any(
                  (level) =>
                      level.id == node.levelId && level.floorPlan != null,
                ),
              ) ==
              true &&
          parking.session.id == oldParking.session.id &&
          parking.session.status == oldParking.session.status &&
          parking.session.confirmedAt == oldParking.session.confirmedAt &&
          parking.session.exitTime == oldParking.session.exitTime &&
          parking.zone.id == oldParking.zone.id) {
        // Session snapshots are cheap. Keep the existing route/map instance
        // while its assignment is unchanged, including the selected floor.
        verifiedAt = DateTime.now();
        message = null;
        return;
      }
      final result =
          parking == null ||
              parking.session.status != ParkingSessionStatus.allocated
          ? NavigationData(parking: parking)
          : await _readNavigation(() => routeRepository!.getRoute(parking));
      if (_disposed) return;
      data = result;
      message = null;
      selectedLevelId =
          (keepData &&
                  result.graph?.levels.any(
                        (level) => level.id == previousLevel,
                      ) ==
                      true
              ? previousLevel
              : null) ??
          geometry?.orderedNodes.firstOrNull?.levelId ??
          result.graph?.levels.firstOrNull?.id;
      status = NavigationStatus.ready;
      verifiedAt = DateTime.now();
    } on AuthFailure catch (error) {
      if (_disposed) return;
      if (kDebugMode) {
        debugPrint(
          'Navigation read failed: ${error.code ?? "unclassified_response"}',
        );
      }
      message = error.message;
      if (!retainPrevious ||
          (!error.retryable && error.code != 'read_cancelled')) {
        status = NavigationStatus.error;
        data = null;
        verifiedAt = null;
      } else {
        selectedSessionId = previous?.parking?.session.id;
      }
    } catch (_) {
      if (_disposed) return;
      message =
          'Unable to load navigation. Check your connection and try again.';
      if (!retainPrevious) {
        status = NavigationStatus.error;
        data = null;
        verifiedAt = null;
      }
    } finally {
      _loadingAssigned = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> confirmSelected(String sessionId) async {
    await _assignedRead;
    if (!canConfirm ||
        !hasConfirmationService ||
        data!.parking!.session.id != sessionId) {
      return false;
    }
    final previous = data!;
    final parking = previous.parking!;
    confirming = true;
    confirmationMessage = null;
    confirmationSucceeded = false;
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
      confirmationMessage = 'Your parking has been confirmed. Your session is now marked as occupied.';
      confirmationSucceeded = true;
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
