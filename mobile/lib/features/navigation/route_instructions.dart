import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/navigation_models.dart';
import 'route_geometry.dart';
import 'route_preview.dart';

enum RouteManeuver { departure, straight, left, right, ramp, arrival }

enum RouteTurn { straight, left, right, review }

/// Small per-node bends are merged, not accumulated into an invented junction.
/// Thresholds are prototype heuristics; the configured lanes remain authoritative.
RouteTurn? classifyRouteTurn(Offset incoming, Offset outgoing) {
  if (!incoming.distance.isFinite ||
      !outgoing.distance.isFinite ||
      incoming.distance <= 1e-6 ||
      outgoing.distance <= 1e-6) {
    return null;
  }
  final a = incoming / incoming.distance, b = outgoing / outgoing.distance;
  final angle =
      math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy) *
      180 /
      math.pi;
  if (angle.abs() >= 150) return RouteTurn.review;
  if (angle.abs() < 30) return RouteTurn.straight;
  // Image Y increases downwards: a positive signed angle is a right turn.
  return angle > 0 ? RouteTurn.right : RouteTurn.left;
}

class RouteInstruction {
  const RouteInstruction({
    required this.maneuver,
    required this.text,
    required this.levelId,
    required this.levelName,
    required this.position,
    required this.distanceFromStartMetres,
    required this.distanceToNextMetres,
    required this.remainingMetres,
    this.destinationLevelId,
  });

  final RouteManeuver maneuver;
  final String text;
  final String levelId;
  final String levelName;
  final String? destinationLevelId;
  final RouteSegmentProgress position;
  final double distanceFromStartMetres;

  /// Published edge metres from this maneuver to the next, including ramp weight.
  final double distanceToNextMetres;
  final double remainingMetres;
}

class RouteInstructionProgress {
  const RouteInstructionProgress(
    this.instructionIndex,
    this.travelledMetres,
    this.metresToNextInstruction,
  );
  final int instructionIndex;
  final double travelledMetres;
  final double metresToNextInstruction;
}

class RouteInstructionPlan {
  RouteInstructionPlan._(
    List<RouteInstruction> instructions,
    List<double> metres,
    List<double?> pixels,
    this.crossesLevels,
    this.error,
  ) : instructions = List.unmodifiable(instructions),
      segmentMetres = List.unmodifiable(metres),
      segmentPixels = List.unmodifiable(pixels);

  factory RouteInstructionPlan._invalid(String error) =>
      RouteInstructionPlan._([], [], [], false, error);

  final List<RouteInstruction> instructions;
  final List<double> segmentMetres;

  /// Null for cross-floor segments: separate images have no shared pixel frame.
  final List<double?> segmentPixels;
  final bool crossesLevels;
  final String? error;

  bool get canSynchronizePreview =>
      error == null &&
      !crossesLevels &&
      segmentPixels.any((length) => (length ?? 0) > 1e-6);

  /// Uses the preview's segment/fraction, never total metres * pixel progress.
  /// Cross-floor synchronization remains disabled until Stage 2B defines it.
  RouteInstructionProgress? progressAt(RouteSegmentProgress position) {
    if (!canSynchronizePreview ||
        position.segmentIndex < 0 ||
        position.segmentIndex >= segmentMetres.length ||
        !position.fraction.isFinite ||
        position.fraction < 0 ||
        position.fraction > 1) {
      return null;
    }
    var routeOffset = position.segmentIndex + position.fraction;
    if (position.fraction == 0 || position.fraction == 1) {
      var next = routeOffset.toInt();
      while (next < segmentPixels.length && segmentPixels[next] == 0) {
        next++;
      }
      routeOffset = next.toDouble();
    }
    var index = 0;
    for (var i = 1; i < instructions.length; i++) {
      final boundary = instructions[i].position;
      if (boundary.segmentIndex + boundary.fraction > routeOffset) break;
      index = i;
    }
    final travelled =
        segmentMetres.take(position.segmentIndex).fold(0.0, (a, b) => a + b) +
        segmentMetres[position.segmentIndex] * position.fraction;
    final next =
        instructions[index].distanceFromStartMetres +
        instructions[index].distanceToNextMetres;
    return RouteInstructionProgress(
      index,
      travelled,
      math.max(0, next - travelled),
    );
  }
}

