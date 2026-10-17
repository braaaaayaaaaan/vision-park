import 'package:flutter/material.dart';

import '../data/repositories/auth_repository.dart';
import '../features/auth/auth_gate.dart';
import '../features/auth/widgets/auth_layout.dart';

import 'app_config.dart';
import 'app_theme.dart';

class VisionParkApp extends StatelessWidget {
  const VisionParkApp({
    this.repository,
    this.startupError,
    this.initialRoute,
    super.key,
  });

  final AuthRepository? repository;
  final String? startupError;
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
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
            startWithRegistration: name == '/register',
          ),
  );
}
