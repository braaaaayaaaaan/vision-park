import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/dashboard_models.dart';
import 'dashboard_card.dart';
import 'occupancy_indicator.dart';

class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({required this.availability, super.key});

  final ParkingAvailability availability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      title: 'Parking Availability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.extraLarge,
            runSpacing: AppSpacing.medium,
            children: [
              _Summary(
                value: availability.availableSpaces,
                label: 'Spaces Available',
              ),
              _Summary(
                value: availability.accessibleZoneCount,
                label: 'Accessible Zones',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          Text(
            'Your Tenant’s Parking Access',
            style: theme.textTheme.labelLarge,
          ),
          if (availability.levels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.medium),
              child: Text(
                'No Accessible Parking Levels\nNo level availability has been returned for your tenant.',
              ),
            ),
          for (final level in availability.levels) ...[
            const SizedBox(height: AppSpacing.large),
            const Divider(),
            const SizedBox(height: AppSpacing.medium),
            Text(level.name, style: theme.textTheme.titleMedium),
            Text(
              '${level.availableSpaces} / ${level.totalSpaces} Spaces Available',
            ),
            const SizedBox(height: AppSpacing.small),
            OccupancyIndicator(
              occupancy: level.occupancy,
              totalSpaces: level.totalSpaces,
            ),
            for (final item in level.zones)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.medium,
                  left: AppSpacing.medium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.zone.name, style: theme.textTheme.titleSmall),
                    Text(
                      '${item.zone.availableCapacity} / ${item.totalSpaces} Spaces Available',
                    ),
                    const SizedBox(height: AppSpacing.small),
                    OccupancyIndicator(
                      occupancy: item.occupancy,
                      totalSpaces: item.totalSpaces,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
