import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/driver_models.dart';

class ProfileDetails extends StatelessWidget {
  const ProfileDetails({required this.profile, super.key});
  final DriverProfile profile;

  String _provided(String? value) =>
      value == null || value.trim().isEmpty ? 'Not Provided' : value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, value) in [
          ('Full Name', _provided(profile.fullName)),
          ('Email Address', _provided(profile.email)),
          ('Company / Tenant', _provided(profile.tenantName)),
          (
            'Account Status',
            profile.isActive == null
                ? 'Unavailable'
                : profile.isActive!
                ? 'Active'
                : 'Inactive',
          ),
        ]) ...[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Text(value),
          const SizedBox(height: AppSpacing.medium),
        ],
        const Text('Your profile and company affiliation are read-only here.'),
      ],
    );
  }
}
