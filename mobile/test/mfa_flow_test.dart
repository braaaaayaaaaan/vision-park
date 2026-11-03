import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visionpark_mobile/app/vision_park_app.dart';
import 'package:visionpark_mobile/data/repositories/auth_repository.dart';
import 'package:visionpark_mobile/data/services/mfa.dart';
import 'package:visionpark_mobile/data/services/password_change.dart';
import 'package:visionpark_mobile/data/services/password_recovery.dart';
import 'package:visionpark_mobile/features/auth/auth_controller.dart';
import 'package:visionpark_mobile/features/auth/mfa_controller.dart';
import 'package:visionpark_mobile/features/auth/password_recovery_controller.dart';
import 'package:visionpark_mobile/features/auth/password_recovery_screen.dart';

const userId = '11111111-1111-4111-8111-111111111111';
const sessionId = '22222222-2222-4222-8222-222222222222';
const factorId = '33333333-3333-4333-8333-333333333333';
const challengeId = '44444444-4444-4444-8444-444444444444';
const fixtureQrSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 2"><rect width="1" height="1" fill="black"/></svg>';

class MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

/// A native Auth HTTP contract fixture, not a TOTP implementation. No test
/// connects to Supabase; accepting/rejecting codes represents Auth's response.
class NativeAuthFixture {
  bool verifiedFactor = false;
  bool pendingFactor = false;
  bool rejectCode = false;
  bool expiredCode = false;
  bool rejectPassword = false;
  bool losePasswordResponse = false;
  String session = sessionId;
  int enrollments = 0, deletions = 0, refreshes = 0, updates = 0;
  String? updateAal;

  Map<String, dynamic> get user => {
    'id': userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'driver@example.invalid',
    'email_confirmed_at': '2026-01-01T00:00:00Z',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'is_anonymous': false,
    'factors': [
      if (verifiedFactor || pendingFactor)
        {
          'id': factorId,
          'factor_type': 'totp',
          'status': verifiedFactor ? 'verified' : 'unverified',
          'friendly_name': 'Test Authenticator',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
    ],
  };

  String token(String aal) {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${encode({'alg': 'ES256'})}.${encode({'sub': userId, 'session_id': session, 'aal': aal, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000})}.offline-signature';
  }

  Map<String, dynamic> credentials(String aal) => {
    'access_token': token(aal),
    'refresh_token': 'offline-refresh-$aal',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': user,
  };

  Map<String, dynamic> claims(String authorization) => jsonDecode(
    utf8.decode(
      base64Url.decode(base64Url.normalize(authorization.split('.')[1])),
    ),
  ) as Map<String, dynamic>;

  Future<http.Response> handle(http.Request request) async {
    expect(request.url.host, 'mfa.example.invalid');
    final path = request.url.path;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    http.Response json(Object data, [int status = 200]) => http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (path == '/auth/v1/token') {
      if (request.url.queryParameters['grant_type'] == 'pkce' &&
          (body['code_verifier'] == null || body['code_verifier'] == '')) {
        return json({'code': 'bad_code_verifier', 'msg': 'Rejected'}, 400);
      }
      if (request.url.queryParameters['grant_type'] == 'refresh_token') {
        refreshes++;
      }
      if (rejectPassword) {
        return json({'code': 'invalid_credentials', 'msg': 'Rejected'}, 400);
      }
      return json(credentials('aal1'));
    }
    if (path == '/auth/v1/user' && request.method == 'GET') return json(user);
    if (path == '/auth/v1/user' && request.method == 'PUT') {
      updates++;
      updateAal = claims(request.headers['authorization']!)['aal'] as String;
      if (verifiedFactor && updateAal != 'aal2') {
        return json({'code': 'insufficient_aal', 'msg': 'AAL2 required'}, 401);
      }
      if (losePasswordResponse) {
        throw http.ClientException('Simulated lost response');
      }
      return json(user);
    }
    if (path == '/auth/v1/recover') return json({});
    if (path == '/auth/v1/logout') return http.Response('', 204);
    if (path == '/auth/v1/factors' && request.method == 'POST') {
      enrollments++;
      pendingFactor = true;
      return json({
        'id': factorId,
        'type': 'totp',
        'totp': {
          'secret': 'JBSWY3DPEHPK3PXP',
          'qr_code': fixtureQrSvg,
          'uri': 'otpauth://totp/fixture',
        },
      });
    }
    if (path == '/auth/v1/factors/$factorId' && request.method == 'DELETE') {
      expect(verifiedFactor, false);
      deletions++;
      pendingFactor = false;
      return json({'id': factorId});
    }
    if (path.endsWith('/challenge')) {
      return json({
        'id': challengeId,
        'type': 'totp',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
      });
    }
    if (path.endsWith('/verify')) {
      expect(body['challenge_id'], challengeId);
      if (rejectCode || expiredCode) {
        return json({
          'code': expiredCode
              ? 'mfa_challenge_expired'
              : 'mfa_verification_failed',
          'msg': 'SENSITIVE_UPSTREAM_SENTINEL',
        }, 422);
      }
      verifiedFactor = true;
      pendingFactor = false;
      return json(credentials('aal2'));
    }
    throw StateError('Unexpected offline Auth request');
  }

  SupabaseClient client({MemoryStorage? storage}) => SupabaseClient(
    'https://mfa.example.invalid',
    'sb_publishable_offline_fixture',
    httpClient: MockClient(handle),
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.pkce,
      pkceAsyncStorage: storage,
    ),
  );
}

