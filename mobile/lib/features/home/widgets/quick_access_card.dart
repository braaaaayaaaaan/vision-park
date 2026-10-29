import 'package:flutter/material.dart';

import '../../../shared/vision_park_brand.dart';

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({required this.onTabSelected, super.key});

  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick Access',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final (label, icon, index) in [
              ('My Vehicles', Icons.directions_car_outlined, 2),
              ('Parking History', Icons.history_rounded, 3),
              ('Account', Icons.person_outline_rounded, 4),
            ])
              ListTile(
                dense: true,
                minTileHeight: 60,
                minVerticalPadding: 6,
                minLeadingWidth: 20,
                horizontalTitleGap: 12,
                contentPadding: EdgeInsets.zero,
                leading: BrandIconBadge(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => onTabSelected(index),
              ),
          ],
        ),
      ),
    );
  }
}
