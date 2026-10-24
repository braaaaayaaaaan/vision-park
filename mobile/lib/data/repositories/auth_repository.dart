import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.expired = false,
    this.missingProfile = false,
  });
  final String message;
  final bool expired;
  final bool missingProfile;
}

class AuthCompany {
  const AuthCompany(this.id, this.name);
  final String id;
  final String name;
}

class AuthProfile {
  const AuthProfile({
    required this.id,
    required this.role,
    required this.approvalStatus,
    required this.isActive,
    this.tenantId,
    this.fullName,
    this.companyName,
  });
  final String id;
  final String role;
  final String approvalStatus;
  final bool isActive;
  final String? tenantId;
  final String? fullName;
  final String? companyName;

  bool get canEnter =>
      role == 'driver' &&
      approvalStatus == 'approved' &&
      isActive &&
      tenantId != null &&
      tenantId!.isNotEmpty;
  String get statusMessage {
    if (role != 'driver') {
      return 'This application is for driver accounts. Administrator accounts cannot access the driver dashboard.';
    }
    if (approvalStatus == 'pending') {
      return 'Your registration is awaiting administrator approval. Check again after your application has been reviewed.';
    }
    if (approvalStatus == 'rejected') {
      return 'Your registration was rejected. Contact your parking administrator for assistance.';
    }
    if (!isActive) {
      return 'Your account is inactive. Contact your parking administrator for assistance.';
    }
    return 'Your parking access could not be confirmed. Contact your parking administrator.';
  }
}

abstract interface class AuthRepository {
  bool get hasSession;
  Stream<void> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<AuthProfile> profile();
  Future<List<AuthCompany>> companies();
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
  });
  Future<void> complete({required String name, required String companyId});
}

/// Small injectable SDK boundary: HTTP/flow tests never use real Auth accounts.
abstract interface class AuthIdentity {
  String? get userId;
  Stream<void> get changes;
  Future<String> accessToken({bool refresh = false});
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseIdentity implements AuthIdentity {
  SupabaseIdentity(this.client);
  final SupabaseClient client;

  @override
  String? get userId => client.auth.currentSession?.user.id;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) {
        throw const AuthFailure(
          'Unable to connect. Check your connection and try again.',
        );
      }
      throw AuthFailure(
        error.code == 'email_not_confirmed'
            ? 'Confirm your email before signing in.'
            : 'Unable to sign in. Check your email and password and try again.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to connect. Check your connection and try again.',
      );
    }
  }

  @override
  Future<String> accessToken({bool refresh = false}) async {
    try {
      var session = client.auth.currentSession;
      if (session == null) {
        throw const AuthFailure(
          'Your session has expired. Please sign in again.',
          expired: true,
        );
      }
      if (refresh || session.isExpired) {
        session = (await client.auth.refreshSession()).session;
      }
      if (session == null) {
        throw const AuthFailure(
          'Your session has expired. Please sign in again.',
          expired: true,
        );
      }
      return session.accessToken;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) {
        throw const AuthFailure(
          'Unable to refresh your session. Check your connection and retry.',
        );
      }
      throw const AuthFailure(
        'Your session has expired. Please sign in again.',
        expired: true,
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to refresh your session. Check your connection and retry.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The SDK clears local state before its server logout request.
      if (client.auth.currentSession != null) {
        throw const AuthFailure('Unable to sign out. Please try again.');
      }
    }
  }
}

