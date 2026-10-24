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

/// A simulation in published image pixels, never a real-world speed estimate.
/// Cross-floor playback needs an explicit transition policy (Stage 2B).
class RoutePreviewPath {
  RoutePreviewPath(List<RouteNode> nodes)
    : points = List.unmodifiable(nodes.map((n) => Offset(n.x, n.y))),
      crossesLevels = nodes.map((n) => n.levelId).toSet().length > 1 {
    lengths = [
      for (var i = 1; i < points.length; i++)
        (points[i] - points[i - 1]).distance,
    ];
    totalDistance = lengths.fold(0, (sum, length) => sum + length);
  }

  static const pixelsPerSecond = 120.0;
  final List<Offset> points;
  final bool crossesLevels;
  late final List<double> lengths;
  late final double totalDistance;

  bool get canPlay =>
      !crossesLevels &&
      points.length > 1 &&
      totalDistance.isFinite &&
      totalDistance > 0;

  Duration get duration => Duration(
    microseconds:
        (totalDistance / pixelsPerSecond * Duration.microsecondsPerSecond)
            .round()
            .clamp(1, 1 << 53),
  );

  /// Original segment occurrence and local fraction for normalized pixel progress.
  /// Interior boundaries select the outgoing nonzero segment; completion selects
  /// the final endpoint. Cross-level paths deliberately remain unsupported.
  RouteSegmentProgress? segmentAt(double progress) {
    if (!canPlay || !progress.isFinite) return null;
    var remaining = progress.clamp(0.0, 1.0) * totalDistance;
    for (var i = 0; i < lengths.length; i++) {
      final length = lengths[i];
      if (length == 0) continue;
      // Exact boundaries belong to the next nonzero segment.
      if (remaining < length) {
        return RouteSegmentProgress(i, remaining / length);
      }
      remaining -= length;
    }
    return RouteSegmentProgress(lengths.length - 1, 1);
  }

  Offset? position(double progress) {
    final segment = segmentAt(progress);
    if (segment == null) return null;
    return Offset.lerp(
      points[segment.segmentIndex],
      points[segment.segmentIndex + 1],
      segment.fraction,
    );
  }

  /// East = 0, south = pi/2. Skip zero-length segments, including at arrival.
  double? heading(double progress, {bool smooth = false}) {
    final segment = segmentAt(progress);
    if (segment == null) return null;
    var index = segment.segmentIndex;
    while (index >= 0 && lengths[index] <= 1e-6) {
      index--;
    }
    if (index < 0) return null;
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
    if (previous >= 0 && along < window(previous)) {
      final t = .5 + along / (2 * window(previous));
      return interpolateHeading(angle(previous), current, ease(t));
    }
    if (next < lengths.length && lengths[index] - along < window(next)) {
      final t = .5 - (lengths[index] - along) / (2 * window(next));
      return interpolateHeading(current, angle(next), ease(t));
    }
    return current;
  }
}