/// Annotates the existing Dijkstra path; never searches for or alters a route.
RouteInstructionPlan generateRouteInstructions(RouteGeometry geometry) {
  final issue = geometry.error;
  if (issue != null) return RouteInstructionPlan._invalid(issue);
  final nodes = geometry.orderedNodes;
  final levels = {for (final level in geometry.graph.levels) level.id: level};
  for (final node in nodes) {
    final plan = levels[node.levelId]!.floorPlan;
    if (node.x < 0 ||
        node.y < 0 ||
        (plan != null && (node.x > plan.width || node.y > plan.height))) {
      return RouteInstructionPlan._invalid(
        'Coordinates are outside the floor plan.',
      );
    }
  }

  final byPair = <(String, String), List<GraphEdge>>{};
  for (final edge in geometry.graph.edges.where((e) => e.isActive)) {
    byPair.putIfAbsent((edge.fromId, edge.toId), () => []).add(edge);
  }
  final metres = <double>[], pixels = <double?>[];
  final cumulative = <double>[0];
  var crossesLevels = false;
  for (var i = 0; i < nodes.length - 1; i++) {
    final a = nodes[i], b = nodes[i + 1];
    final matches = byPair[(a.id, b.id)]!;
    final distance = matches.singleOrNull?.distanceMetres;
    if (matches.length != 1 ||
        distance == null ||
        !distance.isFinite ||
        distance < 0) {
      return RouteInstructionPlan._invalid(
        'A directed route distance is missing, invalid or ambiguous.',
      );
    }
    final transition = a.levelId != b.levelId;
    if (transition && (a.nodeType != 'ramp' || b.nodeType != 'ramp')) {
      return RouteInstructionPlan._invalid(
        'A level transition has unverified ramp endpoints.',
      );
    }
    crossesLevels |= transition;
    final length = transition
        ? null
        : (Offset(b.x, b.y) - Offset(a.x, a.y)).distance;
    if (length != null &&
        (!length.isFinite || (length <= 1e-6 && distance > 0))) {
      return RouteInstructionPlan._invalid(
        'A measured segment has ambiguous image geometry.',
      );
    }
    metres.add(distance);
    pixels.add(length);
    cumulative.add(cumulative.last + distance);
  }
  if (!cumulative.last.isFinite) {
    return RouteInstructionPlan._invalid('Route distance overflowed.');
  }

  // Original route indices survive duplicate coordinates and repeated node IDs.
  final maneuvers = <(int, RouteManeuver)>[
    if (pixels.any((length) => length == null || length > 1e-6))
      (0, RouteManeuver.departure),
  ];
  for (var i = 0; i < metres.length; i++) {
    if (pixels[i] == null) {
      maneuvers.add((i, RouteManeuver.ramp));
      continue;
    }
    if (i == 0 || pixels[i]! <= 1e-6) continue;
    var previous = i - 1;
    while (previous >= 0 &&
        pixels[previous] != null &&
        pixels[previous]! <= 1e-6) {
      previous--;
    }
    if (previous < 0) continue;
    if (pixels[previous] == null) {
      maneuvers.add((i, RouteManeuver.straight));
      continue;
    }
    final a = nodes[previous], b = nodes[previous + 1];
    final c = nodes[i], d = nodes[i + 1];
    final turn = classifyRouteTurn(
      Offset(b.x - a.x, b.y - a.y),
      Offset(d.x - c.x, d.y - c.y),
    );
    if (turn == RouteTurn.review) {
      return RouteInstructionPlan._invalid(
        'A near-reversal needs administrator review; no U-turn is assumed.',
      );
    }
    if (turn == RouteTurn.left || turn == RouteTurn.right) {
      maneuvers.add((
        i,
        turn == RouteTurn.left ? RouteManeuver.left : RouteManeuver.right,
      ));
    }
  }
  maneuvers.add((nodes.length - 1, RouteManeuver.arrival));
  final instructions = <RouteInstruction>[];
  for (var j = 0; j < maneuvers.length; j++) {
    final (i, maneuver) = maneuvers[j];
    final level = levels[nodes[i].levelId]!;
    final destination = maneuver == RouteManeuver.ramp
        ? levels[nodes[i + 1].levelId]
        : null;
    final text = switch (maneuver) {
      RouteManeuver.departure =>
        nodes.first.nodeType == 'building_entrance'
            ? 'Follow the route from the entrance.'
            : 'Start following the assigned route.',
      RouteManeuver.straight => 'Continue along the route on ${level.name}.',
      RouteManeuver.left => 'Turn left.',
      RouteManeuver.right => 'Turn right.',
      RouteManeuver.ramp => 'Take the ramp to ${destination!.name}.',
      RouteManeuver.arrival =>
        nodes.last.nodeType == 'zone_entrance'
            ? 'Arrive at the assigned zone entrance.'
            : 'End of the planned route.',
    };
    final next = j + 1 < maneuvers.length ? maneuvers[j + 1].$1 : i;
    instructions.add(
      RouteInstruction(
        maneuver: maneuver,
        text: text,
        levelId: level.id,
        levelName: level.name,
        destinationLevelId: destination?.id,
        position: i == nodes.length - 1 && i > 0
            ? RouteSegmentProgress(i - 1, 1)
            : RouteSegmentProgress(i, 0),
        distanceFromStartMetres: cumulative[i],
        distanceToNextMetres: cumulative[next] - cumulative[i],
        remainingMetres: cumulative.last - cumulative[i],
      ),
    );
  }
  return RouteInstructionPlan._(
    instructions,
    metres,
    pixels,
    crossesLevels,
    null,
  );
}
