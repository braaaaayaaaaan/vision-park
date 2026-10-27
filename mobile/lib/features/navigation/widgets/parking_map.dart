import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/navigation_models.dart';
import '../floor_plan_viewport.dart';
import '../navigation_camera.dart';
import '../route_geometry.dart';
import '../route_preview.dart';
import '../route_instructions.dart';
import '../route_voice_guidance.dart';
import 'route_preview_guidance.dart';

class ParkingMap extends StatefulWidget {
  const ParkingMap({
    required this.graph,
    required this.routeNodeIds,
    required this.levelId,
    this.loadFloorPlan,
    this.onTouchInteractionChanged,
    this.previewEnabled = true,
    this.navigationLayout = false,
    this.maxMapHeight,
    this.floorSelector,
    this.destinationSummary,
    this.parkingAction,
    this.parkingFeedback,
    this.voiceGuidance,
    super.key,
  });
  final ParkingGraph graph;
  final List<String> routeNodeIds;
  final String levelId;
  final Future<Uint8List> Function(MapFloorPlan)? loadFloorPlan;
  final ValueChanged<bool>? onTouchInteractionChanged;
  final bool previewEnabled;
  final bool navigationLayout;
  final double? maxMapHeight;
  final Widget? floorSelector;
  final Widget? destinationSummary;
  final Widget? parkingAction;
  final Widget? parkingFeedback;
  final RouteVoiceGuidance? voiceGuidance;
  @override
  State<ParkingMap> createState() => _ParkingMapState();
}

