import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/navigation_models.dart';
import '../route_geometry.dart';

class ParkingMap extends StatelessWidget {
  const ParkingMap({
    required this.graph,
    required this.routeNodeIds,
    required this.levelId,
    super.key,
  });
  final ParkingGraph graph;
  final List<String> routeNodeIds;
  final String levelId;

  @override
  Widget build(BuildContext context) {
    final geometry = RouteGeometry(graph, routeNodeIds);
    final error = geometry.error;
    if (error != null) return Text('Map Unavailable: $error');
    if (!graph.nodes.any((node) => node.levelId == levelId)) {
      return const Text('No Map Nodes on This Level');
    }
    final level = graph.levels.firstWhere((level) => level.id == levelId);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Route Graph for ${level.name}. ${geometry.segments(levelId).length} directed route segments. '
              'Circle: route start. Ring: destination. Square: floor transition. Fixed route, not live tracking.',
          image: true,
          child: SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
              child: ColoredBox(
                color: AppTheme.background,
                child: CustomPaint(
                  painter: ParkingMapPainter(
                    geometry: geometry,
                    levelId: levelId,
                    routeColour: theme.colorScheme.primary,
                    graphColour: theme.colorScheme.outline,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.small),
        const Text(
          'Circle: Start / Entrance   Ring: Destination   Square: Floor Transition',
        ),
        const Text(
          'Arrows show travel direction. Graph view only; no building geometry or live position.',
        ),
      ],
    );
  }
}

class ParkingMapPainter extends CustomPainter {
  ParkingMapPainter({
    required this.geometry,
    required this.levelId,
    required this.routeColour,
    required this.graphColour,
  });
  final RouteGeometry geometry;
  final String levelId;
  final Color routeColour;
  final Color graphColour;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.error != null) return;
    final nodes = geometry.graph.nodes
        .where((node) => node.levelId == levelId)
        .toList();
    if (nodes.isEmpty) return;
    final projection = CoordinateProjection(nodes, size);
    final byId = {for (final node in nodes) node.id: node};
    for (final edge in geometry.graph.edges) {
      if (edge.isActive &&
          byId.containsKey(edge.fromId) &&
          byId.containsKey(edge.toId)) {
        _arrow(
          canvas,
          projection.project(byId[edge.fromId]!),
          projection.project(byId[edge.toId]!),
          graphColour,
          1.5,
        );
      }
    }
    for (final node in nodes) {
      canvas.drawCircle(
        projection.project(node),
        3,
        Paint()..color = graphColour,
      );
    }
    for (final (start, end) in geometry.segments(levelId)) {
      _arrow(
        canvas,
        projection.project(start),
        projection.project(end),
        routeColour,
        5,
      );
    }
    final route = geometry.orderedNodes;
    for (final (from, to, _) in geometry.transitions) {
      for (final node in [from, to]) {
        if (node.levelId == levelId) {
          canvas.drawRect(
            Rect.fromCenter(
              center: projection.project(node),
              width: 14,
              height: 14,
            ),
            Paint()..color = routeColour,
          );
        }
      }
    }
    if (route.first.levelId == levelId) {
      canvas.drawCircle(
        projection.project(route.first),
        7,
        Paint()..color = routeColour,
      );
    }
    if (route.last.levelId == levelId) {
      canvas.drawCircle(
        projection.project(route.last),
        12,
        Paint()
          ..color = routeColour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _arrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color colour,
    double width,
  ) {
    final delta = end - start;
    if (delta.distance < 0.1) return;
    final paint = Paint()
      ..color = colour
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    final middle = Offset.lerp(start, end, 0.6)!;
    final angle = math.atan2(delta.dy, delta.dx);
    final length = math.min(9.0, delta.distance / 3);
    final path = Path()..moveTo(middle.dx, middle.dy);
    for (final side in [-0.6, 0.6]) {
      final point =
          middle -
          Offset(math.cos(angle + side), math.sin(angle + side)) * length;
      path.lineTo(point.dx, point.dy);
      path.moveTo(middle.dx, middle.dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant ParkingMapPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.levelId != levelId ||
      oldDelegate.routeColour != routeColour ||
      oldDelegate.graphColour != graphColour;
}
