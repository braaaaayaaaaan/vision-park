import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.medium),
            child,
          ],
        ),
      ),
    );
  }
}