class _ParkingMapState extends State<ParkingMap>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _transformation = TransformationController();
  late final AnimationController _preview;
  late final AnimationController _camera;
  bool _followingVehicle = false;
  bool _headingViewport = false;
  Matrix4 _cameraStart = Matrix4.identity();
  double _followScale = 1;
  Duration? _lastFollowFrame;
  double _rotationBudget = 0;
  RoutePreviewPath? _previewPath;
  late RouteInstructionPlan _instructionPlan;
  Uint8List? _bytes;
  bool _loading = false;
  int _request = 0;
  Size? _viewport;
  bool _fullPlan = false;
  final _pointers = <int>{};
  MapFloorPlan? get _plan => widget.graph.levels
      .where((level) => level.id == widget.levelId)
      .firstOrNull
      ?.floorPlan;
  RouteGeometry get _geometry =>
      RouteGeometry(widget.graph, widget.routeNodeIds);
  @override
  void initState() {
    super.initState();
    _preview = AnimationController(vsync: this);
    _camera = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _preview.addListener(_followVehicle);
    _preview.addListener(_syncVoice);
    _preview.addStatusListener((status) {
      _syncVoice();
      if (status == AnimationStatus.completed) _camera.stop();
    });
    _camera.addListener(_followVehicle);
    WidgetsBinding.instance.addObserver(this);
    _transformation.addListener(_constrainViewport);
    _instructionPlan = generateRouteInstructions(_geometry);
    widget.voiceGuidance?.setPlan(_instructionPlan);
    _load();
  }

  void _beginFollowingVehicle() {
    final viewport = _viewport!, plan = _plan!;
    final fullScale = math.min(
      viewport.width / plan.width,
      viewport.height / plan.height,
    );
    _cameraStart = _transformation.value.clone();
    _followScale = math.max(fullScale * 3, _cameraStart.getMaxScaleOnAxis());
    _followingVehicle = true;
    _headingViewport = true;
    _lastFollowFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    _rotationBudget = 0;
    _camera.forward(from: 0);
  }

  void _followVehicle() {
    final viewport = _viewport, plan = _plan;
    final position = _previewPath?.position(_preview.value);
    final heading = _previewPath?.heading(_preview.value, smooth: true);
    if (!_followingVehicle ||
        viewport == null ||
        plan == null ||
        position == null ||
        heading == null) {
      return;
    }
    final t = Curves.easeInOut.transform(_camera.value);
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (frame != _lastFollowFrame) {
      final seconds = math.max(
        0.0,
        (frame - (_lastFollowFrame ?? frame)).inMicroseconds /
            1e6 /
            timeDilation,
      );
      _rotationBudget = math.min(math.pi, 2 * math.pi * seconds);
      _lastFollowFrame = frame;
    }
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final startCenter = MatrixUtils.transformPoint(
      Matrix4.inverted(_cameraStart),
      center,
    );
    final focus = Offset.lerp(startCenter, position, t)!;
    final scale = ui.lerpDouble(
      _cameraStart.getMaxScaleOnAxis(),
      _followScale,
      t,
    )!;
    final previousRotation = floorPlanRotation(_transformation.value);
    final next = headingUpCamera(
      viewport: viewport,
      image: Size(plan.width.toDouble(), plan.height.toDouble()),
      focus: focus,
      vehicle: position,
      anchor: Offset(viewport.width / 2, viewport.height * (.5 + .12 * t)),
      scale: scale,
      rotation: interpolateHeading(
        floorPlanRotation(_cameraStart),
        -math.pi / 2 - heading,
        t,
      ),
      referenceRotation: previousRotation,
      transition: t,
      // Both existing controllers share a frame clock; no additional ticker.
      maxRotationStep: _rotationBudget,
    );
    // Preview and camera tickers can fire in either order in the same frame.
    // Share that frame's allowance rather than consuming it before rotation.
    _rotationBudget = math.max(
      0,
      _rotationBudget -
          shortestAngleDelta(previousRotation, floorPlanRotation(next)).abs(),
    );
    _transformation.value = next;
  }

  void _stopFollowingVehicle() {
    _followingVehicle = false;
    _camera.stop();
  }

  void _pausePlayback() {
    widget.voiceGuidance?.pause();
    _preview.stop();
    _camera.stop();
  }

  void _syncVoice() {
    final segment = _previewPath?.segmentAt(_preview.value);
    widget.voiceGuidance?.update(
      progress: segment == null ? null : _instructionPlan.progressAt(segment),
      playing: _preview.isAnimating && widget.previewEnabled,
      complete: _preview.isCompleted,
    );
  }

  void _constrainViewport() {
    final plan = _plan, viewport = _viewport;
    if (plan == null || viewport == null) return;
    final bounded = constrainFloorPlan(
      _transformation.value,
      viewport,
      Size(plan.width.toDouble(), plan.height.toDouble()),
      coverViewport: _headingViewport,
      edgePadding: _headingViewport
          ? headingCameraEdgePadding * Curves.easeInOut.transform(_camera.value)
          : 0,
    );
    if (bounded != _transformation.value) _transformation.value = bounded;
  }

  @override
  void didUpdateWidget(covariant ParkingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceGuidance != widget.voiceGuidance) {
      oldWidget.voiceGuidance?.releasePlan(_instructionPlan);
      widget.voiceGuidance?.setPlan(_instructionPlan);
    }
    if (!widget.previewEnabled) _pausePlayback();
    if (!_sameInstructionData(oldWidget, widget)) {
      _instructionPlan = generateRouteInstructions(_geometry);
      widget.voiceGuidance?.setPlan(_instructionPlan);
      _stopFollowingVehicle();
      _preview.reset();
    }
    if (!_sameMap(oldWidget, widget) ||
        oldWidget.levelId != widget.levelId ||
        !listEquals(oldWidget.routeNodeIds, widget.routeNodeIds)) {
      _load();
    }
  }

  // Compare values, not API object identities. Distances and level metadata may
  // change while image geometry stays the same; only directions need rebuilding.
  bool _sameInstructionData(ParkingMap a, ParkingMap b) =>
      listEquals(a.routeNodeIds, b.routeNodeIds) &&
      listEquals(
        a.graph.nodes
            .map((n) => (n.id, n.levelId, n.x, n.y, n.nodeType))
            .toList(),
        b.graph.nodes
            .map((n) => (n.id, n.levelId, n.x, n.y, n.nodeType))
            .toList(),
      ) &&
      listEquals(
        a.graph.edges
            .map((e) => (e.fromId, e.toId, e.isActive, e.distanceMetres))
            .toList(),
        b.graph.edges
            .map((e) => (e.fromId, e.toId, e.isActive, e.distanceMetres))
            .toList(),
      ) &&
      listEquals(
        a.graph.levels
            .map(
              (l) => (
                l.id,
                l.name,
                l.levelNumber,
                l.floorPlan?.width,
                l.floorPlan?.height,
                l.floorPlan?.revision,
                l.floorPlan?.publicationRevision,
              ),
            )
            .toList(),
        b.graph.levels
            .map(
              (l) => (
                l.id,
                l.name,
                l.levelNumber,
                l.floorPlan?.width,
                l.floorPlan?.height,
                l.floorPlan?.revision,
                l.floorPlan?.publicationRevision,
              ),
            )
            .toList(),
      );

  // API refreshes may recreate model objects without changing map content.
  // Keep the decoded image and manual viewport for those equivalent rebuilds.
  bool _sameMap(ParkingMap a, ParkingMap b) {
    Object? descriptor(ParkingMap map) {
      final plan = map.graph.levels
          .where((level) => level.id == map.levelId)
          .firstOrNull
          ?.floorPlan;
      return plan == null
          ? null
          : (
              plan.width,
              plan.height,
              plan.revision,
              plan.publicationRevision,
              plan.imagePath,
            );
    }

    return descriptor(a) == descriptor(b) &&
        listEquals(
          a.graph.nodes
              .map((n) => (n.id, n.levelId, n.x, n.y, n.nodeType))
              .toList(),
          b.graph.nodes
              .map((n) => (n.id, n.levelId, n.x, n.y, n.nodeType))
              .toList(),
        ) &&
        listEquals(
          a.graph.edges.map((e) => (e.fromId, e.toId, e.isActive)).toList(),
          b.graph.edges.map((e) => (e.fromId, e.toId, e.isActive)).toList(),
        );
  }

  void _pointerDown(PointerDownEvent event) {
    if (_followingVehicle) setState(_stopFollowingVehicle);
    if (_pointers.isEmpty) widget.onTouchInteractionChanged?.call(true);
    _pointers.add(event.pointer);
  }

  void _pointerEnded(PointerEvent event) {
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      widget.onTouchInteractionChanged?.call(false);
    }
  }

  Future<void> _load() async {
    widget.voiceGuidance?.restart();
    _stopFollowingVehicle();
    _preview.reset();
    _previewPath = RoutePreviewPath(_geometry.orderedNodes);
    if (_previewPath!.canPlay) _preview.duration = _previewPath!.duration;
    final request = ++_request;
    _bytes = null;
    _viewport = null;
    _fullPlan = false;
    final plan = _plan;
    final load = widget.loadFloorPlan;
    _loading = plan != null && load != null && _geometry.error == null;
    if (!_loading) {
      if (kDebugMode) {
        debugPrint(
          'Navigation floor plan: image_request_skipped level=${widget.levelId} reason=${plan == null
              ? "missing_parsed_descriptor"
              : load == null
              ? "missing_loader"
              : "invalid_route_geometry"}',
        );
      }
      return;
    }
    var phase = 'image_request';
    try {
      if (kDebugMode) {
        debugPrint(
          'Navigation floor plan: image_request_started level=${widget.levelId}',
        );
      }
      final bytes = await load!(plan!);
      phase = 'image_decode';
      // Verify decoded dimensions before drawing any overlay.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final aligned =
            frame.image.width == plan.width &&
            frame.image.height == plan.height;
        frame.image.dispose();
        if (!aligned) {
          phase = 'image_dimensions';
          throw const FormatException('Image dimensions changed');
        }
      } finally {
        codec.dispose();
      }
      if (mounted && request == _request) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'Navigation floor plan: ${phase}_failed level=${widget.levelId}',
        );
      }
      if (mounted && request == _request) {
        setState(() {
          _bytes = null;
          _loading = false;
        });
      }
    }
  }

  void _fit(Size viewport, {required bool fullPlan}) {
    _stopFollowingVehicle();
    _headingViewport = false;
    final plan = _plan!;
    _transformation.value = fitFloorPlan(
      viewport,
      Size(plan.width.toDouble(), plan.height.toDouble()),
      _geometry.orderedNodes
          .where((node) => node.levelId == widget.levelId)
          .toList(),
      fullPlan: fullPlan,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (_preview.isAnimating || _camera.isAnimating)) {
      setState(_pausePlayback);
    }
  }

  @override
  void dispose() {
    widget.voiceGuidance?.releasePlan(_instructionPlan);
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    _preview.dispose();
    ++_request;
    if (_pointers.isNotEmpty) {
      final notify = widget.onTouchInteractionChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => notify?.call(false));
    }
    _transformation.removeListener(_constrainViewport);
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry, plan = _plan;
    final local = geometry.orderedNodes.where(
      (node) => node.levelId == widget.levelId,
    );
    final invalid =
        geometry.error != null ||
        (plan != null &&
            local.any(
              (node) =>
                  node.x < 0 ||
                  node.y < 0 ||
                  node.x > plan.width ||
                  node.y > plan.height,
            ));
    if (_loading) {
      return _statusLayout(
        const SizedBox(
          height: 320,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading floor plan…'),
              ],
            ),
          ),
        ),
      );
    }
    if (invalid || plan == null || _bytes == null) {
      return _statusLayout(
        Container(
          padding: const EdgeInsets.all(AppSpacing.large),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
          ),
          child: const Column(
            children: [
              Icon(Icons.map_outlined, size: 36),
              SizedBox(height: 8),
              Text(
                'Map Unavailable',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'A verified published floor plan could not be loaded. Refresh navigation or contact your parking administrator.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.navigationLayout)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _fullPlan = false);
                  _fit(_viewport!, fullPlan: false);
                },
                icon: const Icon(Icons.route_rounded),
                label: const Text('Fit Route'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _fullPlan = true);
                  _fit(_viewport!, fullPlan: true);
                },
                icon: const Icon(Icons.fit_screen_rounded),
                label: const Text('Full Floor Plan'),
              ),
            ],
          ),
        if (!widget.navigationLayout) const SizedBox(height: 8),
        if (widget.navigationLayout) ...[
          _guidanceBanner(key: const ValueKey('route-guidance-card')),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final viewport = _mapViewport(constraints.maxWidth);
            if (_viewport != viewport) {
              _viewport = viewport;
              _fit(viewport, fullPlan: _fullPlan);
            }
            final imageSize = Size(
              plan.width.toDouble(),
              plan.height.toDouble(),
            );
            final floorScale = fitFloorPlan(
              viewport,
              imageSize,
              [],
              fullPlan: true,
            ).getMaxScaleOnAxis();
            final routeScale = fitFloorPlan(
              viewport,
              imageSize,
              local.toList(),
            ).getMaxScaleOnAxis();
            final canvas = Align(
              child: Semantics(
                label: 'Indoor route map. Pinch to zoom and drag to pan. Fixed route, no live tracking.',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
                  child: SizedBox(
                    width: viewport.width,
                    height: viewport.height,
                    child: Stack(
                      key: const ValueKey('floor-plan-viewport'),
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: AppTheme.background,
                          child: Listener(
                            onPointerDown: _pointerDown,
                            onPointerUp: _pointerEnded,
                            onPointerCancel: _pointerEnded,
                            child: InteractiveViewer(
                              transformationController: _transformation,
                              constrained: false,
                              alignment: Alignment.topLeft,
                              minScale: floorScale,
                              maxScale: math.max(
                                math.max(
                                  1,
                                  math.sqrt(
                                        viewport.width * viewport.width +
                                            viewport.height * viewport.height,
                                      ) /
                                      imageSize.shortestSide *
                                      4,
                                ),
                                math.max(floorScale * 12, routeScale * 4),
                              ),
                              // InteractiveViewer's native bounds assume an
                              // unrotated image. Our shared controller listener
                              // enforces image-axis bounds for every gesture.
                              boundaryMargin: const EdgeInsets.all(
                                double.infinity,
                              ),
                              child: SizedBox(
                                width: plan.width.toDouble(),
                                height: plan.height.toDouble(),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(
                                      _bytes!,
                                      fit: BoxFit.fill,
                                      excludeFromSemantics: true,
                                    ),
                                    AnimatedBuilder(
                                      animation: Listenable.merge([
                                        _transformation,
                                        _preview,
                                      ]),
                                      builder: (context, _) => CustomPaint(
                                        painter: ParkingMapPainter(
                                          geometry: geometry,
                                          levelId: widget.levelId,
                                          routeColour: scheme.primary,
                                          previewPosition: _previewPath
                                              ?.position(_preview.value),
                                          previewHeading: _previewPath?.heading(
                                            _preview.value,
                                            smooth: true,
                                          ),
                                          markerScale:
                                              1 /
                                              _transformation.value
                                                  .getMaxScaleOnAxis(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (!widget.navigationLayout)
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 10,
                            child: IgnorePointer(
                              child: _guidanceBanner(
                                key: const ValueKey('route-guidance-overlay'),
                              ),
                            ),
                          ),
                        if (widget.navigationLayout &&
                            viewport.height >= 240 &&
                            viewport.width >= 240) ...[
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: _floatingControls(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
            return canvas;
          },
        ),
        if (widget.navigationLayout) ...[
          const SizedBox(height: 8),
          // Keep floor selection below the image; compact maps also need their
          // camera tools here so the controls do not cover the route.
          LayoutBuilder(
            builder: (context, constraints) {
              final viewport = _mapViewport(constraints.maxWidth);
              final toolsBelow = viewport.height < 240 || viewport.width < 240;
              return Row(
                children: [
                  if (widget.floorSelector != null)
                    Expanded(child: widget.floorSelector!),
                  if (toolsBelow) ...[
                    if (widget.floorSelector != null) const SizedBox(width: 8),
                    _floatingControls(horizontal: true),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        _previewControls(),
        const SizedBox(height: 12),
        if (!widget.navigationLayout)
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (_previewPath?.canPlay == true)
                _legend(
                  Icons.directions_car_rounded,
                  'Preview vehicle',
                  const Color(0xFFB45309),
                ),
              _legend(Icons.trip_origin, 'Entrance', scheme.primary),
              _legend(
                Icons.local_parking_rounded,
                'Assigned Zone',
                scheme.primary,
              ),
              _legend(Icons.swap_vert_rounded, 'Ramp', const Color(0xFF7B4FA3)),
            ],
          ),
        if (!widget.navigationLayout) const SizedBox(height: 8),
        if (!widget.navigationLayout)
          const Text(
            'Arrows show the planned driving direction. Pinch to zoom and drag to pan.',
          ),
      ],
    );
  }

  Size _mapViewport(double availableWidth) {
    final plan = _plan!;
    final width = math.min(
      availableWidth,
      (widget.maxMapHeight ?? double.infinity) * plan.width / plan.height,
    );
    return Size(width, width * plan.height / plan.width);
  }

  Widget _guidanceBanner({Key? key}) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface
          .withValues(alpha: widget.navigationLayout ? 1 : .82),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .15),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: _guidance(RouteGuidanceDisplay.overlay),
    ),
  );

  Widget _statusLayout(Widget status) => !widget.navigationLayout
      ? status
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _guidanceBanner(key: const ValueKey('route-guidance-card')),
            const SizedBox(height: 12),
            status,
            if (widget.floorSelector != null) ...[
              const SizedBox(height: 8),
              widget.floorSelector!,
            ],
            const SizedBox(height: 12),
            _previewControls(),
          ],
        );

  Widget _floatingControls({bool horizontal = false}) => AnimatedBuilder(
    animation: _preview,
    builder: (context, _) {
      final buttons = [
        IconButton(
          tooltip: 'Fit Route',
          icon: const Icon(Icons.route_rounded),
          onPressed: () {
            setState(() => _fullPlan = false);
            _fit(_viewport!, fullPlan: false);
          },
        ),
        IconButton(
          tooltip: 'Full Floor Plan',
          icon: const Icon(Icons.fit_screen_rounded),
          onPressed: () {
            setState(() => _fullPlan = true);
            _fit(_viewport!, fullPlan: true);
          },
        ),
        if (_preview.isAnimating && !_followingVehicle)
          IconButton(
            tooltip: 'Follow Vehicle',
            icon: const Icon(Icons.center_focus_strong_rounded),
            onPressed: () => setState(_beginFollowingVehicle),
          ),
      ];
      return Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
        elevation: 2,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(16),
        child: horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: buttons)
            : Column(mainAxisSize: MainAxisSize.min, children: buttons),
      );
    },
  );

  Widget _guidance(RouteGuidanceDisplay display) => AnimatedBuilder(
    animation: _preview,
    builder: (context, _) {
      final segment = _previewPath!.segmentAt(_preview.value);
      return RoutePreviewGuidance(
        plan: _instructionPlan,
        progress: segment == null ? null : _instructionPlan.progressAt(segment),
        complete: _preview.isCompleted,
        display: display,
        guidanceAction:
            display == RouteGuidanceDisplay.overlay &&
                widget.navigationLayout &&
                widget.voiceGuidance != null
            ? _voiceControl()
            : null,
      );
    },
  );

  Widget _previewControls() => AnimatedBuilder(
    animation: _preview,
    builder: (context, _) {
      final path = _previewPath!;
      final plan = _plan;
      final validCoordinates =
          plan != null &&
          _geometry.orderedNodes
              .where((node) => node.levelId == widget.levelId)
              .every(
                (node) =>
                    node.x >= 0 &&
                    node.y >= 0 &&
                    node.x <= plan.width &&
                    node.y <= plan.height,
              );
      final enabled =
          path.canPlay &&
          widget.previewEnabled &&
          _bytes != null &&
          !_loading &&
          validCoordinates;
      final complete = _preview.isCompleted;
      final segment = path.segmentAt(_preview.value);
      final guidance = segment == null
          ? null
          : _instructionPlan.progressAt(segment);
      return Material(
        color: widget.navigationLayout
            ? Theme.of(context).colorScheme.surface
            : AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: widget.navigationLayout
              ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.destinationSummary != null) ...[
                widget.destinationSummary!,
                const SizedBox(height: 8),
              ],
              Text(
                widget.navigationLayout ? 'Route Preview' : 'Route Preview',
                style: widget.navigationLayout
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.titleSmall,
              ),
              if (!widget.navigationLayout)
                const Text('Route preview. Not live location tracking.'),
              if (!path.canPlay)
                Text(
                  path.crossesLevels
                      ? 'Cross-floor playback is coming in Stage 2B. You can still switch floors manually.'
                      : 'This route has no distance to preview.',
                ),
              if (!path.crossesLevels) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: path.canPlay ? _preview.value : 0,
                  semanticsLabel: 'Route preview progress',
                  semanticsValue: '${(_preview.value * 100).round()}%',
                ),
                const SizedBox(height: 8),
                Text(
                  complete
                      ? 'Preview complete · 100%'
                      : '${(_preview.value * 100).floor()}% of Route Preview',
                ),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !enabled || complete
                        ? null
                        : () => setState(() {
                            if (_preview.isAnimating) {
                              _pausePlayback();
                            } else {
                              _beginFollowingVehicle();
                              _preview.forward();
                            }
                          }),
                    icon: Icon(
                      _preview.isAnimating
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(_preview.isAnimating ? 'Pause' : 'Play'),
                  ),
                  if (widget.navigationLayout)
                    IconButton(
                      tooltip: 'Restart',
                      icon: const Icon(Icons.replay_rounded),
                      onPressed: enabled
                          ? () => setState(() {
                              widget.voiceGuidance?.restart();
                              _stopFollowingVehicle();
                              _preview.reset();
                              _fit(_viewport!, fullPlan: false);
                            })
                          : null,
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () => setState(() {
                              widget.voiceGuidance?.restart();
                              _stopFollowingVehicle();
                              _preview.reset();
                              _fit(_viewport!, fullPlan: false);
                            })
                          : null,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Restart'),
                    ),
                  if (!widget.navigationLayout && widget.voiceGuidance != null)
                    _voiceControl(),
                  if (!widget.navigationLayout &&
                      _preview.isAnimating &&
                      !_followingVehicle)
                    OutlinedButton.icon(
                      onPressed: () => setState(_beginFollowingVehicle),
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: const Text('Follow vehicle'),
                    ),
                ],
              ),
              if (!widget.navigationLayout) const SizedBox(height: 12),
              RoutePreviewGuidance(
                plan: _instructionPlan,
                progress: guidance,
                complete: complete,
                display: RouteGuidanceDisplay.directions,
              ),
              if (widget.parkingAction != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: widget.parkingAction!,
                ),
              ],
              if (widget.parkingFeedback != null) ...[
                const SizedBox(height: 8),
                widget.parkingFeedback!,
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _voiceControl() {
    final voice = widget.voiceGuidance!;
    return AnimatedBuilder(
      animation: voice,
      builder: (context, _) => Tooltip(
        message: voice.unavailableReason ?? 'Voice Guidance For Route Preview',
        child: OutlinedButton.icon(
          onPressed:
              voice.enabled ||
                  (widget.previewEnabled &&
                      _bytes != null &&
                      !_loading &&
                      voice.canEnable)
              ? () => voice.setEnabled(!voice.enabled)
              : null,
          icon: Icon(
            voice.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          ),
          label: Text(
            !voice.canEnable
                ? 'Voice Unavailable'
                : voice.enabled
                ? 'Voice On'
                : 'Voice Off',
          ),
        ),
      ),
    );
  }

  Widget _legend(IconData icon, String label, Color colour) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: colour),
      const SizedBox(width: 4),
      Flexible(child: Text(label)),
    ],
  );
}