class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository({
    required this.identity,
    required this.baseUrl,
    required this.httpClient,
  });
  final AuthIdentity identity;
  final Uri baseUrl;
  final http.Client httpClient;
  @override
  bool get hasSession => identity.userId != null;
  @override
  Stream<void> get changes => identity.changes;
  @override
  Future<void> signIn(String email, String password) =>
      identity.signIn(email.trim(), password);
  @override
  Future<void> signOut() => identity.signOut();

  /// Shares the verified session, refresh-on-401 and safe HTTP handling with
  /// driver read repositories. Paths are relative to the configured API root.
  Future<dynamic> getAuthenticated(String path) =>
      _request(path, protected: true);

  Future<Uint8List> getAuthenticatedImage(String path) async =>
      await _request(path, protected: true, image: true) as Uint8List;

  Future<dynamic> postAuthenticated(
    String path, {
    Map<String, Object> body = const {},
  }) => _request(path, body: body, protected: true);
  Future<dynamic> deleteAuthenticated(String path) =>
      _request(path, protected: true, method: 'DELETE');

  Future<dynamic> _request(
    String path, {
    Map<String, Object>? body,
    bool protected = false,
    String? method,
    bool image = false,
  }) async {
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final headers = {
          'Accept': image ? 'image/png' : 'application/json',
          'Content-Type': 'application/json',
        };
        if (protected) {
          headers['Authorization'] =
              'Bearer ${await identity.accessToken(refresh: attempt > 0)}';
        }
        final request =
            http.Request(
                method ?? (body == null ? 'GET' : 'POST'),
                baseUrl.resolve(path),
              )
              ..headers.addAll(headers)
              ..followRedirects = false;
        if (body != null) request.body = jsonEncode(body);
        final response = await httpClient
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 401 && protected && attempt == 0) continue;
        if (response.statusCode == 401) {
          throw const AuthFailure(
            'Your session has expired. Please sign in again.',
            expired: true,
          );
        }
        if (response.statusCode == 403 && path == 'auth/me') {
          final data = jsonDecode(response.body);
          if (data is Map &&
              data['detail'] == 'Application profile is unavailable.') {
            throw const AuthFailure(
              'Complete your driver registration.',
              missingProfile: true,
            );
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AuthFailure(switch (response.statusCode) {
            400 => 'Unable to submit. Check your details and select an available company.',
            403 => 'Access was denied. Contact your parking administrator.',
            404 =>
              path.startsWith('vehicles')
                  ? 'Vehicle not found. Refresh your vehicles.'
                  : 'This parking session is no longer available. Refresh navigation and try again.',
            409 =>
              path == 'vehicles'
                  ? 'This plate is already registered.'
                  : path.startsWith('vehicles/')
                  ? 'This vehicle has parking or ANPR records and cannot be removed. Its history is preserved.'
                  : path.endsWith('/confirm')
                  ? 'This session cannot be confirmed. Refresh navigation to check its current status.'
                  : 'A route is unavailable for this assignment. It may already be occupied, closed or unreachable.',
            422 =>
              path.startsWith('vehicles')
                  ? 'Use 1–32 letters and digits for the number plate, without spaces or punctuation.'
                  : 'Check the required fields and password length.',
            429 => 'Too many attempts. Please wait and try again.',
            _ =>
              path.startsWith('auth/register')
                  ? 'The service is unavailable. Please try again. If registration was submitted, confirm your email and sign in to complete it.'
                  : 'The service is unavailable. Please try again.',
          });
        }
        if (image) {
          if (response.headers['content-type']?.split(';').first !=
                  'image/png' ||
              response.bodyBytes.isEmpty ||
              response.bodyBytes.length > 10 * 1024 * 1024) {
            throw const AuthFailure(
              'The verified floor plan is unavailable. Refresh navigation.',
            );
          }
          return response.bodyBytes;
        }
        return jsonDecode(response.body);
      }
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'Unable to reach the service or read its response. Check your connection and try again.',
      );
    }
  }

  @override
  Future<AuthProfile> profile() async {
    final data = await _request('auth/me', protected: true);
    if (data is! Map ||
        data['id'] != identity.userId ||
        data['role'] is! String ||
        data['approval_status'] is! String ||
        data['is_active'] is! bool ||
        (data['tenant_id'] != null && data['tenant_id'] is! String)) {
      throw const AuthFailure(
        'Unable to verify your account profile. Please retry.',
      );
    }
    return AuthProfile(
      id: data['id'] as String,
      role: data['role'] as String,
      approvalStatus: data['approval_status'] as String,
      isActive: data['is_active'] as bool,
      tenantId: data['tenant_id'] as String?,
      fullName: data['full_name'] is String
          ? data['full_name'] as String
          : null,
      companyName: data['company_name'] is String
          ? data['company_name'] as String
          : null,
    );
  }

  @override
  Future<List<AuthCompany>> companies() async {
    final data = await _request('auth/companies');
    if (data is! List ||
        data.any(
          (row) =>
              row is! Map || row['id'] is! String || row['name'] is! String,
        )) {
      throw const AuthFailure('Unable to load companies. Please retry.');
    }
    return [
      for (final row in data)
        AuthCompany(row['id'] as String, row['name'] as String),
    ];
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
  }) async {
    final result = await _request(
      'auth/register',
      body: {
        'full_name': name.trim(),
        'email': email.trim(),
        'password': password,
        'tenant_id': companyId,
      },
    );
    if (result is! Map || result['status'] != 'check_email_or_sign_in') {
      throw const AuthFailure(
        'Registration could not be confirmed. Check your email, then sign in to complete registration.',
      );
    }
  }

  @override
  Future<void> complete({
    required String name,
    required String companyId,
  }) async {
    final result = await _request(
      'auth/register/complete',
      protected: true,
      body: {'full_name': name.trim(), 'tenant_id': companyId},
    );
    if (result is! Map || result['status'] != 'profile_available') {
      throw const AuthFailure(
        'Profile completion could not be confirmed. Please retry.',
      );
    }
  }
}
