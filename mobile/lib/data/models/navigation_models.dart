import 'dashboard_models.dart';
import 'driver_models.dart';

class MapLevel {
  const MapLevel({required this.id, required this.name});
  final String id;
  final String name;
}

class GraphEdge {
  const GraphEdge({
    required this.fromId,
    required this.toId,
    this.isActive = true,
    this.transitionLabel,
  });
  final String fromId;
  final String toId;
  final bool isActive;
  final String? transitionLabel;
}

class ParkingGraph {
  ParkingGraph({
    required List<MapLevel> levels,
    required List<RouteNode> nodes,
    required List<GraphEdge> edges,
  }) : levels = List.unmodifiable(levels),
       nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges);

  final List<MapLevel> levels;
  final List<RouteNode> nodes;
  final List<GraphEdge> edges;
}

class NavigationData {
  NavigationData({
    required this.parking,
    this.graph,
    this.confirmationAllowed = false,
    List<String> instructions = const [],
  }) : instructions = List.unmodifiable(instructions);

  /// Null means a successful read confirmed no active session.
  final ActiveParking? parking;
  final ParkingGraph? graph;
  final bool confirmationAllowed;
  final List<String> instructions;
}
