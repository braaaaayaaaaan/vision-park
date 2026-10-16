import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Parking History',
      description: 'Review your previous parking visits.',
      icon: Icons.history_rounded,
      emptyTitle: 'Your Visits Will Appear Here',
      emptyMessage: 'Once connected, you can review your parking sessions and their entry and exit times.',
    );
  }
}
