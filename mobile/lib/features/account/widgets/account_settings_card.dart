import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

class AccountSettingsCard extends StatelessWidget {
  const AccountSettingsCard({
    required this.onVehiclesSelected,
    this.onSignOut,
    this.busy = false,
    super.key,
  });
  final VoidCallback onVehiclesSelected;
  final VoidCallback? onSignOut;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        ListTile(
          minTileHeight: 48,
          minVerticalPadding: 8,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const SizedBox(
            width: 24,
            child: Icon(Icons.directions_car_outlined),
          ),
          title: const Text('My Vehicles'),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : onVehiclesSelected,
        ),
        const Divider(height: 1, indent: 56, endIndent: 16),
        ListTile(
          minTileHeight: 48,
          minVerticalPadding: 8,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const SizedBox(width: 24, child: Icon(Icons.help_outline)),
          title: const Text('Help and Support'),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    scrollable: true,
                    title: const Text('Help and Support'),
                    content: const _HelpContent(),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
        ),
        const Divider(height: 1, indent: 56, endIndent: 16),
        ListTile(
          minTileHeight: 48,
          minVerticalPadding: 8,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const SizedBox(width: 24, child: Icon(Icons.logout_rounded)),
          iconColor: Theme.of(context).colorScheme.error,
          textColor: Theme.of(context).colorScheme.error,
          title: Text(busy ? 'Signing Out…' : 'Sign Out'),
          onTap: busy ? null : onSignOut,
        ),
      ],
    ),
  );
}

class _HelpContent extends StatelessWidget {
  const _HelpContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, title, text) in [
          (
            Icons.directions_car_outlined,
            'Vehicle Approval',
            'New registrations need administrator approval. Ask your administrator about pending or rejected requests.',
          ),
          (
            Icons.camera_alt_outlined,
            'ANPR Recognition',
            'Entrance cameras read your plate. Recognition is separate from approval and does not guarantee parking access.',
          ),
          (
            Icons.local_parking_outlined,
            'Parking Allocation',
            'Requires tenant permission, available zone capacity and a reachable route.',
          ),
          (
            Icons.route_outlined,
            'Navigation',
            'With a valid route, tap View Route to open Navigate and follow it to your allocated space.',
          ),
          (
            Icons.check_circle_outline_rounded,
            'Parking Confirmation',
            'Confirm at your allocated space to change the session from allocated to occupied.',
          ),
          (
            Icons.support_agent_outlined,
            'Need Help?',
            'Contact your company or parking administrator for profile, access or parking help.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.small),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              if (icon == Icons.directions_car_outlined)
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 12,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.small),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.35,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
