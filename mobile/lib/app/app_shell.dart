import '../data/repositories/history_repository.dart';
import '../data/repositories/status_reminder_repository.dart';

import 'dart:async';

import '../data/repositories/payment_repository.dart';
import '../data/services/payment_operations.dart';
import '../features/payments/payments_controller.dart';
import '../features/payments/payments_screen.dart';
import '../features/payments/checkout_screen.dart';
import '../features/payments/receipt_screen.dart';
import '../features/payments/payment_widgets.dart';
import '../features/payments/wallet_cards.dart';
import '../features/payments/top_up_sheet.dart';
import '../data/repositories/vehicle_repository.dart';
import '../data/repositories/assigned_route_repository.dart';
import '../data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';

import '../data/repositories/active_session_repository.dart';
import '../data/repositories/auth_repository.dart';

import '../features/account/account_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/allocation_notifications.dart';
import '../features/home/allocation_sound.dart';
import '../features/home/home_controller.dart';
import '../data/models/dashboard_models.dart';
import '../features/navigation/navigation_controller.dart';
import '../features/navigation/navigation_screen.dart';
import '../features/navigation/parking_reminder_schedule.dart';
import '../features/navigation/route_voice_guidance.dart';
import '../features/navigation/widgets/parking_reminder_dialog.dart';
import '../features/vehicles/vehicles_screen.dart';
import 'app_theme.dart';
import 'driver_bottom_navigation.dart';
import '../data/services/password_change.dart';
import '../shared/visible_poller.dart';
import '../shared/vision_park_brand.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    this.onSignOut,
    this.passwordChange,
    this.profile,
    this.activeSessionRepository,
    this.statusReminderRepository,
    this.availabilityRepository,
    this.routeRepository,
    this.vehicleRepository,
    this.historyRepository,
    this.paymentRepository,
    this.paymentOperations,
    this.paymentsController,
    this.allocationNotifications,
    this.parkingReminderClock,
    super.key,
  });

  final Future<void> Function()? onSignOut;
  final PasswordChangeService? passwordChange;
  final AuthProfile? profile;
  final ActiveSessionRepository? activeSessionRepository;
  final StatusReminderRepository? statusReminderRepository;
  final AvailabilityRepository? availabilityRepository;
  final AssignedRouteRepository? routeRepository;
  final VehicleRepository? vehicleRepository;
  final HistoryRepository? historyRepository;
  final PaymentRepository? paymentRepository;
  final PaymentOperationStore? paymentOperations;
  final PaymentsController? paymentsController;
  final AllocationNotifications? allocationNotifications;
  final DateTime Function()? parkingReminderClock;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _parkingRevision = 0;
  int _paymentRevision = 0;
  ActiveParking? _requestedAllocation;
  PaymentsController? _payments;
  VisiblePoller? _paymentPoller;
  bool _foreground = true, _paymentRouteOpen = false;
  Set<String> _seenPending = {};
  late final HomeController _home;
  late final NavigationController _navigation;
  late final RouteVoiceGuidance _voice;
  ParkingReminderSchedule? _parkingReminder;
  ({DialogRoute<bool> route, ActiveParking parking})? _openReminder;
  int _handledSessionRevision = 0;
  bool _reminderCheckQueued = false;

  Set<String> get _paymentSessionIds =>
      _payments?.pending.map((charge) => charge.sessionId).toSet() ?? const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _home = HomeController(
      activeSessionRepository: widget.activeSessionRepository,
      availabilityRepository: widget.availabilityRepository,
      allocationNotifications: widget.allocationNotifications,
    );
    _navigation = NavigationController(routeRepository: widget.routeRepository);
    _voice = RouteVoiceGuidance();
    final profile = widget.profile;
    if (profile != null &&
        widget.activeSessionRepository != null &&
        _navigation.hasConfirmationService) {
      final reminder = _parkingReminder = ParkingReminderSchedule(
        profile.id,
        widget.parkingReminderClock ?? DateTime.now,
      );
      _home.addListener(_queueReminderCheck);
      unawaited(reminder.restore().then((_) => _queueReminderCheck()));
    }
    if (profile != null &&
        widget.activeSessionRepository != null &&
        widget.routeRepository != null) {
      _home.addListener(_queueAllocationNavigation);
    }
    if (widget.paymentRepository != null) {
      _payments =
          widget.paymentsController ??
          PaymentsController(
            widget.paymentRepository!,
            widget.paymentOperations ?? PreferencesPaymentOperations(),
          );
      _payments!.addListener(_paymentChanged);
      unawaited(_payments!.refresh());
      _paymentPoller = VisiblePoller(
        refresh: () => _payments!.refresh(background: true),
        hasError: () => _payments!.error != null,
        isVisible: () =>
            mounted &&
            _foreground &&
            !_paymentRouteOpen &&
            ModalRoute.of(context)?.isCurrent != false &&
            (_selectedIndex == 0 ||
                _selectedIndex == 1 ||
                _selectedIndex == 4) &&
            _payments!.isCurrentOwner,
      );
    }
  }

  bool _pollReminderSessions() =>
      mounted &&
      _parkingReminder != null &&
      _foreground &&
      !_paymentRouteOpen &&
      (_openReminder?.route.isCurrent == true ||
          ModalRoute.isCurrentOf(context) == true);

  void _queueReminderCheck() {
    if (!mounted || _reminderCheckQueued) return;
    _reminderCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reminderCheckQueued = false;
      if (mounted) _checkParkingReminder();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isReminderAllocation(ActiveParking parking) =>
      AllocationNotifications.isAllocated(parking) &&
      !_paymentSessionIds.contains(parking.session.id);

  ActiveParking? _currentAllocation(ActiveParking target) => _home
      .activeSessions
      .where(
        (parking) =>
            parking.session.id == target.session.id &&
            parking.zone.id == target.zone.id &&
            parking.vehicle.id == target.vehicle.id &&
            _isReminderAllocation(parking),
      )
      .firstOrNull;

  bool get _sessionReadVerified =>
      _home.sessionStatus == HomeStatus.ready &&
      _home.sessionError == null &&
      !_home.sessionsRefreshing;

  void _queueAllocationNavigation() {
    final allocations = _home.allocationNotifications;
    if (!_sessionReadVerified || !allocations.hasPendingNavigation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_foreground ||
          !_sessionReadVerified ||
          _paymentRouteOpen ||
          _payments?.busy == true ||
          _navigation.confirming ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      final parking = allocations.takeNavigationAllocation();
      if (parking != null &&
          !_paymentSessionIds.contains(parking.session.id) &&
          (_selectedIndex != 1 ||
              _navigation.selectedSessionId != parking.session.id)) {
        _openParkingSession(parking);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkParkingReminder() {
    final schedule = _parkingReminder;
    if (schedule == null) return;
    if (!_foreground) {
      _closeReminder(snooze: true);
      return;
    }
    if (!schedule.ready ||
        !_sessionReadVerified ||
        _home.sessionRevision <= _handledSessionRevision) {
      return;
    }
    _handledSessionRevision = _home.sessionRevision;
    final open = _openReminder?.parking;
    if (open != null) {
      if (_currentAllocation(open) == null) _closeReminder();
      return;
    }
    if (_paymentRouteOpen ||
        _payments?.busy == true ||
        _navigation.confirming ||
        ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    final parking = _home.activeSessions
        .where(
          (parking) =>
              _isReminderAllocation(parking) && schedule.isDue(parking.session),
        )
        .firstOrNull;
    if (parking != null) unawaited(_showReminder(parking, schedule));
  }

  Future<void> _showReminder(
    ActiveParking parking,
    ParkingReminderSchedule schedule,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: false,
      builder: (_) => ParkingReminderDialog(
        levelName: parking.zone.levelName,
        zoneName: parking.zone.name,
        plateNumber: parking.vehicle.plateNumber,
        onConfirm: () => _confirmFromReminder(parking),
      ),
    );
    // Keep a cooldown even if the app is closed with the dialog still open.
    schedule.snooze(parking.session.id);
    _openReminder = (route: route, parking: parking);
    final result = navigator.push(route);
    if (!_voice.isSpeakingOrPlaying) unawaited(AllocationSound.play());
    final confirmed = await result;
    if (!mounted || !identical(_openReminder?.route, route)) return;
    _openReminder = null;
    if (confirmed != true) schedule.snooze(parking.session.id);
  }

  void _closeReminder({bool snooze = false}) {
    final open = _openReminder;
    if (open == null) return;
    _openReminder = null;
    if (snooze) _parkingReminder?.snooze(open.parking.session.id);
    if (open.route.isActive) open.route.navigator?.removeRoute(open.route);
  }

  Future<String?> _confirmFromReminder(ActiveParking target) async {
    final route = _openReminder?.route;
    const unavailable =
        'Unable to verify this parking session. Check your connection and try again.';
    await _home.loadSessions(background: true);
    ActiveParking? currentAllocation() =>
        mounted &&
            _foreground &&
            identical(_openReminder?.route, route) &&
            route?.isCurrent == true &&
            _payments?.busy != true &&
            _sessionReadVerified
        ? _currentAllocation(target)
        : null;
    if (currentAllocation() == null) return unavailable;
    final error = await _navigation.confirmAllocation(currentAllocation);
    if (!mounted) return unavailable;
    if (error == null) {
      _parkingConfirmed(target.session.id);
      return null;
    }
    unawaited(_home.refreshSessionsAfterChange(background: true));
    return error;
  }

  void _parkingConfirmed(String? id) {
    if (id != null) _parkingReminder?.markConfirmed(id);
    setState(() => _parkingRevision++);
    if (_selectedIndex != 0) {
      unawaited(_home.refreshSessionsAfterChange(background: true));
    }
  }

  void _paymentChanged() {
    if (!mounted) return;
    final ids = _payments!.pending.map((charge) => charge.id).toSet();
    final settled =
        !_payments!.loading &&
        _payments!.error == null &&
        _seenPending.difference(ids).isNotEmpty;
    setState(() {
      if (settled) {
        _parkingRevision++;
        _paymentRevision++;
      }
      _seenPending = ids;
    });
  }

  Future<void> _refreshPayments() async {
    await _payments?.refresh(background: true);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) _requestedAllocation = null;
    });
    if (index == 0 || index == 1 || index == 4) unawaited(_refreshPayments());
  }

  void _openParkingSession(ActiveParking parking) => setState(() {
    _requestedAllocation = parking;
    _selectedIndex = 1;
  });

  void _refreshAfterPayment() => setState(() {
    _parkingRevision++;
    _paymentRevision++;
  });

  Future<void> _openPayments({
    String? chargeId,
    String? sessionId,
    bool topUp = false,
  }) async {
    if (_payments == null || _paymentRouteOpen) return;
    _paymentRouteOpen = true;
    try {
      if (topUp) {
        await showWalletTopUp(context, _payments!);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => chargeId != null
                ? CheckoutScreen(payments: _payments!, chargeId: chargeId)
                : sessionId != null
                ? ReceiptScreen(payments: _payments!, sessionId: sessionId)
                : PaymentsScreen(controller: _payments!),
          ),
        );
      }
      if (mounted) {
        await _refreshPayments();
        if (mounted) _refreshAfterPayment();
      }
    } finally {
      _paymentRouteOpen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_parkingReminder != null && !_foreground) {
      _handledSessionRevision = _home.sessionRevision;
      _closeReminder(snooze: true);
    }
    if (_foreground) {
      unawaited(_refreshPayments());
      _refreshAfterPayment();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final route = _openReminder?.route;
    if (route != null) {
      // The auth gate can remove the shell during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    _home.dispose();
    _navigation.dispose();
    _voice.dispose();
    _paymentPoller?.dispose();
    _payments?.removeListener(_paymentChanged);
    if (widget.paymentsController == null) _payments?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const VisionParkBrand()),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            HomeScreen(
              controller: _home,
              pollSessionsOffHome: _pollReminderSessions,
              onAllocationSelected: _openParkingSession,
              onSessionSelected: _openParkingSession,
              paymentSection: _payments == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WalletBalanceCard(
                          compact: true,
                          balance: _payments!.wallet?.balance,
                          loading: _payments!.loading,
                          unavailable:
                              _payments!.error != null ||
                              !_payments!.isCurrentOwner,
                          onOpen: () => _openPayments(),
                          onTopUp: () => _openPayments(topUp: true),
                        ),
                        const SizedBox(height: AppSpacing.large),
                        if (_payments!.error != null)
                          PaymentPanel(
                            children: [
                              const Text(
                                'Payment status could not be checked. Parking information is shown separately.',
                              ),
                              TextButton(
                                onPressed: _refreshPayments,
                                child: const Text('Retry Payments'),
                              ),
                            ],
                          ),
                        for (final charge in _payments!.pending)
                          PaymentRequiredCard(
                            charge: charge,
                            onOpen: () => _openPayments(chargeId: charge.id),
                          ),
                      ],
                    ),
              paymentSessionIds: _paymentSessionIds,
              onRefreshPayments: _refreshPayments,
              fullName: widget.profile?.fullName,
              companyName: widget.profile?.companyName,
              refreshRevision: _parkingRevision,
              statusReminderRepository: widget.statusReminderRepository,
              isVisible: _selectedIndex == 0,
              onSignOut: widget.onSignOut,
              onTabSelected: _selectTab,
            ),
            NavigationScreen(
              controller: _navigation,
              voiceGuidance: _voice,
              requestedAllocation: _requestedAllocation,
              refreshRevision: _paymentRevision,
              paymentSessionIds: _paymentSessionIds,
              onPaymentSelected: (sessionId) {
                final charge = _payments?.pending
                    .where((charge) => charge.sessionId == sessionId)
                    .firstOrNull;
                if (charge != null) {
                  unawaited(_openPayments(chargeId: charge.id));
                }
              },
              onParkingConfirmed: () =>
                  _parkingConfirmed(_navigation.data?.parking?.session.id),
              isVisible: _selectedIndex == 1,
            ),
            VehiclesScreen(
              vehicleRepository: widget.vehicleRepository,
              isVisible: _selectedIndex == 2,
            ),
            HistoryScreen(
              refreshRevision: _paymentRevision,
              onReceiptSelected: _payments == null
                  ? null
                  : (sessionId) => _openPayments(sessionId: sessionId),
              historyRepository: widget.historyRepository,
              isVisible: _selectedIndex == 3,
            ),
            AccountScreen(
              paymentsController: _payments,
              isVisible: _selectedIndex == 4,
              onPaymentChanged: _refreshAfterPayment,
              profile: widget.profile,
              passwordChange: widget.passwordChange,
              onSignOut: widget.onSignOut,
              onVehiclesSelected: () {
                setState(() => _selectedIndex = 2);
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          DriverBottomNavigation(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
          ),
        ],
      ),
    );
  }
}
