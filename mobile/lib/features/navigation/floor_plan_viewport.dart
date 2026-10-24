import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/driver_models.dart';

/// Both the image and overlay remain in original pixels. Only their common
/// parent is transformed; there is no independent node-bounds projection.
Matrix4 fitFloorPlan(
  Size viewport,
  Size image,
  List<RouteNode> route, {
  bool fullPlan = false,
  double padding = 36,
}) {
  Rect bounds = Offset.zero & image;
  if (!fullPlan && route.isNotEmpty) {
    final xs = route.map((node) => node.x);
    final ys = route.map((node) => node.y);
    final left = xs.reduce(math.min), right = xs.reduce(math.max);
    final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
    bounds = Rect.fromCenter(
      center: Offset((left + right) / 2, (top + bottom) / 2),
      width: math.max(32, right - left),
      height: math.max(32, bottom - top),
    );
  }
  final inset = fullPlan ? 0.0 : padding;
  // Route padding must never zoom out further than the full image view.
  final scale = math.max(
    math.min(viewport.width / image.width, viewport.height / image.height),
    math.min(
      math.max(1, viewport.width - inset * 2) / bounds.width,
      math.max(1, viewport.height - inset * 2) / bounds.height,
    ),
  );
  // InteractiveViewer reads getMaxScaleOnAxis (including Z). Keeping Z at 1
  // incorrectly reports every zoomed-out image as scale 1.
  return Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(
    viewport.width / 2 - bounds.center.dx * scale,
    viewport.height / 2 - bounds.center.dy * scale,
    0,
  );
}

double floorPlanRotation(Matrix4 transform) =>
    math.atan2(transform.entry(1, 0), transform.entry(0, 0));

Matrix4 floorPlanTransform({
  required double scale,
  required double rotation,
  required Offset focus,
  required Offset anchor,
}) {
  final c = math.cos(rotation), s = math.sin(rotation);
  return Matrix4.diagonal3Values(scale, scale, scale)
    ..setEntry(0, 0, scale * c)
    ..setEntry(0, 1, -scale * s)
    ..setEntry(1, 0, scale * s)
    ..setEntry(1, 1, scale * c)
    ..setTranslationRaw(
      anchor.dx - scale * (c * focus.dx - s * focus.dy),
      anchor.dy - scale * (s * focus.dx + c * focus.dy),
      0,
    );
}

double coveringFloorPlanScale(Size viewport, Size image, double rotation) {
  final c = math.cos(rotation).abs(), s = math.sin(rotation).abs();
  return math.max(
    (c * viewport.width + s * viewport.height) / image.width,
    (s * viewport.width + c * viewport.height) / image.height,
  );
}

/// Clamp in the image's axes, not its rotated screen bounding box. Heading-up
/// permits a small screen-pixel edge margin for a fully visible vehicle marker.
Matrix4 constrainFloorPlan(
  Matrix4 transform,
  Size viewport,
  Size image, {
  bool coverViewport = false,
  double edgePadding = 0,
}) {
  final rotation = floorPlanRotation(transform);
  final c = math.cos(rotation), s = math.sin(rotation);
  var scale = transform.getMaxScaleOnAxis();
  var result = transform;
  final minimum = coveringFloorPlanScale(viewport, image, rotation);
  if (coverViewport && scale < minimum - 1e-9) {
    final center = viewport.center(Offset.zero);
    final focus = MatrixUtils.transformPoint(
      Matrix4.inverted(transform),
      center,
    );
    scale = minimum;
    result = floorPlanTransform(
      scale: scale,
      rotation: rotation,
      focus: focus,
      anchor: center,
    );
  }
  // Inverse-rotate viewport corners (still in screen pixels). Translation in
  // these axes has two independent interval constraints even when rotated.
  final corners = [
    Offset.zero,
    Offset(viewport.width, 0),
    Offset(0, viewport.height),
    Offset(viewport.width, viewport.height),
  ].map((p) => Offset(c * p.dx + s * p.dy, -s * p.dx + c * p.dy)).toList();
  double clampAxis(double current, double low, double high, double extent) {
    final minimum = high - extent - edgePadding;
    final maximum = low + edgePadding;
    return minimum > maximum
        ? (low + high - extent) / 2
        : current.clamp(minimum, maximum);
  }

  final tx = result.storage[12], ty = result.storage[13];
  final x = clampAxis(
    c * tx + s * ty,
    corners.map((p) => p.dx).reduce(math.min),
    corners.map((p) => p.dx).reduce(math.max),
    image.width * scale,
  );
  final y = clampAxis(
    -s * tx + c * ty,
    corners.map((p) => p.dy).reduce(math.min),
    corners.map((p) => p.dy).reduce(math.max),
    image.height * scale,
  );
  final bounded = Offset(c * x - s * y, s * x + c * y);
  // Keep the transformation listener idempotent despite rotation roundoff.
  if ((bounded - Offset(tx, ty)).distance <= 1e-7) return result;
  return result.clone()..setTranslationRaw(bounded.dx, bounded.dy, 0);
}
