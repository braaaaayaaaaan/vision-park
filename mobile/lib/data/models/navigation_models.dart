import 'dashboard_models.dart';
import 'driver_models.dart';

class MapLevel {
  const MapLevel({
    required this.id,
    required this.name,
    this.floorPlan,
    this.levelNumber,
  });
  final String id;
  final String name;
  final MapFloorPlan? floorPlan;
  final int? levelNumber;
}

class MapFloorPlan {
  const MapFloorPlan({
    required this.width,
    required this.height,
    required this.revision,
    required this.publicationRevision,
    required this.imagePath,
  });
  final int width;
  final int height;
  final int revision;
  final int publicationRevision;
  final String imagePath;
}

class GraphEdge {
  const GraphEdge({
    required this.fromId,
    required this.toId,
    this.isActive = true,
    this.transitionLabel,
    this.distanceMetres,
  });
  final String fromId;
  final String toId;
  final bool isActive;
  final String? transitionLabel;

  /// Null means absent in a legacy/local graph, never an inferred zero.
  final double? distanceMetres;
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
    this.destinationNodeId,
    List<String> instructions = const [],
  }) : instructions = List.unmodifiable(instructions);

  /// Null means a successful read confirmed no active session.
  final ActiveParking? parking;
  final ParkingGraph? graph;
  final bool confirmationAllowed;
  final String? destinationNodeId;
  final List<String> instructions;
}
