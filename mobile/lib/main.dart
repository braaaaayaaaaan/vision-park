import 'data/repositories/history_repository.dart';
import 'data/repositories/vehicle_repository.dart';
import 'data/repositories/assigned_route_repository.dart';
import 'data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/auth_config.dart';
import 'app/vision_park_app.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/active_session_repository.dart';
import 'data/services/email_verification.dart';
import 'features/auth/email_verification_controller.dart';
import 'data/services/password_recovery.dart';
import 'features/auth/password_recovery_controller.dart';
import 'data/services/password_change.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AuthConfig.environment();
  if (!config.isValid) {
    runApp(const VisionParkApp());
    return;
  }
  try {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.publicKey,
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    final repository = RemoteAuthRepository(
      identity: SupabaseIdentity(Supabase.instance.client),
      baseUrl: config.apiBase,
      httpClient: http.Client(),
    );
    runApp(
      VisionParkApp(
        repository: repository,
        passwordChange: SupabasePasswordChangeService(
          Supabase.instance.client,
          () => SupabaseClient(
            config.supabaseUrl,
            config.publicKey,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ),
        passwordRecovery: PasswordRecoveryController(
          service: SupabasePasswordRecoveryService.create(
            url: config.supabaseUrl,
            publicKey: config.publicKey,
          ),
        ),
        emailVerification: EmailVerificationController(
          platform: AndroidVerificationPlatform(),
          verifier: SupabaseEmailVerifier(Supabase.instance.client),
        ),
        activeSessionRepository: RemoteActiveSessionRepository(repository),
        availabilityRepository: RemoteAvailabilityRepository(repository),
        routeRepository: RemoteAssignedRouteRepository(repository),
        vehicleRepository: RemoteVehicleRepository(repository),
        historyRepository: RemoteHistoryRepository(repository),
      ),
    );
  } catch (_) {
    runApp(
      const VisionParkApp(
        startupError: 'Authentication could not start. Check configuration and connectivity, then restart the app.',
      ),
    );
  }
}