class FakeMfa implements MfaService {
  bool ready = false;
  bool enrolled = true;
  bool pending = false;
  String? qrCode = 'data:image/svg+xml;utf-8,$fixtureQrSvg';
  int reads = 0, enrollments = 0;
  @override
  Future<MfaSnapshot> inspect() async {
    reads++;
    return MfaSnapshot(
      ready: ready,
      factors: [
        if (enrolled || pending)
          MfaFactor(factorId, 'Test', verified: enrolled),
      ],
    );
  }

  @override
  Future<MfaEnrollment> enroll({String? replaceUnverifiedId}) async {
    enrollments++;
    pending = true;
    return MfaEnrollment(factorId, 'JBSWY3DPEHPK3PXP', qrCode: qrCode);
  }

  @override
  Future<void> verify(String factorId, String code) async {
    ready = true;
    enrolled = true;
    pending = false;
  }
}

class FakeRepository implements AuthRepository {
  bool signedIn = true, ready = false;
  String approval = 'approved';
  final events = StreamController<void>.broadcast();
  @override
  final FakeMfa mfa = FakeMfa();
  @override
  bool get hasSession => signedIn;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<AuthProfile> profile() async => AuthProfile(
    id: userId,
    role: 'driver',
    approvalStatus: approval,
    isActive: true,
    tenantId: sessionId,
    mfaVerified: ready,
  );
  @override
  Future<void> signIn(String email, String password) async {
    signedIn = true;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    events.add(null);
  }

  @override
  Future<List<AuthCompany>> companies() async => [];
  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
  }) async {}
  @override
  Future<void> complete({
    required String name,
    required String companyId,
  }) async {}
}

class FakeRecovery implements PasswordRecoveryService {
  @override
  final mfa = FakeMfa()..enrolled = false;
  Uri? received;
  @override
  Future<RecoveryRequestState> requestState() async =>
      const RecoveryRequestState();
  @override
  Future<void> request(String email) async {}
  @override
  Future<String> establish(Uri callback) async {
    received = callback;
    return 'driver@example.invalid';
  }

