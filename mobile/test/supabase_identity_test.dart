import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visionpark_mobile/data/repositories/auth_repository.dart';

void main() {
  test('SDK password sign-in, access token and local signout use mocked Auth transport', () async {
    final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'ES256'})}.${encode({'sub': 'driver-id', 'exp': expires})}.test-signature';
    final requests = <String>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        expect(request.url.queryParameters['grant_type'], 'password');
        final body = jsonDecode(request.body) as Map;
        expect(body['email'], 'driver@example.com');
        expect(body['password'], 'synthetic-password');
        return http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'driver-id',
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final identity = SupabaseIdentity(client);
    await identity.signIn('driver@example.com', 'synthetic-password');
    expect(identity.userId, 'driver-id');
    expect(await identity.accessToken(), token);
    await identity.signOut();
    expect(identity.userId, isNull);
    expect(requests, ['/auth/v1/token', '/auth/v1/logout']);
  });

  for (final code in ['invalid_credentials', 'email_not_confirmed']) {
    test('SDK $code produces safe actionable message', () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'error_code': code, 'msg': 'private upstream details'}),
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseIdentity(client).signIn('driver@example.com', 'wrong'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'safe message',
            code == 'email_not_confirmed'
                ? 'Confirm your email before signing in.'
                : 'Unable to sign in. Check your email and password and try again.',
          ),
        ),
      );
    });
  }
}
