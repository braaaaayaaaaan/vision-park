import '../../data/repositories/history_repository.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../data/repositories/assigned_route_repository.dart';
import '../../data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/active_session_repository.dart';
import 'auth_controller.dart';
import 'login_screen.dart';
import 'registration_screen.dart';
import 'widgets/auth_layout.dart';

/// Only this gate opens the driver shell. Named routes cannot bypass it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.repository,
    this.startWithRegistration = false,
    this.activeSessionRepository,
    this.availabilityRepository,
    this.routeRepository,
    this.vehicleRepository,
    this.historyRepository,
    super.key,
  });
  final AuthRepository repository;
  final ActiveSessionRepository? activeSessionRepository;
  final AvailabilityRepository? availabilityRepository;
  final AssignedRouteRepository? routeRepository;
  final VehicleRepository? vehicleRepository;
  final HistoryRepository? historyRepository;
  final bool startWithRegistration;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final AuthController _controller;
  late bool _registering;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _registering = widget.startWithRegistration;
    WidgetsBinding.instance.addObserver(this);
    _controller = AuthController(widget.repository)..refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.repository.hasSession) {
      _controller.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      switch (_controller.status) {
        case AuthStatus.loading:
          return const AuthLayout(
            title: 'Checking Account',
            description: 'Please wait while we verify your account.',
            child: LinearProgressIndicator(),
          );
        case AuthStatus.approved:
          return AppShell(
            onSignOut: _controller.signOut,
            activeSessionRepository: widget.activeSessionRepository,
            availabilityRepository: widget.availabilityRepository,
            routeRepository: widget.routeRepository,
            vehicleRepository: widget.vehicleRepository,
            historyRepository: widget.historyRepository,
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
                onRegistered: () => setState(() {
                  _registering = false;
                  _notice = 'Check your email and confirm it if required, then sign in. You may be asked to enter your name and company again to complete registration. Existing users should sign in.';
                }),
              ),
            );
          }
          return LoginScreen(
            message: _controller.message ?? _notice,
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
            onRegistered: () {},
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
