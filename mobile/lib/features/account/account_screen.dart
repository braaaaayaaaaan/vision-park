import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Account',
      description: 'Your profile and parking access.',
      icon: Icons.person_outline_rounded,
      emptyTitle: 'Your Profile Will Appear Here',
      emptyMessage: 'Your profile and tenant details will be available once account access is connected.',
    );
  }
}
