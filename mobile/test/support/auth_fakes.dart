import 'dart:async';

import 'package:visionpark_mobile/data/repositories/auth_repository.dart';

const approvedDriver = AuthProfile(
  id: 'driver-id',
  role: 'driver',
  approvalStatus: 'approved',
  isActive: true,
  tenantId: 'company-id',
);

class FakeAuthRepository implements AuthRepository {
  @override
  bool hasSession = false;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => events.stream;
  AuthProfile currentProfile = approvedDriver;
  AuthFailure? loginFailure;
  AuthFailure? profileFailure;
  AuthFailure? companiesFailure;
  AuthFailure? registrationFailure;
  int profileCalls = 0;
  int signOutCalls = 0;
  String? signedInEmail;
  Map<String, String>? registration;
  Map<String, String>? completion;
  Completer<AuthProfile>? profileResult;

  @override
  Future<void> signIn(String email, String password) async {
    if (loginFailure != null) throw loginFailure!;
    signedInEmail = email;
    hasSession = true;
    events.add(null);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    hasSession = false;
    events.add(null);
  }

  @override
  Future<AuthProfile> profile() async {
    profileCalls++;
    if (profileFailure != null) throw profileFailure!;
    return profileResult == null ? currentProfile : await profileResult!.future;
  }

  @override
  Future<List<AuthCompany>> companies() async {
    if (companiesFailure != null) throw companiesFailure!;
    return const [
      AuthCompany('company-id', 'Company From Backend'),
      AuthCompany('company-2', 'Second Company'),
    ];
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
  }) async {
    if (registrationFailure != null) throw registrationFailure!;
    registration = {
      'full_name': name,
      'email': email,
      'password': password,
      'tenant_id': companyId,
    };
  }

  @override
  Future<void> complete({
    required String name,
    required String companyId,
  }) async {
    completion = {'full_name': name, 'tenant_id': companyId};
    profileFailure = null;
    currentProfile = const AuthProfile(
      id: 'driver-id',
      role: 'driver',
      approvalStatus: 'pending',
      isActive: false,
    );
  }
}

class FakeIdentity implements AuthIdentity {
  @override
  String? userId = 'driver-id';
  @override
  Stream<void> get changes => const Stream.empty();
  bool? refreshed;
  String? email;
  @override
  Future<String> accessToken({bool refresh = false}) async {
    refreshed = refresh;
    return refresh ? 'refreshed-token' : 'test-token';
  }

  @override
  Future<void> signIn(String email, String password) async {
    this.email = email;
    userId = 'driver-id';
  }

  @override
  Future<void> signOut() async {
    userId = null;
  }
}
