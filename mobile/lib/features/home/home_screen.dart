import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Welcome to VisionPark',
      description: 'Your parking journey, in one place.',
      icon: Icons.local_parking_rounded,
      emptyTitle: 'Your Parking Overview',
      emptyMessage: 'Your current parking session and authorised parking options will appear here once connected.',
    );
  }
}
