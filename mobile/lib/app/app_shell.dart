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
import '../data/models/dashboard_models.dart';
import '../features/navigation/navigation_screen.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (_foreground) {
      unawaited(_refreshPayments());
      _refreshAfterPayment();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
              allocationNotifications: widget.allocationNotifications,
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
              paymentSessionIds:
                  _payments?.pending
                      .map((charge) => charge.sessionId)
                      .toSet() ??
                  const {},
              onRefreshPayments: _refreshPayments,
              fullName: widget.profile?.fullName,
              companyName: widget.profile?.companyName,
              refreshRevision: _parkingRevision,
              activeSessionRepository: widget.activeSessionRepository,
              statusReminderRepository: widget.statusReminderRepository,
              availabilityRepository: widget.availabilityRepository,
              isVisible: _selectedIndex == 0,
              onSignOut: widget.onSignOut,
              onTabSelected: _selectTab,
            ),
            NavigationScreen(
              requestedAllocation: _requestedAllocation,
              refreshRevision: _paymentRevision,
              paymentSessionIds:
                  _payments?.pending
                      .map((charge) => charge.sessionId)
                      .toSet() ??
                  const {},
              onPaymentSelected: (sessionId) {
                final charge = _payments?.pending
                    .where((charge) => charge.sessionId == sessionId)
                    .firstOrNull;
                if (charge != null) {
                  unawaited(_openPayments(chargeId: charge.id));
                }
              },
              onParkingConfirmed: () => setState(() => _parkingRevision++),
              routeRepository: widget.routeRepository,
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
