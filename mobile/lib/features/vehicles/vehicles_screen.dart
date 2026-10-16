import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder.dart';

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'My Vehicles',
      description: 'Keep your registered vehicles in one place.',
      icon: Icons.directions_car_outlined,
      emptyTitle: 'Your Vehicles Will Appear Here',
      emptyMessage: 'Vehicle registration and approval details will be available once connected. No vehicle records are loaded.',
    );
  }
}
