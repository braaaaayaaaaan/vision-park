import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'floor_plan_viewport.dart';
import 'route_preview.dart';

const headingCameraEdgePadding = 28.0;

/// One shared image-coordinate transform. Screen UI never enters this matrix.
/// Exact corner cases cannot simultaneously keep a rotated image covering the
/// viewport and its corner marker visible: limit rotation there, not the route.
Matrix4 headingUpCamera({
  required Size viewport,
  required Size image,
  required Offset focus,
  required Offset vehicle,
  required Offset anchor,
  required double scale,
  required double rotation,
  required double referenceRotation,
  double transition = 1,
  double maxRotationStep = math.pi,
}) {
  rotation =
      referenceRotation +
      shortestAngleDelta(
        referenceRotation,
        rotation,
      ).clamp(-maxRotationStep, maxRotationStep);
  final padding = headingCameraEdgePadding * transition;
  final inset = math.min(24.0, viewport.shortestSide * .3) * transition;
  final visible = (Offset.zero & viewport).deflate(inset);
  Matrix4 camera(double angle) => constrainFloorPlan(
    floorPlanTransform(
      scale: math.max(scale, coveringFloorPlanScale(viewport, image, angle)),
      rotation: angle,
      focus: focus,
      anchor: anchor,
    ),
    viewport,
    image,
    coverViewport: true,
    edgePadding: padding,
  );
  bool fits(Matrix4 matrix) {
    final point = MatrixUtils.transformPoint(matrix, vehicle);
    return point.dx >= visible.left - 1e-6 &&
        point.dx <= visible.right + 1e-6 &&
        point.dy >= visible.top - 1e-6 &&
        point.dy <= visible.bottom + 1e-6;
  }

  final requested = camera(rotation);
  if (fits(requested)) return requested;
  // Start from the current safe orientation; if the vehicle has moved too close
  // to a corner, the nearest quarter-turn is a guaranteed bounded fallback.
  var base = referenceRotation;
  if (!fits(camera(base))) {
    base = (referenceRotation / (math.pi / 2)).round() * (math.pi / 2);
  }
  var low = 0.0, high = 1.0;
  var safe = camera(base);
  for (var i = 0; i < 18; i++) {
    final fraction = (low + high) / 2;
    final candidate = camera(interpolateHeading(base, rotation, fraction));
    if (fits(candidate)) {
      low = fraction;
      safe = candidate;
    } else {
      high = fraction;
    }
  }
  return safe;
}
