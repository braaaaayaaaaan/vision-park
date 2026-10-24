import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/dashboard_models.dart';
import '../../../data/models/driver_models.dart';
import '../../../shared/formatting/malaysian_date_time.dart';
import 'dashboard_card.dart';

class ActiveSessionCard extends StatelessWidget {
  const ActiveSessionCard({
    required this.parking,
    required this.onViewRoute,
    super.key,
  });

  final ActiveParking parking;
  final VoidCallback onViewRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      title: 'Active Parking Session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                parking.vehicle.plateNumber,
                style: theme.textTheme.headlineMedium,
              ),
              _SessionStatusBadge(status: parking.session.status),
            ],
          ),
          const SizedBox(height: AppSpacing.medium),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: _SessionDetail(
              icon: Icons.local_parking_rounded,
              label: 'Allocated Zone',
              value: '${parking.zone.levelName} · ${parking.zone.name}',
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          _SessionDetail(
            icon: Icons.schedule_rounded,
            label: 'Entry Time',
            value: MalaysianDateTime.format(parking.session.entryTime),
          ),
          if (parking.session.confirmedAt != null) ...[
            const SizedBox(height: 12),
            _SessionDetail(
              icon: Icons.check_circle_outline_rounded,
              label: 'Parking Confirmed',
              value: MalaysianDateTime.format(parking.session.confirmedAt!),
            ),
          ],
          const SizedBox(height: AppSpacing.medium),
          if (parking.hasValidRoute) ...[
            Text(
              'Route Distance · ${parking.route!.distanceMetres.toStringAsFixed(0)} m',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: onViewRoute,
            icon: const Icon(Icons.near_me_outlined),
            label: const Text('View Route'),
          ),
        ],
      ),
    );
  }
}

class _SessionStatusBadge extends StatelessWidget {
  const _SessionStatusBadge({required this.status});

  final ParkingSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (label, icon, background, foreground) = switch (status) {
      ParkingSessionStatus.allocated => (
        'Space Allocated',
        Icons.local_parking_rounded,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      ParkingSessionStatus.occupied => (
        'Parked',
        Icons.check_circle_outline_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      ParkingSessionStatus.completed => (
        'Completed',
        Icons.task_alt_rounded,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };

    return Semantics(
      label: 'Session status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: foreground.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  const _SessionDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
