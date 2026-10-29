import '../../data/repositories/availability_repository.dart';
import '../../data/repositories/status_reminder_repository.dart';
import 'widgets/status_reminder_banner.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/active_session_repository.dart';
import '../../data/models/dashboard_models.dart';
import '../../data/models/driver_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/visible_poller.dart';
import 'home_controller.dart';
import 'allocation_notifications.dart';
import 'widgets/allocation_banner.dart';
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
    this.statusReminderRepository,
    this.availabilityRepository,
    this.isVisible = true,
    this.refreshRevision = 0,
    this.onSignOut,
    this.fullName,
    this.companyName,
    this.paymentSection,
    this.paymentSessionIds = const {},
    this.onRefreshPayments,
    this.onActiveParkingChanged,
    this.allocationNotifications,
    this.onAllocationSelected,
    this.onSessionSelected,
    super.key,
  });

  final ValueChanged<int> onTabSelected;
  final HomeController? controller;
  final DateTime Function()? clock;
  final ActiveSessionRepository? activeSessionRepository;
  final StatusReminderRepository? statusReminderRepository;
  final AvailabilityRepository? availabilityRepository;
  final bool isVisible;
  final int refreshRevision;
  final VoidCallback? onSignOut;
  final String? fullName;
  final String? companyName;
  final Widget? paymentSection;
  final Set<String> paymentSessionIds;
  final Future<void> Function()? onRefreshPayments;
  final ValueChanged<bool>? onActiveParkingChanged;
  final AllocationNotifications? allocationNotifications;
  final ValueChanged<ActiveParking>? onAllocationSelected;
  final ValueChanged<ActiveParking>? onSessionSelected;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  late final Timer _greetingTimer;
  late final VisiblePoller _poller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        HomeController(
          activeSessionRepository: widget.activeSessionRepository,
          availabilityRepository: widget.availabilityRepository,
          allocationNotifications: widget.allocationNotifications,
        );
    _controller.load();
    _controller.refreshParking();
    _controller.addListener(_parkingChanged);
    _poller = VisiblePoller(
      refresh: () => _controller.refreshParking(background: true),
      isVisible: () =>
          mounted &&
          widget.isVisible &&
          ModalRoute.of(context)?.isCurrent != false,
    );
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _parkingChanged() => widget.onActiveParkingChanged?.call(
    _controller.activeSessions.isNotEmpty,
  );

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible &&
        (!oldWidget.isVisible ||
            widget.refreshRevision != oldWidget.refreshRevision)) {
      _controller.refreshParking(background: true);
    }
  }

  @override
  void dispose() {
    _greetingTimer.cancel();
    _poller.dispose();
    _controller.removeListener(_parkingChanged);
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
        final tenant = (widget.companyName ?? data?.profile.tenantName)?.trim();
        final name = (widget.fullName ?? data?.profile.fullName)?.trim();
        final now = (widget.clock ?? DateTime.now)();
        final hasCurrentParking = _controller.activeSessionRepository != null
            ? _controller.sessionStatus == HomeStatus.ready &&
                  _controller.activeSessions.any(
                    (parking) =>
                        parking.session.status !=
                            ParkingSessionStatus.completed &&
                        !widget.paymentSessionIds.contains(parking.session.id),
                  )
            : _controller.status == HomeStatus.ready &&
                  data?.activeParking != null &&
                  data!.activeParking!.session.status !=
                      ParkingSessionStatus.completed;

        final content = SingleChildScrollView(
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
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (name != null && name.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(name, style: theme.textTheme.titleMedium),
                              ],
                              const SizedBox(height: AppSpacing.small),
                              Text(
                                'Your parking journey, in one place.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
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
                                : () {
                                    _controller.refreshParking();
                                    widget.onRefreshPayments?.call();
                                  },
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
                    if (widget.statusReminderRepository != null)
                      StatusReminderBanner(
                        repository: widget.statusReminderRepository!,
                        isVisible: widget.isVisible,
                      ),
                    if (hasCurrentParking) ...[
                      _parkingSection(data),
                      const SizedBox(height: AppSpacing.large),
                    ],
                    if (widget.paymentSection != null) ...[
                      widget.paymentSection!,
                      const SizedBox(height: AppSpacing.small),
                    ],
                    if (_controller.availabilityRepository != null)
                      _availabilitySection(tenant)
                    else if (_controller.status == HomeStatus.ready &&
                        data != null)
                      AvailabilityCard(
                        availability: data.availability,
                        companyName: tenant,
                      )
                    else
                      _unavailableSection(
                        'Parking Availability',
                        session: false,
                      ),
                    const SizedBox(height: AppSpacing.large),
                    if (!hasCurrentParking) _parkingSection(data),
                    const SizedBox(height: AppSpacing.large),
                    QuickAccessCard(onTabSelected: widget.onTabSelected),
                  ],
                ),
              ),
            ),
          ),
        );
        if (widget.onAllocationSelected == null) return content;
        return Column(
          children: [
            AllocationBanner(
              controller: _controller,
              isVisible: widget.isVisible,
              paymentSessionIds: widget.paymentSessionIds,
              onViewNavigation: widget.onAllocationSelected!,
            ),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  void _openSession(ActiveParking parking) {
    final open = widget.onSessionSelected;
    if (open != null) {
      open(parking);
    } else {
      widget.onTabSelected(1);
    }
  }

  Widget _parkingSection(DashboardData? data) {
    if (_controller.activeSessionRepository != null) {
      return _activeSessionsSection();
    }
    if (_controller.status == HomeStatus.ready && data != null) {
      final parking = data.activeParking;
      if (parking != null &&
          parking.session.status != ParkingSessionStatus.completed) {
        return ActiveSessionCard(
          parking: parking,
          onViewRoute: () => _openSession(parking),
        );
      }
      return const EmptyStateCard(
        compact: true,
        icon: Icons.directions_car_outlined,
        title: 'No Active Parking Session',
        message: 'Your current parking session will appear here when one is available.',
      );
    }
    return _unavailableSection('Current Parking Session', session: true);
  }

  Widget _availabilitySection(String? companyName) {
    if (_controller.availabilityStatus == HomeStatus.ready) {
      return AvailabilityCard(
        availability: _controller.availability!,
        companyName: companyName,
      );
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
      final sessions = _controller.activeSessions
          .where(
            (parking) =>
                parking.session.status != ParkingSessionStatus.completed &&
                !widget.paymentSessionIds.contains(parking.session.id),
          )
          .toList();
      if (sessions.isEmpty && _controller.activeSessions.isEmpty) {
        return const EmptyStateCard(
          compact: true,
          icon: Icons.directions_car_outlined,
          title: 'No Active Parking Session',
          message: 'Your current parking session will appear here when one is available.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < sessions.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.large),
            ActiveSessionCard(
              parking: sessions[index],
              onViewRoute: () => _openSession(sessions[index]),
            ),
          ],
        ],
      );
    }
    return DashboardCard(
      title: 'Current Parking Session',
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
            FilledButton.icon(
              onPressed: () => widget.onTabSelected(1),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('View Route'),
            ),
          ],
        ],
      ),
    );
  }
}
