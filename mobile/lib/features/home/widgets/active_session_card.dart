import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/dashboard_models.dart';
import '../../../data/models/driver_models.dart';
import '../../../shared/formatting/malaysian_date_time.dart';

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
    if (parking.session.status == ParkingSessionStatus.completed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final radius = BorderRadius.circular(AppTheme.cornerRadius);
    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onViewRoute,
        borderRadius: radius,
        splashColor: theme.colorScheme.primary.withValues(alpha: .08),
        highlightColor: theme.colorScheme.primary.withValues(alpha: .04),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Current Parking Session',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: secondary,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${parking.zone.levelName} - ${parking.zone.name}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    parking.vehicle.plateNumber,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _SessionStatusBadge(status: parking.session.status),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: AppSpacing.medium),
              _SessionDetail(
                label: 'Entry Time',
                value: MalaysianDateTime.format(parking.session.entryTime),
              ),
              if (parking.session.confirmedAt != null) ...[
                const SizedBox(height: 12),
                _SessionDetail(
                  label: 'Parking Confirmed',
                  value: MalaysianDateTime.format(parking.session.confirmedAt!),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onViewRoute,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('View Route'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionStatusBadge extends StatelessWidget {
  const _SessionStatusBadge({required this.status});
  final ParkingSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final label = status == ParkingSessionStatus.occupied
        ? 'Parked'
        : 'Assigned';
    return Semantics(
      label: 'Session status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  const _SessionDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
      ),
    ],
  );
}
