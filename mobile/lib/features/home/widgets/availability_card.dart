import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/dashboard_models.dart';
import 'dashboard_card.dart';
import 'occupancy_indicator.dart';
import '../../../shared/vision_park_brand.dart';
import '../../../shared/summary_cards.dart';

class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({
    required this.availability,
    this.companyName,
    super.key,
  });

  final ParkingAvailability availability;
  final String? companyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      title: 'Parking Availability',
      icon: Icons.garage_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (companyName != null && companyName!.trim().isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandIconBadge(Icons.business_rounded, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Company', style: theme.textTheme.labelSmall),
                      Text(
                        companyName!.trim(),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.medium),
          ],
          SummaryCards(
            first: SummaryMetric(
              icon: Icons.directions_car_outlined,
              value: '${availability.availableSpaces}',
              title: 'Spaces Available',
            ),
            second: SummaryMetric(
              icon: Icons.grid_view_rounded,
              value: '${availability.accessibleZoneCount}',
              title: 'Accessible Zones',
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          if (availability.levels.isNotEmpty)
            Text('Tap a floor to view zones', style: theme.textTheme.bodySmall),
          if (availability.levels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.medium),
              child: Text(
                'No Accessible Parking Levels\nNo level availability has been returned for your tenant.',
              ),
            ),
          for (final level in availability.levels) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ExpansionTile(
                key: PageStorageKey('availability-${level.id}'),
                backgroundColor: AppTheme.background,
                collapsedBackgroundColor: AppTheme.background,
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text(level.name, style: theme.textTheme.titleSmall),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${level.availableSpaces} / ${level.totalSpaces} Spaces Available',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    OccupancyIndicator(
                      occupancy: level.occupancy,
                      totalSpaces: level.totalSpaces,
                    ),
                  ],
                ),
                children: [
                  const Divider(),
                  for (final item in level.zones)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.medium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item.zone.name,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            item.zone.availableCapacity == null
                                ? 'Available Spaces Unavailable'
                                : '${item.zone.availableCapacity} / ${item.totalSpaces} Spaces Available',
                          ),
                          const SizedBox(height: AppSpacing.small),
                          OccupancyIndicator(
                            occupancy: item.occupancy,
                            totalSpaces: item.totalSpaces,
                          ),
                        ],
                      ),
                    ),
                  if (level.zones.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('No accessible zones on this floor.'),
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
