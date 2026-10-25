import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/form_validators.dart';
import '../repositories/auth_repository.dart';

const passwordRecoveryRedirect = 'visionpark://auth/reset-password';

abstract interface class PasswordRecoveryService {
  Future<RecoveryRequestState> requestState();
  Future<void> startOver();
  Future<void> request(String email);
  Future<String> establish(Uri callback);
  Future<void> update(String password);
  Future<void> end();
  Future<void> dispose();
}

/// Local attempt information, never evidence of an account or email delivery.
class RecoveryRequestState {
  const RecoveryRequestState({this.pending = false, this.availableAt});
  final bool pending;
  final DateTime? availableAt;
}

class RecoveryRequestStore {
  const RecoveryRequestStore(this.storage, this.key);
  final GotrueAsyncStorage storage;
  final String key;

  Future<RecoveryRequestState> read() async {
    final value = await storage.getItem(key: key);
    if (value == null) return const RecoveryRequestState();
    final data = jsonDecode(value) as Map<String, dynamic>;
    final deadline = data['available_at'] as int?;
    return RecoveryRequestState(
      pending: data['pending'] as bool,
      availableAt: deadline == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deadline, isUtc: true),
    );
  }

  Future<void> write(RecoveryRequestState state) => storage.setItem(
    key: key,
    value: jsonEncode({
      'pending': state.pending,
      'available_at': state.availableAt?.millisecondsSinceEpoch,
    }),
  );
}

/// Namespaces the SDK's own PKCE verifier, keeping signup and reset state apart.
/// No application token or plaintext password is stored here.
class RecoveryPkceStorage extends GotrueAsyncStorage {
  const RecoveryPkceStorage(this.storage, this.namespace);
  final GotrueAsyncStorage storage;
  final String namespace;
  String _key(String key) => 'visionpark-recovery-$namespace-$key';
  @override
  Future<String?> getItem({required String key}) =>
      storage.getItem(key: _key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.setItem(key: _key(key), value: value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.removeItem(key: _key(key));
}

class SupabasePasswordRecoveryService implements PasswordRecoveryService {
  SupabasePasswordRecoveryService(
    this.client, {
    required this.requestStore,
    DateTime Function()? now,
    void Function(String)? diagnostic,
  }) : _now = now ?? DateTime.now,
       _diagnostic = diagnostic ?? debugPrint;
  factory SupabasePasswordRecoveryService.create({
    required String url,
    required String publicKey,
  }) {
    final storage = SharedPreferencesGotrueAsyncStorage();
    final namespace = Uri.parse(url).host;
    return SupabasePasswordRecoveryService(
      SupabaseClient(
        url,
        publicKey,
        authOptions: AuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: false,
          pkceAsyncStorage: RecoveryPkceStorage(storage, namespace),
        ),
      ),
      requestStore: RecoveryRequestStore(
        storage,
        'visionpark-recovery-$namespace-request-state',
      ),
    );
  }

  // A standard SDK client without the Flutter session-persistence integration.
  // Recovery auth changes never reach the application's identity/repositories.
  final SupabaseClient client;
  final RecoveryRequestStore requestStore;
  final DateTime Function() _now;
  final void Function(String) _diagnostic;
  bool _requestBusy = false;
  static const requestWait =
      'Check your inbox and spam folder before trying again. Email limits may require a longer wait.';
  String? _authorizedToken;
  String? _authorizedUser;
  String? _usedCode;
  bool _updating = false;
  static const invalidLink =
      'This reset link is invalid, expired or already used. Request a new link on this device.';

  @override
  Future<RecoveryRequestState> requestState() => requestStore.read();

  @override
  Future<void> startOver() async {
    if (_requestBusy) throw const AuthFailure(requestWait);
    _requestBusy = true;
    try {
      final state = await requestState();
      if (state.availableAt?.isAfter(_now()) ?? false) {
        throw const AuthFailure(requestWait);
      }
      // Explicit abandonment only. Use the SDK's public cleanup API, without
      // reading, copying, restoring or naming any SDK-private verifier keys.
      _authorizedToken = null;
      _authorizedUser = null;
      await client.auth.signOut(scope: SignOutScope.local);
      await requestStore.write(
        RecoveryRequestState(availableAt: state.availableAt),
      );
    } on AuthFailure {
      rethrow;
    } catch (_) {
      _diagnostic('Password recovery: local_state_unavailable');
      throw const AuthFailure(
        'Unable to start over safely. Please try again later.',
      );
    } finally {
      _requestBusy = false;
    }
  }

  @override
  Future<void> request(String email) async {
    if (AuthFormValidators.email(email) != null) {
      throw const AuthFailure('Enter a valid email address.');
    }
    if (_requestBusy) throw const AuthFailure(requestWait);
    _requestBusy = true;
    try {
      final state = await requestState();
      if (state.pending || (state.availableAt?.isAfter(_now()) ?? false)) {
        throw const AuthFailure(requestWait);
      }
      // Persist before calling Auth, so even a process death/lost response
      // cannot cause an automatic replacement request on the next launch.
      await requestStore.write(
        RecoveryRequestState(
          pending: true,
          availableAt: _now().add(const Duration(seconds: 60)),
        ),
      );
    } on AuthFailure {
      _requestBusy = false;
      rethrow;
    } catch (_) {
      _requestBusy = false;
      _diagnostic('Password recovery: local_state_unavailable');
      throw const AuthFailure(
        'Unable to save the request safely. Please try again later.',
      );
    }
    try {
      await end();
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: passwordRecoveryRedirect,
      );
      _diagnostic('Password recovery: request_returned');
    } on AuthRetryableFetchException {
      _diagnostic('Password recovery: request_outcome_unknown');
      throw const AuthFailure(
        'The request could not be confirmed. An email may still arrive. Check your inbox before trying again.',
      );
    } on AuthApiException catch (error) {
      // Log only a validated HTTP status, never provider messages or payloads.
      final status = int.tryParse(error.statusCode ?? '');
      _diagnostic(
        'Password recovery: auth_response status=${status != null && status >= 400 && status <= 599 ? status : "unknown"}',
      );
      // Known/unknown accounts, mail-delivery restrictions, rate limits and
      // other Auth responses keep identical local pending/cooldown state.
    } on AuthException {
      _diagnostic('Password recovery: request_outcome_unknown');
      throw const AuthFailure(
        'The request could not be confirmed. Check your inbox before trying again.',
      );
    } catch (_) {
      _diagnostic('Password recovery: request_outcome_unknown');
      throw const AuthFailure(
        'The request could not be confirmed. Check your inbox before trying again.',
      );
    } finally {
      try {
        await requestStore.write(
          RecoveryRequestState(
            pending: true,
            availableAt: _now().add(const Duration(seconds: 60)),
          ),
        );
      } catch (_) {
        // The pre-request marker remains. Never auto-retry after this failure.
        _diagnostic('Password recovery: cooldown_save_failed');
      }
      _requestBusy = false;
    }
  }

