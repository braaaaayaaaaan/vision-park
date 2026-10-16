import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/driver_models.dart';
import '../../data/models/navigation_models.dart';

/// Validates the directed path without computing or inventing a new route.
class RouteGeometry {
  RouteGeometry(this.graph, List<String> routeIds)
    : routeIds = List.unmodifiable(routeIds);

  final ParkingGraph graph;
  final List<String> routeIds;

  String? get error {
    final levels = graph.levels.map((level) => level.id).toSet();
    final nodes = {for (final node in graph.nodes) node.id: node};
    if (levels.isEmpty ||
        levels.contains('') ||
        levels.length != graph.levels.length ||
        nodes.length != graph.nodes.length ||
        nodes.containsKey('')) {
      return 'Map identifiers are missing or duplicated.';
    }
    if (graph.nodes.any(
      (node) =>
          !levels.contains(node.levelId) ||
          !node.x.isFinite ||
          !node.y.isFinite,
    )) {
      return 'Map coordinates or level information are invalid.';
    }
    for (final level in graph.levels) {
      final local = graph.nodes
          .where((node) => node.levelId == level.id)
          .toList();
      if (local.isNotEmpty &&
          (!(_max(local, true) - _min(local, true)).isFinite ||
              !(_max(local, false) - _min(local, false)).isFinite)) {
        return 'Map coordinate bounds are invalid.';
      }
    }
    if (graph.edges
        .where((edge) => edge.isActive)
        .any(
          (edge) =>
              !nodes.containsKey(edge.fromId) || !nodes.containsKey(edge.toId),
        )) {
      return 'The graph contains an edge with missing nodes.';
    }
    if (routeIds.isEmpty || routeIds.any((id) => !nodes.containsKey(id))) {
      return 'The route is missing one or more map nodes.';
    }
    for (var i = 1; i < routeIds.length; i++) {
      if (!graph.edges.any(
        (edge) =>
            edge.isActive &&
            edge.fromId == routeIds[i - 1] &&
            edge.toId == routeIds[i],
      )) {
        return 'The route contains a missing or incorrectly directed link.';
      }
    }
    return null;
  }

  List<RouteNode> get orderedNodes {
    if (error != null) return const [];
    final byId = {for (final node in graph.nodes) node.id: node};
    return routeIds.map((id) => byId[id]!).toList();
  }

  List<(RouteNode, RouteNode)> segments(String levelId) {
    final nodes = orderedNodes;
    return [
      for (var i = 1; i < nodes.length; i++)
        if (nodes[i - 1].levelId == levelId && nodes[i].levelId == levelId)
          (nodes[i - 1], nodes[i]),
    ];
  }

  List<(RouteNode, RouteNode, String)> get transitions {
    final nodes = orderedNodes;
    return [
      for (var i = 1; i < nodes.length; i++)
        if (nodes[i - 1].levelId != nodes[i].levelId)
          (
            nodes[i - 1],
            nodes[i],
            graph.edges
                    .firstWhere(
                      (edge) =>
                          edge.isActive &&
                          edge.fromId == nodes[i - 1].id &&
                          edge.toId == nodes[i].id,
                    )
                    .transitionLabel ??
                'Floor Transition',
          ),
    ];
  }

  static double _min(List<RouteNode> nodes, bool x) =>
      nodes.map((n) => x ? n.x : n.y).reduce(math.min);
  static double _max(List<RouteNode> nodes, bool x) =>
      nodes.map((n) => x ? n.x : n.y).reduce(math.max);
}

/// Aspect-preserving projection. Positive Y points down in the drawing contract.
class CoordinateProjection {
  CoordinateProjection(List<RouteNode> nodes, this.size) {
    minX = nodes.isEmpty ? 0 : RouteGeometry._min(nodes, true);
    minY = nodes.isEmpty ? 0 : RouteGeometry._min(nodes, false);
    final width = nodes.isEmpty ? 0.0 : RouteGeometry._max(nodes, true) - minX;
    final height = nodes.isEmpty
        ? 0.0
        : RouteGeometry._max(nodes, false) - minY;
    final usableWidth = math.max(1.0, size.width - 64);
    final usableHeight = math.max(1.0, size.height - 64);
    // Normalise before scaling so very small coordinate spans cannot overflow.
    span = math.max(width, height);
    if (span == 0) span = 1;
    final normalWidth = width / span;
    final normalHeight = height / span;
    scale = width == 0 && height == 0
        ? 1
        : math.min(
            width == 0 ? double.infinity : usableWidth / normalWidth,
            height == 0 ? double.infinity : usableHeight / normalHeight,
          );
    origin = Offset(
      (size.width - normalWidth * scale) / 2,
      (size.height - normalHeight * scale) / 2,
    );
  }
  final Size size;
  late final double minX;
  late final double minY;
  late final double scale;
  late double span;
  late final Offset origin;
  Offset project(RouteNode node) =>
      origin +
      Offset((node.x - minX) / span * scale, (node.y - minY) / span * scale);
}
