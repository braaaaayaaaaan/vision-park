import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visionpark_mobile/app/auth_config.dart';
import 'package:visionpark_mobile/data/repositories/auth_repository.dart';

import 'support/auth_fakes.dart';

const profileJson = {
  'id': 'driver-id',
  'role': 'driver',
  'approval_status': 'approved',
  'is_active': true,
  'tenant_id': 'company-id',
};

void main() {
  late FakeIdentity identity;
  RemoteAuthRepository repository(
    Future<http.Response> Function(http.Request) handler,
  ) => RemoteAuthRepository(
    identity: identity,
    baseUrl: Uri.parse('https://api.example.test/'),
    httpClient: MockClient(handler),
  );
  setUp(() {
    identity = FakeIdentity();
  });

  test(
    'sign in uses identity SDK; me carries bearer and validates profile',
    () async {
      final repo = repository((request) async {
        expect(request.url.path, '/auth/me');
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.followRedirects, isFalse);
        return http.Response(jsonEncode(profileJson), 200);
      });
      await repo.signIn(' driver@example.com ', 'password');
      expect(identity.email, 'driver@example.com');
      expect((await repo.profile()).canEnter, isTrue);
    },
  );

  test(
    'companies and registration use exact backend contract and no bearer',
    () async {
      final repo = repository((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        if (request.method == 'GET') {
          expect(request.url.path, '/auth/companies');
          return http.Response(
            '[{"id":"actual-company-id","name":"Actual Company"}]',
            200,
          );
        }
        expect(request.url.path, '/auth/register');
        expect(jsonDecode(request.body), {
          'full_name': 'Driver',
          'email': 'd@example.com',
          'password': 'long-password',
          'tenant_id': 'actual-company-id',
        });
        return http.Response('{"status":"check_email_or_sign_in"}', 202);
      });
      final companies = await repo.companies();
      await repo.register(
        name: ' Driver ',
        email: 'd@example.com',
        password: 'long-password',
        companyId: companies.single.id,
      );
    },
  );

  test(
    'completion uses verified session and only name/requested tenant fields',
    () async {
      final repo = repository((request) async {
        expect(request.url.path, '/auth/register/complete');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body), {
          'full_name': 'Driver',
          'tenant_id': 'company-id',
        });
        return http.Response('{"status":"profile_available"}', 200);
      });
      await repo.complete(name: 'Driver', companyId: 'company-id');
    },
  );

  test('401 retries once with refreshed token', () async {
    var calls = 0;
    final repo = repository((request) async {
      if (++calls == 1) return http.Response('{}', 401);
      expect(request.headers['Authorization'], 'Bearer refreshed-token');
      return http.Response(jsonEncode(profileJson), 200);
    });
    expect((await repo.profile()).canEnter, isTrue);
    expect(calls, 2);
    expect(identity.refreshed, isTrue);
  });

  test('persistent 401 is expired; only exact missing-profile 403 allows completion', () async {
    await expectLater(
      repository((_) async => http.Response('{}', 401)).profile(),
      throwsA(isA<AuthFailure>().having((e) => e.expired, 'expired', true)),
    );
    await expectLater(
      repository(
        (_) async => http.Response(
          '{"detail":"Application profile is unavailable."}',
          403,
        ),
      ).profile(),
      throwsA(
        isA<AuthFailure>().having((e) => e.missingProfile, 'missing', true),
      ),
    );
    await expectLater(
      repository((_) async => http.Response('{"detail":"Forbidden"}', 403))
          .profile(),
      throwsA(
        isA<AuthFailure>().having((e) => e.missingProfile, 'missing', false),
      ),
    );
  });

  test('bad identity, malformed response, service and network failures fail closed', () async {
    for (final response in [
      http.Response(jsonEncode({...profileJson, 'id': 'other-user'}), 200),
      http.Response('bad json', 200),
      http.Response('private error', 503),
    ]) {
      await expectLater(
        repository((_) async => response).profile(),
        throwsA(isA<AuthFailure>()),
      );
    }
    await expectLater(
      repository((_) async => throw http.ClientException('secret details'))
          .profile(),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message.contains('secret'),
          'sanitized',
          false,
        ),
      ),
    );
  });

  test('configuration accepts public credentials and rejects privileged credentials', () {
    AuthConfig config(String key) => AuthConfig(
      supabaseUrl: 'https://project.supabase.co',
      publicKey: key,
      apiUrl: 'http://10.0.2.2:8000',
    );
    expect(config('sb_publishable_example').isValid, isTrue);
    expect(config('sb_secret_example').isValid, isFalse);
    final encoded = base64Url.encode(utf8.encode('{"role":"service_role"}'));
    expect(config('header.$encoded.signature').isValid, isFalse);
    expect(
      config('sb_publishable_example').apiBase.toString(),
      'http://10.0.2.2:8000/',
    );
    expect(const AuthConfig.environment().isValid, isFalse);
  });
}