  @override
  Future<String> establish(Uri callback) async {
    if (_requestBusy) throw const AuthFailure(requestWait);
    _authorizedToken = null;
    _authorizedUser = null;
    try {
      final values = <String, String>{};
      if (callback.scheme != 'visionpark' ||
          callback.host != 'auth' ||
          callback.path != '/reset-password' ||
          callback.userInfo.isNotEmpty ||
          callback.hasPort) {
        throw const AuthFailure(invalidLink);
      }
      for (final source in [callback.query, callback.fragment]) {
        for (final entry in Uri(query: source).queryParametersAll.entries) {
          if (!{
                'code',
                'type',
                'error',
                'error_code',
                'error_description',
              }.contains(entry.key) ||
              entry.value.length != 1 ||
              values.containsKey(entry.key)) {
            throw const AuthFailure(invalidLink);
          }
          values[entry.key] = entry.value.single;
        }
      }
      final code = values['code'];
      if (values.keys.any((key) => key.startsWith('error')) ||
          (values['type'] != null && values['type'] != 'recovery') ||
          code == null ||
          code.isEmpty ||
          code.length > 2048 ||
          code == _usedCode) {
        throw const AuthFailure(invalidLink);
      }
      // The SDK obtains redirectType from its saved PKCE request purpose, not
      // from caller-controlled URL parameters. Auth validates code + verifier.
      final response = await client.auth.exchangeCodeForSession(code);
      if (response.redirectType != AuthChangeEvent.passwordRecovery.name) {
        throw const AuthFailure(invalidLink);
      }
      final session = client.auth.currentSession;
      final user = (await client.auth.getUser(response.session.accessToken))
          .user;
      if (session == null ||
          session.isExpired ||
          user == null ||
          user.isAnonymous ||
          user.emailConfirmedAt == null ||
          user.email == null ||
          user.id != response.session.user.id ||
          session.user.id != user.id) {
        throw const AuthFailure(invalidLink);
      }
      _authorizedToken = session.accessToken;
      _authorizedUser = user.id;
      _usedCode = code;
      try {
        final state = await requestState();
        await requestStore.write(
          RecoveryRequestState(availableAt: state.availableAt),
        );
      } catch (_) {
        // Stale local pending state cannot grant access or block this session.
        _diagnostic('Password recovery: local_state_unavailable');
      }
      return user.email!;
    } catch (_) {
      await end();
      throw const AuthFailure(invalidLink);
    }
  }

  @override
  Future<void> update(String password) async {
    final validation = AuthFormValidators.registrationPassword(password);
    if (validation != null) throw AuthFailure(validation);
    final session = client.auth.currentSession;
    if (_updating ||
        _authorizedToken == null ||
        session == null ||
        session.isExpired ||
        session.accessToken != _authorizedToken ||
        session.user.id != _authorizedUser) {
      throw const AuthFailure(invalidLink);
    }
    _updating = true;
    try {
      final user = (await client.auth.getUser(session.accessToken)).user;
      if (user == null ||
          user.isAnonymous ||
          user.email == null ||
          user.id != _authorizedUser ||
          user.emailConfirmedAt == null) {
        throw const AuthFailure(invalidLink);
      }
      // Consume local authorization before writing: a lost response must not
      // lead to automatic repeated password changes. A fresh link can recover.
      _authorizedToken = null;
      final result = await client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (result.user?.id != _authorizedUser) {
        throw const AuthFailure(invalidLink);
      }
      await end();
    } on AuthFailure {
      await end();
      rethrow;
    } catch (_) {
      await end();
      throw const AuthFailure(
        'The update could not be confirmed. Try signing in with your new password, or request a fresh reset link.',
      );
    } finally {
      _updating = false;
    }
  }

  @override
  Future<void> end() async {
    _authorizedToken = null;
    _authorizedUser = null;
    if (client.auth.currentSession != null) {
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // SDK local state is cleared before remote logout; no app session exists.
      }
    }
  }

  @override
  Future<void> dispose() => client.dispose();
}
