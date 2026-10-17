import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/auth_config.dart';
import 'app/vision_park_app.dart';
import 'data/repositories/auth_repository.dart';

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
    );
    runApp(
      VisionParkApp(
        repository: RemoteAuthRepository(
          identity: SupabaseIdentity(Supabase.instance.client),
          baseUrl: config.apiBase,
          httpClient: http.Client(),
        ),
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
