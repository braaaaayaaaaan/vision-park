import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/driver_models.dart';

/// Position on an occurrence of a directed segment, not a node ID (loops work).
class RouteSegmentProgress {
  const RouteSegmentProgress(this.segmentIndex, this.fraction);
  final int segmentIndex;
  final double fraction;
}

/// Clockwise angles in image coordinates (Y down), in [-pi, pi).
double shortestAngleDelta(double from, double to) =>
    (to - from + math.pi) % (2 * math.pi) - math.pi;

double interpolateHeading(double from, double to, double fraction) =>
    from + shortestAngleDelta(from, to) * fraction.clamp(0.0, 1.0);

/// A simulation, never a real-world speed estimate. Single-floor timing stays in
/// image pixels; multi-floor timing uses published metres across separate images.
class RoutePreviewPath {
  RoutePreviewPath(List<RouteNode> nodes, {List<double>? segmentMetres})
    : points = List.unmodifiable(nodes.map((n) => Offset(n.x, n.y))),
      levels = List.unmodifiable(nodes.map((n) => n.levelId)),
      crossesLevels = nodes.map((n) => n.levelId).toSet().length > 1 {
    final validTransitions = [
      for (var i = 1; i < nodes.length; i++)
        if (nodes[i - 1].levelId != nodes[i].levelId)
          nodes[i - 1].nodeType == 'ramp' && nodes[i].nodeType == 'ramp',
    ].every((valid) => valid);
    final measured =
        segmentMetres != null &&
        segmentMetres.length == points.length - 1 &&
        segmentMetres.every((m) => m.isFinite && m >= 0);
    _valid = !crossesLevels || (validTransitions && measured);
    lengths = [
      for (var i = 1; i < points.length; i++)
        crossesLevels
            ? (measured
                  // Even a published zero-metre ramp needs a visible transition
                  // interval. Instruction distances remain the published values.
                  ? (levels[i - 1] != levels[i] && segmentMetres[i - 1] == 0
                        ? previewMetresPerSecond * .5
                        : segmentMetres[i - 1])
                  : 0)
            : (points[i] - points[i - 1]).distance,
    ];
    totalDistance = lengths.fold(0, (sum, length) => sum + length);
  }

  static const pixelsPerSecond = 120.0;
  static const previewMetresPerSecond = 3.0;
  final List<Offset> points;
  final List<String> levels;
  final bool crossesLevels;
  late final bool _valid;
  late final List<double> lengths;
  late final double totalDistance;

  bool get canPlay =>
      _valid &&
      points.length > 1 &&
      totalDistance.isFinite &&
      totalDistance > 0;

  Duration get duration => Duration(
    microseconds:
        (totalDistance /
                (crossesLevels ? previewMetresPerSecond : pixelsPerSecond) *
                Duration.microsecondsPerSecond)
            .round()
            .clamp(1, 1 << 53),
  );

  /// Original segment occurrence and local fraction for normalized pixel progress.
  /// Interior boundaries select the outgoing nonzero segment; completion selects
  /// the final endpoint. Ramp fractions represent time, never image coordinates.
  RouteSegmentProgress? segmentAt(double progress) {
    if (!canPlay || !progress.isFinite) return null;
    var remaining = progress.clamp(0.0, 1.0) * totalDistance;
    for (var i = 0; i < lengths.length; i++) {
      final length = lengths[i];
      if (length == 0) continue;
      // Exact boundaries belong to the next nonzero segment.
      if (remaining < length &&
          !(crossesLevels &&
              (remaining - length).abs() < totalDistance * 1e-12)) {
        return RouteSegmentProgress(i, remaining / length);
      }
      remaining = math.max(0, remaining - length);
    }
    return RouteSegmentProgress(lengths.length - 1, 1);
  }

  Offset? position(double progress) {
    final segment = segmentAt(progress);
    if (segment == null) return null;
    if (levels[segment.segmentIndex] != levels[segment.segmentIndex + 1]) {
      return points[segment.segmentIndex + (segment.fraction == 1 ? 1 : 0)];
    }
    return Offset.lerp(
      points[segment.segmentIndex],
      points[segment.segmentIndex + 1],
      segment.fraction,
    );
  }

  String? levelAt(double progress) {
    final segment = segmentAt(progress);
    if (segment == null) return levels.firstOrNull;
    return levels[segment.segmentIndex + (segment.fraction == 1 ? 1 : 0)];
  }

  /// First completed ramp after [from], even when a frame skips several floors.
  /// Occurrence-based boundaries also handle routes that return to an old floor.
  (double, String)? nextFloorChange(double from, double to) {
    if (!canPlay || !crossesLevels) return null;
    var distance = 0.0;
    for (var i = 0; i < lengths.length; i++) {
      distance += lengths[i];
      final boundary = distance / totalDistance;
      if (levels[i] != levels[i + 1] && boundary > from && boundary <= to) {
        return (boundary, levels[i + 1]);
      }
    }
    return null;
  }

  /// East = 0, south = pi/2. Skip zero-length segments, including at arrival.
  double? heading(double progress, {bool smooth = false}) {
    final segment = segmentAt(progress);
    if (segment == null) return null;
    var index = segment.segmentIndex;
    if (levels[index] != levels[index + 1]) return null;
    while (index >= 0 &&
        lengths[index] <= 1e-6 &&
        levels[index] == levels[segment.segmentIndex]) {
      index--;
    }
    if (index < 0 || levels[index] != levels[index + 1]) return null;
    double angle(int i) {
      final delta = points[i + 1] - points[i];
      return math.atan2(delta.dy, delta.dx);
    }

    final current = angle(index);
    if (!smooth) return current;
    final along = index == segment.segmentIndex
        ? lengths[index] * segment.fraction
        : lengths[index];
    var previous = index - 1, next = index + 1;
    while (previous >= 0 && lengths[previous] <= 1e-6) {
      previous--;
    }
    while (next < lengths.length && lengths[next] <= 1e-6) {
      next++;
    }
    double window(int other) =>
        math.min(36, math.min(lengths[index], lengths[other]) / 4);
    double ease(double t) => t * t * (3 - 2 * t);
    // Distance windows never overlap on short segments. Both sides of a corner
    // share one interpolation, so heading stays continuous at the boundary.
    if (previous >= 0 &&
        levels[previous] == levels[index] &&
        levels[previous + 1] == levels[index] &&
        along < window(previous)) {
      final t = .5 + along / (2 * window(previous));
      return interpolateHeading(angle(previous), current, ease(t));
    }
    if (next < lengths.length &&
        levels[next] == levels[index] &&
        levels[next + 1] == levels[index] &&
        lengths[index] - along < window(next)) {
      final t = .5 - (lengths[index] - along) / (2 * window(next));
      return interpolateHeading(current, angle(next), ease(t));
    }
    return current;
  }
}
