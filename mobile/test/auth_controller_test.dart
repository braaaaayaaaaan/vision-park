import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/data/repositories/auth_repository.dart';
import 'package:visionpark_mobile/features/auth/auth_controller.dart';

import 'support/auth_fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late AuthController controller;
  setUp(() {
    repo = FakeAuthRepository();
    controller = AuthController(repo);
  });
  tearDown(() async {
    controller.dispose();
    await repo.events.close();
  });

  test(
    'login reads application profile and permits only approved active driver',
    () async {
      await controller.signIn('driver@example.com', 'password');
      expect(repo.profileCalls, 1);
      expect(controller.status, AuthStatus.approved);
    },
  );
  for (final profile in [
    const AuthProfile(
      id: 'driver-id',
      role: 'driver',
      approvalStatus: 'pending',
      isActive: false,
    ),
    const AuthProfile(
      id: 'driver-id',
      role: 'driver',
      approvalStatus: 'rejected',
      isActive: false,
    ),
    const AuthProfile(
      id: 'driver-id',
      role: 'driver',
      approvalStatus: 'approved',
      isActive: false,
      tenantId: 'company-id',
    ),
    const AuthProfile(
      id: 'driver-id',
      role: 'admin',
      approvalStatus: 'approved',
      isActive: true,
    ),
  ]) {
    test(
      'blocks ${profile.role}/${profile.approvalStatus}/${profile.isActive}',
      () async {
        repo.currentProfile = profile;
        await controller.signIn('driver@example.com', 'password');
        expect(controller.status, AuthStatus.blocked);
        expect(controller.message, profile.statusMessage);
      },
    );
  }
  test('restored session rechecks profile; signout removes access', () async {
    repo.hasSession = true;
    await controller.refresh();
    expect(controller.status, AuthStatus.approved);
    expect(repo.profileCalls, 1);
    await controller.signOut();
    expect(controller.status, AuthStatus.signedOut);
    expect(repo.hasSession, isFalse);
  });
  test('missing profile completes after sign-in and remains pending', () async {
    repo.profileFailure = const AuthFailure(
      'Complete registration',
      missingProfile: true,
    );
    await controller.signIn('driver@example.com', 'password');
    expect(controller.status, AuthStatus.completion);
    await controller.complete('Driver', 'company-id');
    expect(repo.completion, {'full_name': 'Driver', 'tenant_id': 'company-id'});
    expect(controller.status, AuthStatus.blocked);
  });
  test(
    'invalid login, profile network failure and expired session handled',
    () async {
      repo.loginFailure = const AuthFailure('Invalid credentials');
      await controller.signIn('driver@example.com', 'wrong');
      expect(controller.status, AuthStatus.signedOut);
      expect(repo.profileCalls, 0);
      repo.loginFailure = null;
      repo.profileFailure = const AuthFailure('Network unavailable');
      await controller.signIn('driver@example.com', 'password');
      expect(controller.status, AuthStatus.error);
      repo.profileFailure = const AuthFailure('Expired', expired: true);
      await controller.refresh();
      expect(controller.status, AuthStatus.signedOut);
      expect(repo.hasSession, isFalse);
    },
  );
  test('late profile response cannot undo signout', () async {
    repo.hasSession = true;
    repo.profileResult = Completer<AuthProfile>();
    final pending = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    repo.profileResult!.complete(approvedDriver);
    await pending;
    expect(controller.status, AuthStatus.signedOut);
  });
  test(
    'auth stream failures close dashboard access without crashing',
    () async {
      repo.hasSession = true;
      await controller.refresh();
      repo.events.addError(Exception('offline'));
      expect(controller.status, AuthStatus.error);
    },
  );
}
