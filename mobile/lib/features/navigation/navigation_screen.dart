import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder.dart';

class NavigationScreen extends StatelessWidget {
  const NavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Navigation',
      description: 'Find your way to your allocated parking zone.',
      icon: Icons.route_rounded,
      emptyTitle: 'Your Route Will Appear Here',
      emptyMessage: 'Once connected, an active allocation will provide your destination and floor plan. No route is loaded.',
    );
  }
}
