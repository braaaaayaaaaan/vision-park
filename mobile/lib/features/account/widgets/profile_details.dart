import 'package:flutter/material.dart';

import '../../../data/models/driver_models.dart';

class ProfileDetails extends StatelessWidget {
  const ProfileDetails({required this.profile, this.statusLabel, super.key});
  final DriverProfile profile;
  final String? statusLabel;
  String _provided(String? value) =>
      value == null || value.trim().isEmpty ? 'Not Provided' : value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      (Icons.person_outline_rounded, 'Full Name', _provided(profile.fullName)),
      (Icons.mail_outline_rounded, 'Email Address', _provided(profile.email)),
      (Icons.business_outlined, 'Company', _provided(profile.tenantName)),
      (
        Icons.verified_user_outlined,
        'Account Status',
        statusLabel ??
            (profile.isActive == null
                ? 'Unavailable'
                : profile.isActive!
                ? 'Active'
                : 'Inactive'),
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 56, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Icon(
                    rows[i].$1,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].$2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rows[i].$3,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
