import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/models/navigation_models.dart';
import '../../data/repositories/driver_repository.dart';
import 'route_geometry.dart';

enum NavigationStatus { disconnected, loading, ready, error }

class NavigationController extends ChangeNotifier {
  NavigationController({this.repository});
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
    return null;
  }

  bool get canConfirm =>
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