  @override
  Future<void> confirmMfa() async {}
  @override
  Future<void> startOver() async {}
  @override
  Future<void> update(String password) async {}
  @override
  Future<void> end() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native QR SVG supports raw, UTF-8 and base64 data without network loading',
    () {
      for (final data in [
        fixtureQrSvg,
        'data:image/svg+xml;utf-8,$fixtureQrSvg',
        'data:image/svg+xml,${Uri.encodeComponent(fixtureQrSvg)}',
        'data:image/svg+xml;base64,${base64Encode(utf8.encode(fixtureQrSvg))}',
      ]) {
        expect(
          MfaEnrollment(factorId, 'fixture-key', qrCode: data).qrSvg,
          fixtureQrSvg,
        );
      }
      for (final data in [
        'https://external.invalid/qr',
        'data:text/html,<svg/>',
        'data:image/svg+xml;base64,%%%',
      ]) {
        expect(
          MfaEnrollment(factorId, 'fixture-key', qrCode: data).qrSvg,
          isNull,
        );
      }
    },
  );

  for (final showQr in [true, false]) {
    testWidgets(
      showQr
          ? 'enrollment displays the native QR alongside the manual setup key'
          : 'manual setup remains available when native QR metadata is absent',
      (tester) async {
        final repository = FakeRepository();
        repository.mfa.enrolled = false;
        if (!showQr) repository.mfa.qrCode = null;
        await tester.pumpWidget(VisionParkApp(repository: repository));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mfa-enrollment-qr')), findsNothing);
        await tester.tap(find.text('Begin Setup'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mfa-enrollment-qr')),
          showQr ? findsOneWidget : findsNothing,
        );
        expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
        expect(find.text('Verify and Continue'), findsOneWidget);
        expect(repository.mfa.enrollments, 1);
        await tester.pumpWidget(const SizedBox());
        await repository.events.close();
      },
    );
  }

  test('native SDK enrollment and verification establish aal2 without factor-list refresh loops', () async {
    final fixture = NativeAuthFixture();
    final client = fixture.client();
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'driver@example.invalid',
      password: 'fixture-password',
    );
    final service = SupabaseMfaService(client);
    expect((await service.inspect()).ready, false);
    final enrolled = await service.enroll();
    expect(enrolled.id, factorId);
    expect(enrolled.qrSvg, fixtureQrSvg);
    await expectLater(service.enroll(), throwsA(isA<AuthFailure>()));
    expect(fixture.enrollments, 1);
    await service.verify(factorId, '123456');
    expect(
      client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
      AuthenticatorAssuranceLevels.aal2,
    );
    expect((await service.inspect()).ready, true);
    expect(fixture.refreshes, 0);
  });

  for (final expired in [false, true]) {
    test(
      'native ${expired ? 'expired' : 'incorrect'} code errors keep aal1 and hide upstream details',
      () async {
        final fixture = NativeAuthFixture()
          ..verifiedFactor = true
          ..rejectCode = !expired
          ..expiredCode = expired;
        final client = fixture.client();
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'driver@example.invalid',
          password: 'fixture-password',
        );
        await expectLater(
          SupabaseMfaService(client).verify(factorId, '000000'),
          throwsA(
            isA<AuthFailure>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('SENSITIVE_UPSTREAM_SENTINEL')),
            ),
          ),
        );
        expect(
          client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
          AuthenticatorAssuranceLevels.aal1,
        );
      },
    );
  }

  test('interrupted enrollment restarts only an unverified factor and never removes a verified factor', () async {
    final fixture = NativeAuthFixture()..pendingFactor = true;
    final client = fixture.client();
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'driver@example.invalid',
      password: 'fixture-password',
    );
    final service = SupabaseMfaService(client);
    await service.enroll(replaceUnverifiedId: factorId);
    expect(fixture.deletions, 1);
    fixture.verifiedFactor = true;
    await expectLater(
      service.enroll(replaceUnverifiedId: factorId),
      throwsA(isA<AuthFailure>()),
    );
    expect(fixture.deletions, 1);
  });

  test('password change checks current password separately but updates through main aal2 session', () async {
    final fixture = NativeAuthFixture()..verifiedFactor = true;
    final client = fixture.client();
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'driver@example.invalid',
      password: 'fixture-password',
    );
    await SupabaseMfaService(client).verify(factorId, '123456');
    final service = SupabasePasswordChangeService(client, fixture.client);
    await service.change('OldPassword1!', 'NewPassword2!');
    expect(fixture.updates, 1);
    expect(fixture.updateAal, 'aal2');
    expect(client.auth.currentSession, isNotNull);
  });

  test('wrong current password cannot trigger a password update', () async {
    final fixture = NativeAuthFixture()..verifiedFactor = true;
    final client = fixture.client();
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'driver@example.invalid',
      password: 'fixture-password',
    );
    await SupabaseMfaService(client).verify(factorId, '123456');
    fixture.rejectPassword = true;
    await expectLater(
      SupabasePasswordChangeService(
        client,
        fixture.client,
      ).change('wrong', 'NewPassword2!'),
      throwsA(isA<AuthFailure>()),
    );
    expect(fixture.updates, 0);
  });

  test('pasted email links redeem only the configured Auth URL and still use native PKCE', () async {
    final fixture = NativeAuthFixture();
    final storage = MemoryStorage();
    var requests = 0;
    final service = SupabasePasswordRecoveryService(
      fixture.client(storage: storage),
      requestStore: RecoveryRequestStore(storage, 'request'),
      emailLinkEndpoint: Uri.parse(
        'https://mfa.example.invalid/auth/v1/verify',
      ),
      linkClient: MockClient((request) async {
        requests++;
        expect(request.followRedirects, false);
        expect(request.url.host, 'mfa.example.invalid');
        return http.Response(
          '',
          303,
          headers: {
            'location': 'visionpark://auth/reset-password?code=offline-code',
          },
        );
      }),
      diagnostic: (_) {},
    );
    addTearDown(service.dispose);
    await service.request('driver@example.invalid');
    for (final link in [
      'https://evil.invalid/auth/v1/verify?token=secret&type=recovery',
      'https://mfa.example.invalid/auth/v1/verify?token=secret&type=signup',
      'https://mfa.example.invalid/auth/v1/verify?token=secret&type=recovery&redirect_to=https%3A%2F%2Fevil.invalid',
      'https://mfa.example.invalid/auth/v1/verify?token=secret&type=recovery&type=signup',
    ]) {
      await expectLater(
        service.establish(Uri.parse(link)),
        throwsA(isA<AuthFailure>()),
      );
    }
    expect(requests, 0);
    expect(
      await service.establish(
        Uri.parse(
          'https://mfa.example.invalid/auth/v1/verify?token=secret&type=recovery&redirect_to=visionpark%3A%2F%2Fauth%2Freset-password',
        ),
      ),
      'driver@example.invalid',
    );
    expect(requests, 1);
    expect(fixture.updates, 0);
  });

  test('a pasted link cannot replace the requesting device PKCE verifier or follow a foreign redirect', () async {
    final fixture = NativeAuthFixture();
    final storage = MemoryStorage();
    var foreignRedirect = false;
    final service = SupabasePasswordRecoveryService(
      fixture.client(storage: storage),
      requestStore: RecoveryRequestStore(storage, 'request'),
      emailLinkEndpoint: Uri.parse(
        'https://mfa.example.invalid/auth/v1/verify',
      ),
      linkClient: MockClient(
        (_) async => http.Response(
          '',
          303,
          headers: {
            'location': foreignRedirect
                ? 'https://evil.invalid/?code=secret'
                : 'visionpark://auth/reset-password?code=offline-code',
          },
        ),
      ),
      diagnostic: (_) {},
    );
    addTearDown(service.dispose);
    final link = Uri.parse(
      'https://mfa.example.invalid/auth/v1/verify?token=secret&type=recovery',
    );
    await expectLater(service.establish(link), throwsA(isA<AuthFailure>()));
    await service.request('driver@example.invalid');
    foreignRedirect = true;
    await expectLater(service.establish(link), throwsA(isA<AuthFailure>()));
    expect(fixture.updates, 0);
    expect(service.client.auth.currentSession, isNull);
  });

  testWidgets(
    'recovery screen accepts a copied email link on the requesting emulator',
    (tester) async {
      final service = FakeRecovery();
      final controller = PasswordRecoveryController(service: service);
      await controller.request('driver@example.invalid');
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => PasswordRecoveryScreen(
              controller: controller,
              onReturnToSignIn: () async {},
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://mfa.example.invalid/auth/v1/verify?token=secret&type=recovery',
      );
      await tester.ensureVisible(find.text('Continue with Reset Link'));
      await tester.tap(find.text('Continue with Reset Link'));
      await tester.pumpAndSettle();
      expect(controller.stage, RecoveryStage.ready);
      expect(find.text('Create New Password'), findsOneWidget);
      expect(service.received?.queryParameters['token'], 'secret');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump();
    },
  );

  test('recovery verifies the same isolated PKCE session and never opens the application session', () async {
    final fixture = NativeAuthFixture()..verifiedFactor = true;
    final storage = MemoryStorage();
    final recoveryClient = fixture.client(storage: storage);
    final mainClient = fixture.client();
    addTearDown(mainClient.dispose);
    final service = SupabasePasswordRecoveryService(
      recoveryClient,
      requestStore: RecoveryRequestStore(storage, 'request'),
      diagnostic: (_) {},
    );
    final controller = PasswordRecoveryController(service: service);
    await controller.request('driver@example.invalid');
    await controller.handleLink(
      'visionpark://auth/reset-password?code=offline-recovery-code',
    );
    expect(controller.stage, RecoveryStage.mfa);
    expect(fixture.updates, 0);
    expect(mainClient.auth.currentSession, isNull);
    await service.mfa.verify(factorId, '123456');
    await controller.completeMfa();
    expect(controller.stage, RecoveryStage.ready);
    expect(await controller.update('NewPassword2!'), true);
    expect(fixture.updateAal, 'aal2');
    expect(mainClient.auth.currentSession, isNull);
    expect(recoveryClient.auth.currentSession, isNull);
    expect(
      storage.values.values.any((value) => value.contains('JBSWY3DPEHPK3PXP')),
      false,
    );
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'recovery cannot borrow an aal2 session with a different session identity',
    () async {
      final fixture = NativeAuthFixture()..verifiedFactor = true;
      final storage = MemoryStorage();
      final client = fixture.client(storage: storage);
      final service = SupabasePasswordRecoveryService(
        client,
        requestStore: RecoveryRequestStore(storage, 'request'),
        diagnostic: (_) {},
      );
      addTearDown(service.dispose);
      await service.request('driver@example.invalid');
      await service.establish(
        Uri.parse('visionpark://auth/reset-password?code=offline-code'),
      );
      fixture.session = challengeId;
      await client.auth.signInWithPassword(
        email: 'driver@example.invalid',
        password: 'fixture-password',
      );
      await service.mfa.verify(factorId, '123456');
      await expectLater(service.confirmMfa(), throwsA(isA<AuthFailure>()));
      expect(fixture.updates, 0);
    },
  );

  test('aal1 restoration requires MFA; aal2 restoration and logout preserve state boundaries', () async {
    final repository = FakeRepository();
    final controller = AuthController(repository);
    addTearDown(() async {
      controller.dispose();
      await repository.events.close();
    });
    await controller.refresh();
    expect(controller.status, AuthStatus.mfa);
    repository.ready = true;
    await controller.refresh();
    expect(controller.status, AuthStatus.approved);
    repository.approval = 'pending';
    await controller.refresh();
    expect(controller.status, AuthStatus.blocked);
    await controller.signOut();
    expect(controller.status, AuthStatus.signedOut);
  });

  testWidgets(
    'named routes and app restart cannot open protected UI with aal1',
    (tester) async {
      final repository = FakeRepository();
      await tester.pumpWidget(
        VisionParkApp(repository: repository, initialRoute: '/payments'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verify Your Authenticator'), findsOneWidget);
      expect(find.text('Wallet and Payments'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        VisionParkApp(repository: repository, initialRoute: '/navigation'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verify Your Authenticator'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repository.events.close();
    },
  );

  test(
    'MFA controller keeps pending setup in memory across status reads',
    () async {
      final service = FakeMfa()..enrolled = false;
      final controller = MfaController(service);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.enroll();
      final enrollment = controller.enrollment;
      await controller.load();
      expect(identical(controller.enrollment, enrollment), true);
      expect(controller.selectedFactor, factorId);
      expect(service.enrollments, 1);
      expect(await controller.verify('123456'), true);
      expect(controller.state!.ready, true);
    },
  );

  testWidgets(
    'opening an authenticator and resuming preserves unfinished enrollment without creating another factor',
    (tester) async {
      final repository = FakeRepository();
      repository.mfa.enrolled = false;
      await tester.pumpWidget(VisionParkApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin Setup'));
      await tester.pumpAndSettle();
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
      expect(repository.mfa.enrollments, 1);
      await tester.pumpWidget(const SizedBox());
      await repository.events.close();
    },
  );
}
