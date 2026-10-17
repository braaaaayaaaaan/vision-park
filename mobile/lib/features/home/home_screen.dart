import '../../data/repositories/availability_repository.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/active_session_repository.dart';
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
    this.activeSessionRepository,
    this.availabilityRepository,
    this.isVisible = true,
    this.refreshRevision = 0,
    this.onSignOut,
    super.key,
  });

  final ValueChanged<int> onTabSelected;
  final HomeController? controller;
  final DateTime Function()? clock;
  final ActiveSessionRepository? activeSessionRepository;
  final AvailabilityRepository? availabilityRepository;
  final bool isVisible;
  final int refreshRevision;
  final VoidCallback? onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  late final Timer _greetingTimer;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        HomeController(
          activeSessionRepository: widget.activeSessionRepository,
          availabilityRepository: widget.availabilityRepository,
        );
    _controller.load();
    _controller.refreshParking();
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isVisible && !oldWidget.isVisible) ||
        widget.refreshRevision != oldWidget.refreshRevision) {
      _controller.refreshParking();
    }
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
                        if (_controller.activeSessionRepository != null ||
                            _controller.availabilityRepository != null)
                          IconButton(
                            tooltip: _controller.availabilityRepository == null
                                ? 'Refresh Active Sessions'
                                : 'Refresh Parking',
                            onPressed:
                                _controller.sessionStatus ==
                                        HomeStatus.loading ||
                                    _controller.availabilityStatus ==
                                        HomeStatus.loading
                                ? null
                                : _controller.refreshParking,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        IconButton.filledTonal(
                          tooltip: 'Open Account',
                          onPressed: () => widget.onTabSelected(4),
                          icon: const Icon(Icons.person_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (_controller.availabilityRepository != null)
                      _availabilitySection()
                    else if (_controller.status == HomeStatus.ready &&
                        data != null)
                      AvailabilityCard(availability: data.availability)
                    else
                      _unavailableSection(
                        'Parking Availability',
                        session: false,
                      ),
                    const SizedBox(height: AppSpacing.large),
                    if (_controller.activeSessionRepository != null)
                      _activeSessionsSection()
                    else if (_controller.status == HomeStatus.ready &&
                        data != null) ...[
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

  Widget _availabilitySection() {
    if (_controller.availabilityStatus == HomeStatus.ready) {
      return AvailabilityCard(availability: _controller.availability!);
    }
    return DashboardCard(
      title: 'Parking Availability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.availabilityStatus == HomeStatus.loading) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Loading Parking Availability',
            ),
            const SizedBox(height: AppSpacing.medium),
            const Text('Loading Parking Availability'),
          ] else ...[
            Text(
              _controller.availabilityError ??
                  'Parking availability is unavailable.',
            ),
            TextButton(
              onPressed:
                  _controller.availabilityExpired && widget.onSignOut != null
                  ? widget.onSignOut
                  : _controller.loadAvailability,
              child: Text(
                _controller.availabilityExpired && widget.onSignOut != null
                    ? 'Sign Out'
                    : 'Try Again',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeSessionsSection() {
    if (_controller.sessionStatus == HomeStatus.ready) {
      if (_controller.activeSessions.isEmpty) {
        return const EmptyStateCard(
          icon: Icons.local_parking_outlined,
          title: 'No Active Parking Session',
          message: 'Your current parking session will appear here when one is available.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (
            var index = 0;
            index < _controller.activeSessions.length;
            index++
          ) ...[
            if (index > 0) const SizedBox(height: AppSpacing.large),
            ActiveSessionCard(
              parking: _controller.activeSessions[index],
              onViewRoute: () => widget.onTabSelected(1),
            ),
          ],
        ],
      );
    }
    return DashboardCard(
      title: 'Active Parking Session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.sessionStatus == HomeStatus.loading) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Loading Active Sessions',
            ),
            const SizedBox(height: AppSpacing.medium),
            const Text('Loading Active Parking Sessions'),
          ] else ...[
            Text(
              _controller.sessionError ??
                  'Active parking sessions are unavailable.',
            ),
            const SizedBox(height: AppSpacing.small),
            TextButton(
              onPressed: _controller.sessionExpired && widget.onSignOut != null
                  ? widget.onSignOut
                  : _controller.loadSessions,
              child: Text(
                _controller.sessionExpired && widget.onSignOut != null
                    ? 'Sign Out'
                    : 'Try Again',
              ),
            ),
          ],
        ],
      ),
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
