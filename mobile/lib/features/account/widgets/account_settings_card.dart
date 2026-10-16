import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/driver_models.dart';
import 'profile_details.dart';

class AccountSettingsCard extends StatelessWidget {
  const AccountSettingsCard({
    required this.profile,
    required this.onVehiclesSelected,
    super.key,
  });

  final DriverProfile? profile;
  final VoidCallback onVehiclesSelected;

  void _show(BuildContext context, String title, Widget content) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Account & Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.small),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Personal Information'),
              subtitle: const Text('Read-Only Profile Details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _show(
                context,
                'Personal Information',
                profile == null
                    ? const Text(
                        'Profile information is unavailable until account data is loaded.',
                      )
                    : ProfileDetails(profile: profile!),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('My Vehicles'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onVehiclesSelected,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Security'),
              subtitle: const Text('Authentication Not Connected'),
              onTap: () => _show(
                context,
                'Security Unavailable',
                const Text(
                  'Authentication is not connected in this version. Password changes and security settings are unavailable. No account changes have been made.',
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _show(context, 'Help & Support', const _HelpContent()),
            ),
            const SizedBox(height: AppSpacing.medium),
            OutlinedButton.icon(
              onPressed: () => _show(
                context,
                'Sign Out Unavailable',
                const Text(
                  'Authentication is not connected, so this app cannot sign you out. No authentication session has been changed.',
                ),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpContent extends StatelessWidget {
  const _HelpContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (title, text) in [
          (
            'Vehicle Approval',
            'New vehicle registrations require administrator approval. Contact your company or parking administrator about pending or rejected registrations.',
          ),
          (
            'ANPR Recognition',
            'ANPR reads your number plate at the entrance. Recognition is separate from registration approval and does not guarantee parking access.',
          ),
          (
            'Parking Allocation',
            'An allocation depends on your tenant permissions, available zone capacity and a reachable route.',
          ),
          (
            'Navigation',
            'When an allocated session has a valid route, View Route opens Navigate. The floor-plan interface is still being developed.',
          ),
          (
            'Parking Confirmation',
            'Parking confirmation changes an allocated session to occupied. Use the confirmation flow when it becomes available after integration.',
          ),
          (
            'Need Help?',
            'Contact your company or parking administrator for profile, access or parking assistance. Live account and parking services are not connected in this version.',
          ),
        ]) ...[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.small),
          Text(text),
          const SizedBox(height: AppSpacing.medium),
        ],
      ],
    );
  }
}
