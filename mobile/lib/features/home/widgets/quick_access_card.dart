import 'package:flutter/material.dart';

import 'dashboard_card.dart';

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({required this.onTabSelected, super.key});

  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      title: 'Quick Access',
      child: Column(
        children: [
          for (final (label, icon, index) in [
            ('My Vehicles', Icons.directions_car_outlined, 2),
            ('Parking History', Icons.history_rounded, 3),
            ('Account', Icons.person_outline_rounded, 4),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onTabSelected(index),
            ),
        ],
      ),
    );
  }
}
