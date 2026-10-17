import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'account_controller.dart';
import 'widgets/account_settings_card.dart';
import 'widgets/profile_details.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.onVehiclesSelected,
    this.controller,
    this.onSignOut,
    super.key,
  });
  final VoidCallback onVehiclesSelected;
  final AccountController? controller;
  final VoidCallback? onSignOut;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AccountController();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final ready = _controller.status == AccountStatus.ready;
        final profile = _controller.profile;
        return SingleChildScrollView(
          key: const PageStorageKey('account'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Account', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.small),
                    const Text('Your Profile and Parking Access'),
                    const SizedBox(height: AppSpacing.large),
                    if (ready && profile != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.large),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    size: 32,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.medium),
                              Text(
                                'Profile Overview',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: AppSpacing.medium),
                              ProfileDetails(profile: profile),
                            ],
                          ),
                        ),
                      )
                    else if (_controller.status == AccountStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Account',
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      const Text('Loading Account'),
                    ] else if (_controller.status == AccountStatus.error) ...[
                      const EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Account',
                        message: 'Your account information could not be confirmed. Please try again.',
                      ),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Try Again'),
                      ),
                    ] else
                      const EmptyStateCard(
                        icon: Icons.person_outline_rounded,
                        title: 'Your Profile Will Appear Here',
                        message: 'Not Connected. Your profile and company affiliation are unavailable until account services are connected.',
                      ),
                    const SizedBox(height: AppSpacing.large),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.large),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Account Summary',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.medium),
                            Wrap(
                              spacing: AppSpacing.large,
                              runSpacing: AppSpacing.medium,
                              children: [
                                Text(
                                  'Approved Vehicles: ${ready ? _controller.count('approved') : 'Unavailable'}',
                                ),
                                Text(
                                  'Pending Approval: ${ready ? _controller.count('pending') : 'Unavailable'}',
                                ),
                              ],
                            ),
                            if (ready && _controller.vehicles.isEmpty) ...[
                              const SizedBox(height: AppSpacing.small),
                              const Text('No Registered Vehicles'),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    AccountSettingsCard(
                      onSignOut: widget.onSignOut,
                      profile: ready ? profile : null,
                      onVehiclesSelected: widget.onVehiclesSelected,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
