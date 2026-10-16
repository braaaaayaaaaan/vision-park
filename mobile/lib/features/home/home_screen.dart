import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'home_controller.dart';
import 'widgets/active_session_card.dart';
import 'widgets/availability_card.dart';
import 'widgets/dashboard_card.dart';
import 'widgets/quick_access_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onTabSelected,
    this.controller,
    this.clock,
    super.key,
  });

  final ValueChanged<int> onTabSelected;
  final HomeController? controller;
  final DateTime Function()? clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  late final Timer _greetingTimer;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? HomeController();
    _controller.load();
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _greetingTimer.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final data = _controller.data;
        final tenant = data?.profile.tenantName;
        final now = (widget.clock ?? DateTime.now)();

        return SingleChildScrollView(
          key: const PageStorageKey('home-dashboard'),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MalaysianDateTime.greeting(now),
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: AppSpacing.small),
                              Text(
                                tenant != null && tenant.trim().isNotEmpty
                                    ? tenant
                                    : 'Your parking journey, in one place.',
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Open Account',
                          onPressed: () => widget.onTabSelected(4),
                          icon: const Icon(Icons.person_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (_controller.status == HomeStatus.ready &&
                        data != null) ...[
                      AvailabilityCard(availability: data.availability),
                      const SizedBox(height: AppSpacing.large),
                      if (data.activeParking != null)
                        ActiveSessionCard(
                          parking: data.activeParking!,
                          onViewRoute: () => widget.onTabSelected(1),
                        )
                      else
                        const EmptyStateCard(
                          icon: Icons.local_parking_outlined,
                          title: 'No Active Parking Session',
                          message: 'Your current parking session will appear here when one is available.',
                        ),
                    ] else ...[
                      _unavailableSection(
                        'Parking Availability',
                        session: false,
                      ),
                      const SizedBox(height: AppSpacing.large),
                      _unavailableSection(
                        'Active Parking Session',
                        session: true,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.large),
                    QuickAccessCard(onTabSelected: widget.onTabSelected),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _unavailableSection(String title, {required bool session}) {
    final status = _controller.status;
    return DashboardCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status == HomeStatus.loading) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Loading Parking Data',
            ),
            const SizedBox(height: AppSpacing.medium),
            const Text('Loading Parking Information'),
          ] else if (status == HomeStatus.error) ...[
            const Text('Unable to Load Parking Information'),
            const SizedBox(height: AppSpacing.small),
            const Text(
              'Please try again. No parking information has been confirmed.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _controller.load,
                child: const Text('Try Again'),
              ),
            ),
          ] else ...[
            const Text('Not Connected'),
            const SizedBox(height: AppSpacing.small),
            Text(
              session
                  ? 'Session information is unavailable until parking services are connected.'
                  : 'Your tenant’s available spaces, levels and zones will appear here once connected.',
            ),
          ],
          if (session) ...[
            const SizedBox(height: AppSpacing.medium),
            const FilledButton(onPressed: null, child: Text('View Route')),
          ],
        ],
      ),
    );
  }
}