class ParkingMapPainter extends CustomPainter {
  ParkingMapPainter({
    required this.geometry,
    required this.levelId,
    required this.routeColour,
    this.markerScale = 1,
    this.previewPosition,
    this.previewHeading,
  });
  final RouteGeometry geometry;
  final String levelId;
  final Color routeColour;
  final double markerScale;
  final Offset? previewPosition;
  final double? previewHeading;

  Offset get previewForward => Offset(
    math.cos(previewHeading ?? -math.pi / 2),
    math.sin(previewHeading ?? -math.pi / 2),
  );

  /// Coordinates are already image pixels; the parent transforms both layers.
  Offset imagePoint(double x, double y) => Offset(x, y);
  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.error != null) return;
    Offset point(node) => imagePoint(node.x, node.y);
    for (final (start, end) in geometry.segments(levelId)) {
      final a = point(start), b = point(end);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 8 * markerScale
          ..strokeCap = StrokeCap.round,
      );
      _arrow(canvas, a, b);
    }
    for (final (from, to, _) in geometry.transitions) {
      for (final node in [from, to]) {
        if (node.levelId == levelId) {
          _marker(
            canvas,
            point(node),
            Icons.swap_vert_rounded,
            const Color(0xFF7B4FA3),
          );
        }
      }
    }
    final route = geometry.orderedNodes;
    if (route.first.levelId == levelId) {
      _marker(canvas, point(route.first), Icons.trip_origin, routeColour);
    }
    if (route.last.levelId == levelId) {
      _marker(
        canvas,
        point(route.last),
        Icons.local_parking_rounded,
        routeColour,
      );
    }
    if (previewPosition != null) {
      // Heading is applied once in image space. The common camera transform
      // then turns both the route and this forward-pointing car together.
      canvas.save();
      canvas.translate(previewPosition!.dx, previewPosition!.dy);
      canvas.rotate((previewHeading ?? -math.pi / 2) + math.pi / 2);
      final pointer = Path()
        ..moveTo(0, -21 * markerScale)
        ..lineTo(-8 * markerScale, -8 * markerScale)
        ..lineTo(8 * markerScale, -8 * markerScale)
        ..close();
      canvas.drawPath(
        pointer,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * markerScale
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(pointer, Paint()..color = const Color(0xFFB45309));
      _marker(
        canvas,
        Offset.zero,
        Icons.directions_car_rounded,
        const Color(0xFFB45309),
      );
      canvas.restore();
    }
  }

  void _marker(Canvas canvas, Offset point, IconData icon, Color colour) {
    canvas.drawCircle(point, 13 * markerScale, Paint()..color = Colors.white);
    canvas.drawCircle(point, 11 * markerScale, Paint()..color = colour);
    final text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 17 * markerScale,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
  }

  void _arrow(Canvas canvas, Offset start, Offset end) {
    final delta = end - start;
    if (delta.distance < .1) return;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = routeColour
        ..strokeWidth = 5 * markerScale
        ..strokeCap = StrokeCap.round,
    );
    final middle = Offset.lerp(start, end, .6)!;
    final angle = math.atan2(delta.dy, delta.dx);
    final length = math.min(10 * markerScale, delta.distance / 3);
    final path = Path();
    for (final side in [-.65, .65]) {
      final point =
          middle -
          Offset(math.cos(angle + side), math.sin(angle + side)) * length;
      path.moveTo(point.dx, point.dy);
      path.lineTo(middle.dx, middle.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2 * markerScale
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant ParkingMapPainter oldDelegate) =>
      oldDelegate.previewPosition != previewPosition ||
      oldDelegate.previewHeading != previewHeading ||
      oldDelegate.geometry != geometry ||
      oldDelegate.levelId != levelId ||
      oldDelegate.routeColour != routeColour ||
      oldDelegate.markerScale != markerScale;
}
