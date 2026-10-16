import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../navigation_controller.dart';
import 'parking_map.dart';

class RoutePanel extends StatelessWidget {
  const RoutePanel({required this.controller, super.key});
  final NavigationController controller;

  @override
  Widget build(BuildContext context) {
    final issue = controller.routeError;
    if (issue != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Text('Route Unavailable\n$issue'),
        ),
      );
    }
    final data = controller.data!;
    final graph = data.graph!;
    final geometry = controller.geometry!;
    final parking = data.parking!;
    final selected = controller.selectedLevelId!;
    String levelName(String id) =>
        graph.levels.firstWhere((level) => level.id == id).name;
    final start = geometry.orderedNodes.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Route Map', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.medium),
            Wrap(
              spacing: AppSpacing.small,
              runSpacing: AppSpacing.small,
              children: [
                for (final level in graph.levels)
                  ChoiceChip(
                    label: Text(
                      '${level.name}${level.id == parking.zone.levelId ? ' (Destination)' : ''}',
                    ),
                    selected: selected == level.id,
                    onSelected: (_) => controller.selectLevel(level.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.medium),
            ParkingMap(
              graph: graph,
              routeNodeIds: geometry.routeIds,
              levelId: selected,
            ),
            for (final (from, to, label) in geometry.transitions)
              if (from.levelId == selected || to.levelId == selected)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.small),
                  child: Text(
                    '$label: ${levelName(from.levelId)} to ${levelName(to.levelId)}',
                  ),
                ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'Route Directions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.small),
            if (data.instructions.isNotEmpty)
              for (var index = 0; index < data.instructions.length; index++)
                Text('${index + 1}. ${data.instructions[index]}')
            else ...[
              Text(
                'Start: ${start.label ?? (start.nodeType == 'building_entrance' ? 'Entrance' : 'Route Start')} - ${levelName(start.levelId)}',
              ),
              Text(
                'Destination: ${parking.zone.name} - ${parking.zone.levelName}',
              ),
              const Text(
                'Detailed turn instructions are unavailable. Follow the highlighted fixed route and posted signs.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
