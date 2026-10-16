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
    final status = switch (parking.session.status) {
      ParkingSessionStatus.allocated => 'Allocated',
      ParkingSessionStatus.occupied => 'Occupied',
      ParkingSessionStatus.completed => 'Completed',
    };

    return DashboardCard(
      title: 'Active Parking Session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            parking.vehicle.plateNumber,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.small),
          Text('Session Status: $status'),
          const SizedBox(height: AppSpacing.medium),
          Text('Allocated Zone', style: theme.textTheme.labelLarge),
          Text('${parking.zone.name} · ${parking.zone.levelName}'),
          const SizedBox(height: AppSpacing.medium),
          Text('ANPR Verification', style: theme.textTheme.labelLarge),
          Text(
            parking.anprInformation ??
                'Verification information is unavailable.',
          ),
          if (parking.anprVerifiedAt != null)
            Text(MalaysianDateTime.format(parking.anprVerifiedAt!)),
          const SizedBox(height: AppSpacing.medium),
          Text('Route Distance', style: theme.textTheme.labelLarge),
          Text(
            parking.hasValidRoute
                ? '${parking.route!.distanceMetres.toStringAsFixed(0)} m'
                : 'Route information is unavailable.',
          ),
          const SizedBox(height: AppSpacing.large),
          FilledButton.icon(
            onPressed: parking.hasValidRoute ? onViewRoute : null,
            icon: const Icon(Icons.near_me_outlined),
            label: const Text('View Route'),
          ),
          if (!parking.hasValidRoute) ...[
            const SizedBox(height: AppSpacing.small),
            const Text('A valid route for an allocated session is required.'),
          ],
        ],
      ),
    );
  }
}
