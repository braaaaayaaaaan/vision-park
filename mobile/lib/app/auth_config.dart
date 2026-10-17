import 'dart:convert';

class AuthConfig {
  const AuthConfig({
    required this.supabaseUrl,
    required this.publicKey,
    required this.apiUrl,
  });
  const AuthConfig.environment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      publicKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      apiUrl = const String.fromEnvironment('FASTAPI_BASE_URL');
  final String supabaseUrl;
  final String publicKey;
  final String apiUrl;

  bool get isValid {
    final supabase = Uri.tryParse(supabaseUrl);
    final api = Uri.tryParse(apiUrl);
    if (supabase == null ||
        supabase.scheme != 'https' ||
        supabase.host.isEmpty ||
        (supabase.path.isNotEmpty && supabase.path != '/') ||
        supabase.userInfo.isNotEmpty ||
        supabase.hasQuery ||
        supabase.hasFragment ||
        api == null ||
        !['http', 'https'].contains(api.scheme) ||
        api.host.isEmpty ||
        api.userInfo.isNotEmpty ||
        api.hasQuery ||
        api.hasFragment) {
      return false;
    }
    if (publicKey.startsWith('sb_publishable_')) return true;
    // Classification of a configured public API key only, never JWT identity verification.
    try {
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(publicKey.split('.')[1])),
        ),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  Uri get apiBase => Uri.parse(apiUrl.endsWith('/') ? apiUrl : '$apiUrl/');
}
