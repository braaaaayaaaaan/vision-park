import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mfa.dart';

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.expired = false,
    this.missingProfile = false,
    this.code,
    this.retryable = false,
  });
  final String message;
  final bool expired;
  final bool missingProfile;
  final String? code;
  final bool retryable;
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
    this.email,
    this.mfaVerified = false,
  });
  final String id;
  final String role;
  final String approvalStatus;
  final bool isActive;
  final String? tenantId;
  final String? fullName;
  final String? companyName;
  final String? email;
  final bool mfaVerified;

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
  MfaService? get mfa;
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
            : 'Unavailable to sign in. Check your email and password again',
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
          retryable: true,
          code: 'auth_refresh_transport',
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

class RemoteAuthRepository
    with WidgetsBindingObserver
    implements AuthRepository {
  RemoteAuthRepository({
    required this.identity,
    required this.baseUrl,
    required this.httpClient,
    this.mfa,
  }) {
    _owner = identity.userId;
    WidgetsBinding.instance.addObserver(this);
    _identityChanges = identity.changes.listen(
      (_) {
        if (_owner != identity.userId || identity.userId == null) {
          _owner = identity.userId;
          _cancelReads();
        }
        if (!_disposed) _authChanges.add(null);
      },
      onError: (Object error) {
        if (!_disposed) _authChanges.addError(error);
      },
    );
  }
  final AuthIdentity identity;
  final Uri baseUrl;
  final http.Client httpClient;
  @override
  final MfaService? mfa;
  final _authChanges = StreamController<void>.broadcast();
  final _reads = <String, Future<dynamic>>{};
  final _cancellations = <Completer<void>>{};
  late final StreamSubscription<void> _identityChanges;
  String? _owner;
  int _epoch = 0;
  bool _disposed = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _cancelReads() {
    _epoch++;
    for (final cancel in _cancellations) {
      if (!cancel.isCompleted) cancel.complete();
    }
    _reads.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelReads();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelReads();
    _identityChanges.cancel();
    unawaited(_authChanges.close());
    WidgetsBinding.instance.removeObserver(this);
    httpClient.close();
  }

  Future<dynamic> _read(String path, {bool image = false}) {
    final key = '${identity.userId}:$image:$path';
    return _reads.putIfAbsent(key, () {
      final epoch = _epoch, owner = identity.userId;
      final cancel = Completer<void>();
      _cancellations.add(cancel);
      bool active() =>
          !_disposed &&
          _foreground &&
          epoch == _epoch &&
          owner != null &&
          owner == identity.userId;
      Future<dynamic> run() async {
        try {
          for (var attempt = 0; ; attempt++) {
            if (!active()) {
              throw const AuthFailure(
                'Refresh when signed in and the app is active.',
                code: 'read_cancelled',
              );
            }
            try {
              final result = await _request(
                path,
                protected: true,
                image: image,
                cancel: cancel.future,
                isCurrentRead: active,
              );
              if (!active()) {
                throw const AuthFailure(
                  'The account or screen changed. Refresh to continue.',
                  code: 'read_cancelled',
                );
              }
              return result;
            } on AuthFailure catch (error) {
              final safe =
                  path.startsWith('parking/') ||
                  path.startsWith('payments/') ||
                  path == 'vehicles' ||
                  path.startsWith('vehicles/');
              if (!safe || !error.retryable || attempt >= 2 || !active()) {
                rethrow;
              }
              await Future.any([
                Future<void>.delayed(
                  Duration(
                    milliseconds:
                        (300 *
                                (1 << attempt) *
                                (0.85 + Random().nextDouble() * .3))
                            .round(),
                  ),
                ),
                cancel.future,
              ]);
            }
          }
        } finally {
          if (!cancel.isCompleted) cancel.complete();
          _cancellations.remove(cancel);
          if (epoch == _epoch) _reads.remove(key);
        }
      }

      return Future<dynamic>.microtask(run);
    });
  }

  @override
  bool get hasSession => identity.userId != null;
  @override
  Stream<void> get changes => _authChanges.stream;
  @override
  Future<void> signIn(String email, String password) =>
      identity.signIn(email.trim(), password);
  @override
  Future<void> signOut() => identity.signOut();

  /// Shares the verified session, refresh-on-401 and safe HTTP handling with
  /// driver read repositories. Paths are relative to the configured API root.
  Future<dynamic> getAuthenticated(String path) => _read(path);

  Future<Uint8List> getAuthenticatedImage(String path) async =>
      await _read(path, image: true) as Uint8List;

  Future<dynamic> postAuthenticated(
    String path, {
    Map<String, Object> body = const {},
  }) => _request(path, body: body, protected: true);
  Future<dynamic> deleteAuthenticated(String path) =>
      _request(path, protected: true, method: 'DELETE');

  /// Payment writes retain their exact body and key across the existing single
  /// authentication refresh retry. Never retry uncertain writes with a new key.
  Future<dynamic> paymentAuthenticated(
    String path, {
    String method = 'GET',
    Map<String, Object>? body,
    String? idempotencyKey,
  }) => method == 'GET' && body == null
      ? _read(path)
      : _request(
          path,
          protected: true,
          method: method,
          body: body,
          idempotencyKey: idempotencyKey,
        );

  Future<dynamic> _request(
    String path, {
    Map<String, Object>? body,
    bool protected = false,
    String? method,
    bool image = false,
    String? idempotencyKey,
    Future<void>? cancel,
    bool Function()? isCurrentRead,
  }) async {
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (isCurrentRead?.call() == false) {
          throw const AuthFailure(
            'Refresh when the app is active.',
            code: 'read_cancelled',
          );
        }
        final headers = {
          'Accept': image ? 'image/png' : 'application/json',
          'Content-Type': 'application/json',
        };
        if (protected) {
          headers['Authorization'] =
              'Bearer ${await identity.accessToken(refresh: attempt > 0)}';
        }
        if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
        if (isCurrentRead?.call() == false) {
          throw const AuthFailure(
            'The account or screen changed.',
            code: 'read_cancelled',
          );
        }
        final timeoutAbort = Completer<void>();
        final request =
            http.AbortableRequest(
                method ?? (body == null ? 'GET' : 'POST'),
                baseUrl.resolve(path),
                abortTrigger: cancel == null
                    ? null
                    : Future.any([cancel, timeoutAbort.future]),
              )
              ..headers.addAll(headers)
              ..followRedirects = false;
        if (body != null) request.body = jsonEncode(body);
        final response = await httpClient
            .send(request)
            .then(http.Response.fromStream)
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                if (cancel != null && !timeoutAbort.isCompleted) {
                  timeoutAbort.complete();
                }
                throw TimeoutException('API request timed out');
              },
            );
        if (response.statusCode == 401 && protected && attempt == 0) continue;
        if (response.statusCode == 401) {
          throw const AuthFailure(
            'Your session has expired. Please sign in again.',
            expired: true,
          );
        }
        if (response.statusCode == 403) {
          final data = jsonDecode(response.body);
          if (data is Map &&
              data['detail'] is Map &&
              data['detail']['code'] == 'mfa_required') {
            if (!_disposed) _authChanges.add(null);
            throw const AuthFailure(
              'Complete authenticator verification to continue.',
              code: 'mfa_required',
            );
          }
          if (data is Map &&
              data['detail'] == 'Confirm your email before continuing.') {
            throw const AuthFailure('Confirm your email before continuing.');
          }
          if (data is Map &&
              path == 'auth/me' &&
              data['detail'] == 'Application profile is unavailable.') {
            throw const AuthFailure(
              'Complete your driver registration.',
              missingProfile: true,
            );
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (image &&
              const {408, 500, 502, 503, 504}.contains(response.statusCode)) {
            throw AuthFailure(
              'The floor plan is temporarily unavailable. Please try again.',
              retryable: true,
              code: 'http_${response.statusCode}',
            );
          }
          if (path.startsWith('payments/')) {
            dynamic detail;
            try {
              detail = (jsonDecode(response.body) as Map)['detail'];
            } catch (_) {}
            final code = detail is Map ? detail['code'] : null;
            const messages = {
              'payments_inactive': 'Parking payments are not activated.',
              'finance_schema_unavailable':
                  'Payment services are unavailable. Try again later.',
              'stale': 'This setting changed. Refresh before saving again.',
              'stale_quote':
                  'This quotation changed. Refresh the payment request.',
              'quote_expired':
                  'This quotation expired. Renew it before paying.',
              'in_progress':
                  'A payment is processing. Check the existing transaction.',
              'already_paid':
                  'This charge is already paid. Refresh to open its receipt.',
              'manual_required':
                  'Enable automatic payment or choose a test card.',
              'payment_not_found': 'The payment record is not available.',
              'receipt_not_found': 'The receipt is not available yet.',
              'idempotency_conflict': 'This request changed. Check the original payment before trying again.',
            };
            throw AuthFailure(
              messages[code] ?? 'Payment could not be confirmed. Refresh or retry the same request.',
              code: messages.containsKey(code)
                  ? code as String
                  : 'payment_unavailable',
              retryable:
                  body == null &&
                  (method == null || method == 'GET') &&
                  const {408, 500, 502, 503, 504}.contains(response.statusCode),
            );
          }
          if (response.statusCode == 409 && path.startsWith('vehicles')) {
            // Only recognized application codes select specific local feedback.
            // Never display an arbitrary database/backend message.
            dynamic detail;
            try {
              final data = jsonDecode(response.body);
              if (data is Map) detail = data['detail'];
            } catch (_) {
              /* Retain the existing safe fallback below. */
            }
            if (detail is Map &&
                detail['code'] == 'vehicle_limit_reached' &&
                path == 'vehicles') {
              throw const AuthFailure(
                'You have reached the five-vehicle limit. Remove an eligible registration or wait for a pending registration to be rejected.',
                code: 'vehicle_limit_reached',
              );
            }
            if (detail is Map &&
                detail['code'] == 'rejected_vehicle_retained' &&
                path.startsWith('vehicles/')) {
              throw const AuthFailure(
                'Rejected registrations are retained for audit and cannot be removed.',
                code: 'rejected_vehicle_retained',
              );
            }
          }
          throw AuthFailure(
            switch (response.statusCode) {
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
                    : 'Check the required fields and password requirements.',
              429 => 'Too many attempts. Please wait and try again.',
              _ =>
                path.startsWith('auth/register')
                    ? 'The service is unavailable. Please try again. If registration was submitted, confirm your email and sign in to complete it.'
                    : 'The service is unavailable. Please try again.',
            },
            retryable:
                body == null &&
                (method == null || method == 'GET') &&
                const {408, 500, 502, 503, 504}.contains(response.statusCode),
            code: 'http_${response.statusCode}',
          );
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
    } catch (error) {
      throw AuthFailure(
        'Unable to reach the service or read its response. Check your connection and try again.',
        retryable:
            body == null &&
            (method == null || method == 'GET') &&
            (error is http.ClientException || error is TimeoutException),
        code: error is TimeoutException
            ? 'read_timeout'
            : error is http.ClientException
            ? 'read_transport'
            : 'read_response_invalid',
      );
    }
  }

  @override
  Future<AuthProfile> profile() async {
    dynamic data;
    try {
      data = await _request('auth/me', protected: true);
    } on AuthFailure catch (error) {
      if (!error.missingProfile) rethrow;
      // Only an exact missing-profile response permits automatic provisioning.
      // Auth and metadata are revalidated by the backend, not by this client.
      final result = await _request(
        'auth/register/restore',
        body: const {},
        protected: true,
      );
      if (result is Map && result['status'] == 'completion_required') {
        rethrow;
      }
      if (result is! Map || result['status'] != 'profile_available') {
        throw const AuthFailure(
          'Unable to restore your registration. Please retry.',
        );
      }
      data = await _request('auth/me', protected: true);
    }
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
      email: identity is SupabaseIdentity
          ? (identity as SupabaseIdentity).client.auth.currentUser?.email
          : null,
      mfaVerified: data['aal'] == 'aal2' && data['mfa_verified'] == true,
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
