import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../route_instructions.dart';

enum RouteGuidanceDisplay { full, overlay, directions }

/// Presentation only. The map owns playback and supplies the existing clock's
/// segment-based progress; expanding directions never changes that progress.
class RoutePreviewGuidance extends StatelessWidget {
  const RoutePreviewGuidance({
    required this.plan,
    this.progress,
    this.complete = false,
    this.display = RouteGuidanceDisplay.full,
    this.guidanceAction,
    super.key,
  });

  final RouteInstructionPlan plan;
  final RouteInstructionProgress? progress;
  final bool complete;
  final RouteGuidanceDisplay display;
  final Widget? guidanceAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = display != RouteGuidanceDisplay.directions;
    final directions = display != RouteGuidanceDisplay.overlay;
    final compact =
        display == RouteGuidanceDisplay.overlay &&
        MediaQuery.textScalerOf(context).scale(14) > 20;
    if (plan.error != null || plan.instructions.isEmpty) {
      if (!summary) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (display != RouteGuidanceDisplay.overlay ||
              guidanceAction != null) ...[
            _heading(context),
            const SizedBox(height: 4),
          ],
          Text(
            'Detailed Directions Unavailable',
            style: display == RouteGuidanceDisplay.overlay
                ? theme.textTheme.bodySmall?.copyWith(height: 1.15)
                : null,
          ),
          if (guidanceAction != null) ...[
            const SizedBox(height: 8),
            guidanceAction!,
          ],
        ],
      );
    }

    final state = progress;
    final staticDirections = plan.crossesLevels;
    var target = 0;
    double? distance;
    if (complete || (!staticDirections && !plan.canSynchronizePreview)) {
      target = plan.instructions.length - 1;
      distance = 0;
    } else if (state != null) {
      final active = plan.instructions[state.instructionIndex];
      // At the exact boundary, show the maneuver at zero metres before advancing.
      final atManeuver =
          active.maneuver != RouteManeuver.departure &&
          (state.travelledMetres - active.distanceFromStartMetres).abs() < 1e-6;
      target = atManeuver
          ? state.instructionIndex
          : math.min(state.instructionIndex + 1, plan.instructions.length - 1);
      distance = math.max(
        0,
        plan.instructions[target].distanceFromStartMetres -
            state.travelledMetres,
      );
    } else {
      target = math.min(1, plan.instructions.length - 1);
    }
    final instruction = plan.instructions[target];
    final next = target + 1 < plan.instructions.length
        ? plan.instructions[target + 1]
        : null;
    final arrived =
        !staticDirections &&
        target == plan.instructions.length - 1 &&
        distance == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary) ...[
          _heading(
            context,
            compact: compact,
            staticDirections: staticDirections,
          ),
          if (staticDirections && !compact)
            const Text(
              'Static Directions Only · Cross-Floor Playback Unavailable',
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon(instruction.maneuver),
                size: 28,
                color: theme.colorScheme.primary,
                semanticLabel: _label(instruction.maneuver),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact || (!staticDirections && !arrived))
                      Text(
                        arrived
                            ? 'Preview Arrival'
                            : staticDirections
                            ? '${instruction.distanceFromStartMetres.round()} m From Route Start'
                            : compact
                            ? '${(distance ?? 0).round()} m'
                            : '${(distance ?? 0).round()} m to Maneuver',
                        key: const ValueKey('maneuver-distance'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          height: display == RouteGuidanceDisplay.overlay
                              ? 1.1
                              : null,
                        ),
                      ),
                    Text(
                      compact ? _compactText(instruction) : instruction.text,
                      semanticsLabel: instruction.text,
                      maxLines: compact ? 3 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      key: const ValueKey('upcoming-instruction'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: display == RouteGuidanceDisplay.overlay
                            ? 1.15
                            : null,
                      ),
                    ),
                    if (next != null && !compact)
                      Text(
                        'Then: ${next.text}',
                        key: const ValueKey('following-instruction'),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (guidanceAction != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: guidanceAction!),
          ],
        ],
        if (directions)
          ExpansionTile(
            // Separate the expanded bool from Navigate's saved double scroll offset.
            key: const PageStorageKey('route-preview-all-directions'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'View All Directions',
              style: theme.textTheme.labelLarge,
            ),
            children: [
              for (var i = 0; i < plan.instructions.length; i++)
                Semantics(
                  selected: !staticDirections && i == target,
                  child: Container(
                    key: ValueKey('direction-$i'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: !staticDirections && i == target
                          ? theme.colorScheme.primary.withValues(alpha: .07)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _icon(plan.instructions[i].maneuver),
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${i + 1}. ${plan.instructions[i].text}'),
                              Text(
                                '${plan.instructions[i].distanceFromStartMetres.round()} m from Start · ${plan.instructions[i].levelName}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _heading(
    BuildContext context, {
    bool compact = false,
    bool staticDirections = false,
  }) => Text(
    compact
        ? (staticDirections ? 'Static' : 'Preview')
        : 'Route Preview Assistance',
    style: display == RouteGuidanceDisplay.overlay
        ? Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.1)
        : Theme.of(context).textTheme.titleSmall,
  );

  static String _compactText(RouteInstruction instruction) =>
      switch (instruction.maneuver) {
        RouteManeuver.arrival => 'Zone Entrance',
        RouteManeuver.ramp => instruction.text.replaceFirst(
          'Take the ramp to ',
          'Ramp to ',
        ),
        RouteManeuver.straight => 'Continue Along Route',
        _ => instruction.text.replaceFirst(RegExp(r'\.$'), ''),
      };

  static IconData _icon(RouteManeuver maneuver) => switch (maneuver) {
    RouteManeuver.departure => Icons.login_rounded,
    RouteManeuver.straight => Icons.straight_rounded,
    RouteManeuver.left => Icons.turn_left_rounded,
    RouteManeuver.right => Icons.turn_right_rounded,
    RouteManeuver.ramp => Icons.swap_vert_rounded,
    RouteManeuver.arrival => Icons.flag_rounded,
  };

  static String _label(RouteManeuver maneuver) => switch (maneuver) {
    RouteManeuver.departure => 'Departure',
    RouteManeuver.straight => 'Continue',
    RouteManeuver.left => 'Turn Left',
    RouteManeuver.right => 'Turn Right',
    RouteManeuver.ramp => 'Ramp',
    RouteManeuver.arrival => 'Arrival',
  };
}
