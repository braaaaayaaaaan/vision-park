import 'dart:async';

import '../../data/repositories/history_repository.dart';
import '../../data/repositories/status_reminder_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/services/payment_operations.dart';
import '../payments/payments_controller.dart';
import '../payments/payments_screen.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../data/repositories/assigned_route_repository.dart';
import '../../data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../home/allocation_notifications.dart';
import '../../app/app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/active_session_repository.dart';
import 'auth_controller.dart';
import 'email_verification_controller.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';
import 'password_recovery_controller.dart';
import 'password_recovery_screen.dart';
import 'registration_screen.dart';
import 'widgets/auth_layout.dart';
import '../../data/services/password_change.dart';
import 'mfa_controller.dart';
import 'mfa_screen.dart';

/// Only this gate opens the driver shell. Named routes cannot bypass it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.repository,
    this.startWithRegistration = false,
    this.emailVerification,
    this.passwordRecovery,
    this.passwordChange,
    this.activeSessionRepository,
    this.statusReminderRepository,
    this.availabilityRepository,
    this.routeRepository,
    this.vehicleRepository,
    this.historyRepository,
    this.paymentRepository,
    super.key,
  });
  final AuthRepository repository;
  final ActiveSessionRepository? activeSessionRepository;
  final StatusReminderRepository? statusReminderRepository;
  final AvailabilityRepository? availabilityRepository;
  final AssignedRouteRepository? routeRepository;
  final VehicleRepository? vehicleRepository;
  final HistoryRepository? historyRepository;
  final PaymentRepository? paymentRepository;
  final bool startWithRegistration;
  final EmailVerificationController? emailVerification;
  final PasswordRecoveryController? passwordRecovery;
  final PasswordChangeService? passwordChange;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final AuthController _controller;
  late bool _registering;
  String? _notice;
  late final EmailVerificationController _verification;
  late final PasswordRecoveryController _recovery;
  Timer? _verifiedTimer;
  bool _advancing = false;
  bool _leavingRecovery = false;
  PaymentsController? _payments;
  AllocationNotifications? _allocations;
  String? _allocationOwner;
  MfaController? _mfa;
  String? _mfaOwner;

  MfaController? _driverMfa() {
    final service = widget.repository.mfa;
    final owner = _controller.profile?.id;
    if (service == null || owner == null) return null;
    if (_mfaOwner != owner || _mfa == null) {
      _mfa?.dispose();
      _mfaOwner = owner;
      _mfa = MfaController(service)..load();
    }
    return _mfa;
  }

  AllocationNotifications _driverAllocations() {
    final owner = _controller.profile!.id;
    if (_allocationOwner != owner || _allocations == null) {
      _allocationOwner = owner;
      _allocations = AllocationNotifications();
    }
    return _allocations!;
  }

  void _allocationAuthChanged() {
    if (_controller.status == AuthStatus.mfa ||
        _controller.status == AuthStatus.signedOut) {
      // Close a pushed settlement screen as well as the shell underneath it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (_controller.status == AuthStatus.mfa ||
                _controller.status == AuthStatus.signedOut)) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
    if (!widget.repository.hasSession ||
        _controller.status == AuthStatus.signedOut ||
        _controller.status == AuthStatus.mfa ||
        _controller.status == AuthStatus.blocked) {
      _allocations = null;
      _allocationOwner = null;
    }
    if (!widget.repository.hasSession ||
        _controller.status == AuthStatus.signedOut ||
        _controller.status == AuthStatus.approved) {
      _mfa?.dispose();
      _mfa = null;
      _mfaOwner = null;
    }
  }

  PaymentsController? _driverPayments() {
    final repository = widget.paymentRepository;
    final profile = _controller.profile;
    if (repository == null ||
        profile?.role != 'driver' ||
        profile?.approvalStatus != 'approved' ||
        profile?.mfaVerified != true ||
        repository.ownerId != profile?.id) {
      return null;
    }
    if (_payments?.owner != profile!.id) {
      _payments?.dispose();
      _payments = PaymentsController(
        repository,
        PreferencesPaymentOperations(),
      );
    }
    return _payments;
  }

  @override
  void initState() {
    super.initState();
    _registering = widget.startWithRegistration;
    WidgetsBinding.instance.addObserver(this);
    _controller = AuthController(widget.repository)..refresh();
    _controller.addListener(_allocationAuthChanged);
    _verification = widget.emailVerification ?? EmailVerificationController();
    _recovery = widget.passwordRecovery ?? PasswordRecoveryController();
    _verification.onRecoveryLink = (link) {
      _verifiedTimer?.cancel();
      _verifiedTimer = null;
      return _recovery.handleLink(
        link,
        hasApplicationSession: widget.repository.hasSession,
      );
    };
    _verification.addListener(_onVerificationChanged);
    unawaited(
      _verification.initialize(hasSession: widget.repository.hasSession),
    );
  }

  void _onVerificationChanged() {
    if (_verification.stage != VerificationStage.verified) {
      _verifiedTimer?.cancel();
      _verifiedTimer = null;
    }
    if (_verification.stage == VerificationStage.verified &&
        _verification.callbackHasSession &&
        _verifiedTimer == null) {
      _verifiedTimer = Timer(
        const Duration(seconds: 2),
        _continueAfterVerification,
      );
    }
  }

  void _continueAfterVerification() {
    if (!mounted || _advancing) return;
    _advancing = true;
    _verifiedTimer?.cancel();
    _verifiedTimer = null;
    _registering = false;
    _verification.continueToAccount();
    unawaited(_controller.refresh().whenComplete(() => _advancing = false));
  }

  void _signInAfterOtherDevice() {
    _verifiedTimer?.cancel();
    _verifiedTimer = null;
    _registering = false;
    _notice = 'Sign in to securely check email confirmation and administrator approval.';
    unawaited(_verification.leave());
    unawaited(_controller.refresh());
  }

  void _leaveVerification() {
    _verifiedTimer?.cancel();
    _verifiedTimer = null;
    _registering = false;
    unawaited(_verification.leave());
  }

  Future<void> _leaveRecovery() async {
    if (_recovery.busy || _leavingRecovery) return;
    _leavingRecovery = true;
    try {
      _registering = false;
      _notice = _recovery.stage == RecoveryStage.updated
          ? 'Password updated. Sign in with your new password.'
          : null;
      await _verification.leave();
      // A callback received while signed in is rejected without replacing that
      // account. Returning from this flow explicitly returns to sign-in.
      if (widget.repository.hasSession) await _controller.signOut();
      await _recovery.leave();
    } finally {
      _leavingRecovery = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.repository.hasSession) {
      _controller.refresh();
    }
  }

  @override
  void dispose() {
    _verifiedTimer?.cancel();
    _verification.removeListener(_onVerificationChanged);
    _verification.onRecoveryLink = null;
    if (widget.emailVerification == null) _verification.dispose();
    if (widget.passwordRecovery == null) _recovery.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_allocationAuthChanged);
    _controller.dispose();
    _payments?.dispose();
    _mfa?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_controller, _verification, _recovery]),
    builder: (context, _) {
      if (_recovery.stage != RecoveryStage.idle) {
        return PasswordRecoveryScreen(
          controller: _recovery,
          hasApplicationSession: widget.repository.hasSession,
          onReturnToSignIn: _leaveRecovery,
        );
      }
      if (_verification.stage != VerificationStage.idle) {
        return EmailVerificationScreen(
          controller: _verification,
          hasSession: widget.repository.hasSession,
          onContinue: _continueAfterVerification,
          onSignInElsewhere: _signInAfterOtherDevice,
          onLeave: _leaveVerification,
        );
      }
      switch (_controller.status) {
        case AuthStatus.mfa:
          final mfa = _driverMfa();
          if (mfa != null) {
            return MfaScreen(
              controller: mfa,
              onComplete: _controller.refresh,
              onSignOut: _controller.signOut,
            );
          }
          return AuthLayout(
            title: 'Authenticator Unavailable',
            description:
                'Restart the application to check authenticator configuration.',
            child: OutlinedButton(
              onPressed: _controller.signOut,
              child: const Text('Sign Out'),
            ),
          );
        case AuthStatus.loading:
          return const AuthLayout(
            title: 'Checking Account',
            description: 'Please wait while we verify your account.',
            child: LinearProgressIndicator(),
          );
        case AuthStatus.approved:
          return AppShell(
            key: ValueKey(_controller.profile!.id),
            allocationNotifications: _driverAllocations(),
            passwordChange: widget.passwordChange,
            profile: _controller.profile,
            onSignOut: _controller.signOut,
            activeSessionRepository: widget.activeSessionRepository,
            statusReminderRepository: widget.statusReminderRepository,
            availabilityRepository: widget.availabilityRepository,
            routeRepository: widget.routeRepository,
            vehicleRepository: widget.vehicleRepository,
            historyRepository: widget.historyRepository,
            paymentRepository: widget.paymentRepository,
            paymentsController: _driverPayments(),
          );
        case AuthStatus.signedOut:
          if (_registering) {
            return PopScope<void>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) setState(() => _registering = false);
              },
              child: RegistrationScreen(
                repository: widget.repository,
                onBack: () => setState(() => _registering = false),
                onRegistered: (email) => setState(() {
                  _registering = false;
                  unawaited(_verification.waitForEmail(email));
                }),
              ),
            );
          }
          return LoginScreen(
            initialEmail: _recovery.email.isNotEmpty
                ? _recovery.email
                : _verification.email,
            onForgotPassword: (email) {
              _notice = null;
              _recovery.showRequest(email);
            },
            message: _controller.message ?? _notice,
            messageIsError: _controller.message != null,
            onLogin: (email, password) {
              _notice = null;
              return _controller.signIn(email, password);
            },
            onRegister: () => setState(() {
              _registering = true;
              _notice = null;
            }),
          );
        case AuthStatus.completion:
          return RegistrationScreen(
            key: const ValueKey('completion'),
            repository: widget.repository,
            completion: true,
            message: _controller.message,
            onBack: _controller.signOut,
            onRegistered: (_) {},
            onComplete: _controller.complete,
          );
        case AuthStatus.blocked:
        case AuthStatus.error:
          return AuthLayout(
            title: _controller.status == AuthStatus.blocked
                ? 'Account Status'
                : 'Unable to Verify Account',
            description: _controller.message ?? 'Please try again.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_controller.status == AuthStatus.blocked &&
                    _controller.profile?.role == 'driver' &&
                    _controller.profile?.approvalStatus == 'approved' &&
                    _controller.profile?.mfaVerified == true &&
                    widget.paymentRepository != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Wallet and Payments'),
                    onPressed: () async {
                      final payments = _driverPayments();
                      if (payments == null) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PaymentsScreen(controller: payments),
                        ),
                      );
                    },
                  ),
                FilledButton(
                  onPressed: _controller.refresh,
                  child: const Text('Check Again'),
                ),
                const SizedBox(height: AppSpacing.small),
                OutlinedButton(
                  onPressed: _controller.signOut,
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
      }
    },
  );
}
