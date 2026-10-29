import '../data/repositories/history_repository.dart';
import '../data/repositories/status_reminder_repository.dart';
import '../data/repositories/payment_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../data/repositories/assigned_route_repository.dart';
import '../data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/active_session_repository.dart';
import '../features/auth/auth_gate.dart';
import '../features/auth/email_verification_controller.dart';
import '../features/auth/password_recovery_controller.dart';
import '../features/auth/widgets/auth_layout.dart';
import '../data/services/password_change.dart';

import 'app_config.dart';
import 'app_theme.dart';

class VisionParkApp extends StatelessWidget {
  const VisionParkApp({
    this.repository,
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
    this.startupError,
    this.initialRoute,
    super.key,
  });

  final AuthRepository? repository;
  final EmailVerificationController? emailVerification;
  final PasswordRecoveryController? passwordRecovery;
  final PasswordChangeService? passwordChange;
  final ActiveSessionRepository? activeSessionRepository;
  final StatusReminderRepository? statusReminderRepository;
  final AvailabilityRepository? availabilityRepository;
  final AssignedRouteRepository? routeRepository;
  final VehicleRepository? vehicleRepository;
  final HistoryRepository? historyRepository;
  final PaymentRepository? paymentRepository;
  final String? startupError;
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Keep cards rigid when dragging beyond the start or end of a page.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        overscroll: false,
        physics: const ClampingScrollPhysics(),
      ),
      initialRoute: initialRoute,
      // Generate a single guarded route even for a platform-provided deep link.
      onGenerateInitialRoutes: (route) => [_route(route)],
      onGenerateRoute: (settings) => _route(settings.name ?? '/'),
    );
  }

  Route<void> _route(String name) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => repository == null
        ? AuthLayout(
            title: 'Authentication Unavailable',
            description: startupError ?? 'Configure SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and FASTAPI_BASE_URL, then restart the app.',
            child: const SizedBox.shrink(),
          )
        : AuthGate(
            repository: repository!,
            emailVerification: emailVerification,
            passwordRecovery: passwordRecovery,
            passwordChange: passwordChange,
            activeSessionRepository: activeSessionRepository,
            statusReminderRepository: statusReminderRepository,
            availabilityRepository: availabilityRepository,
            routeRepository: routeRepository,
            vehicleRepository: vehicleRepository,
            historyRepository: historyRepository,
            paymentRepository: paymentRepository,
            startWithRegistration: name == '/register',
          ),
  );
}
