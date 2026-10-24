import 'package:flutter/material.dart';

import '../../../data/repositories/assigned_route_repository.dart';
import '../navigation_controller.dart';
import '../route_voice_guidance.dart';
import 'parking_map.dart';

/// Layout adapter only; route, playback and confirmation keep their own owners.
class RoutePanel extends StatelessWidget {
  const RoutePanel({
    required this.controller,
    this.onMapTouchChanged,
    this.previewEnabled = true,
    this.maxMapHeight,
    this.parkingAction,
    this.parkingFeedback,
    this.voiceGuidance,
    super.key,
  });

  final NavigationController controller;
  final ValueChanged<bool>? onMapTouchChanged;
  final bool previewEnabled;
  final double? maxMapHeight;
  final Widget? parkingAction;
  final Widget? parkingFeedback;
  final RouteVoiceGuidance? voiceGuidance;

  @override
  Widget build(BuildContext context) {
    final parking = controller.data!.parking!;
    final theme = Theme.of(context);
    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.local_parking_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parking.zone.name, style: theme.textTheme.titleMedium),
              Text(parking.zone.levelName, style: theme.textTheme.bodySmall),
              Text(
                controller.routeError == null
                    ? 'Planned Route Distance: ${parking.route!.distanceMetres.toStringAsFixed(0)} m'
                    : 'Route Distance: Unavailable',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    final issue = controller.routeError;
    if (issue != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 16),
              Text('Route Unavailable\n$issue'),
              if (parkingAction != null) ...[
                const SizedBox(height: 12),
                parkingAction!,
              ],
              ?parkingFeedback,
            ],
          ),
        ),
      );
    }
    final graph = controller.data!.graph!;
    final geometry = controller.geometry!;
    final selected = controller.selectedLevelId!;
    final routeLevels = geometry.orderedNodes.map((n) => n.levelId).toSet();
    final level = graph.levels.firstWhere((l) => l.id == selected);
    final imageRepository = controller.routeRepository;
    final floorSelector = Material(
      elevation: 2,
      shadowColor: Colors.black12,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: PopupMenuButton<String>(
        tooltip: 'Select Floor',
        initialValue: selected,
        onSelected: controller.selectLevel,
        itemBuilder: (_) => [
          for (final floor in graph.levels.where(
            (l) => routeLevels.contains(l.id),
          ))
            PopupMenuItem(
              value: floor.id,
              child: Text(
                '${floor.name}${floor.id == parking.zone.levelId ? ' (Destination)' : ''}',
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.layers_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  level.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
    return ParkingMap(
      key: ValueKey(parking.session.id),
      navigationLayout: true,
      voiceGuidance: voiceGuidance,
      maxMapHeight: maxMapHeight,
      floorSelector: floorSelector,
      destinationSummary: summary,
      parkingAction: parkingAction,
      parkingFeedback: parkingFeedback,
      previewEnabled: previewEnabled,
      onTouchInteractionChanged: onMapTouchChanged,
      graph: graph,
      routeNodeIds: geometry.routeIds,
      levelId: selected,
      loadFloorPlan: imageRepository is FloorPlanRepository
          ? (imageRepository as FloorPlanRepository).getFloorPlan
          : null,
    );
  }
}
