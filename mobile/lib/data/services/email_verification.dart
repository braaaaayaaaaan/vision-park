import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/auth_repository.dart';

class EmailVerificationResult {
  const EmailVerificationResult({
    required this.email,
    required this.hasSession,
    this.isVerified = true,
  });
  final String? email;
  final bool hasSession;
  final bool isVerified;
}

/// Accept only the signup callback and unambiguous Supabase parameters. Values
/// remain untrusted until Supabase validates them; never log or persist the URI.
Map<String, String> emailConfirmationParameters(Uri uri) {
  if (uri.scheme != 'visionpark' ||
      uri.host != 'auth' ||
      uri.path != '/confirm' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    throw const AuthFailure(
      'This is not a valid VisionPark confirmation link.',
    );
  }
  const allowed = {
    'access_token',
    'refresh_token',
    'expires_in',
    'expires_at',
    'token_type',
    'type',
    'code',
    'error',
    'error_code',
    'error_description',
  };
  final values = <String, String>{};
  for (final source in [uri.query, uri.fragment]) {
    for (final entry in Uri(query: source).queryParametersAll.entries) {
      if (!allowed.contains(entry.key) ||
          entry.value.length != 1 ||
          values.containsKey(entry.key)) {
        throw const AuthFailure(
          'This confirmation link has invalid or ambiguous parameters.',
        );
      }
      values[entry.key] = entry.value.single;
    }
  }
  if (values.keys.any((key) => key.startsWith('error'))) {
    throw const AuthFailure(
      'This confirmation link is invalid, expired or already used. Continue to sign in if you already confirmed your email.',
    );
  }
  if (values['type'] != null && !{'signup', 'email'}.contains(values['type'])) {
    throw const AuthFailure(
      'Open the signup confirmation link from your VisionPark email.',
    );
  }
  if (values.containsKey('code') &&
      values.keys.any(
        (key) => {
          'access_token',
          'refresh_token',
          'expires_in',
          'expires_at',
          'token_type',
        }.contains(key),
      )) {
    throw const AuthFailure(
      'This confirmation link mixes incompatible authentication flows.',
    );
  }
  return values;
}

abstract interface class EmailVerifier {
  Future<EmailVerificationResult> verify(Uri callback, {String? expectedEmail});
}

class SupabaseEmailVerifier implements EmailVerifier {
  SupabaseEmailVerifier(this.client);
  final SupabaseClient client;

  @override
  Future<EmailVerificationResult> verify(
    Uri callback, {
    String? expectedEmail,
  }) async {
    final parameters = emailConfirmationParameters(callback);
    final existing = client.auth.currentSession;
    if (existing != null &&
        parameters.keys.any(
          (key) => {'access_token', 'refresh_token', 'code'}.contains(key),
        )) {
      throw const AuthFailure(
        'An account is already signed in. Continue to your account, or sign out before confirming another registration.',
      );
    }
    try {
      if (existing != null) {
        final user = _confirmed(
          (await client.auth.getUser(existing.accessToken)).user,
          expectedEmail,
        );
        if (user.id != existing.user.id) {
          throw const AuthFailure('Email confirmation could not be verified.');
        }
        return EmailVerificationResult(email: user.email, hasSession: true);
      }
      if (parameters.containsKey('code')) {
        // The current server-side signup uses implicit flow. A PKCE callback
        // works only if this SDK has the original verifier; never invent one.
        try {
          final parsed = await client.auth.getSessionFromUrl(
            callback,
            storeSession: false,
          );
          final user = _confirmed(
            (await client.auth.getUser(parsed.session.accessToken)).user,
            expectedEmail,
          );
          if (user.id != parsed.session.user.id) {
            throw const AuthFailure(
              'Email confirmation could not be verified.',
            );
          }
          return EmailVerificationResult(
            email: user.email,
            hasSession: client.auth.currentSession?.user.id == user.id,
          );
        } on AuthFailure {
          await _discardSession();
          rethrow;
        } catch (_) {
          await _discardSession();
          return const EmailVerificationResult(
            email: null,
            hasSession: false,
            isVerified: false,
          );
        }
      }
      final expires = int.tryParse(parameters['expires_in'] ?? '');
      if (parameters['access_token']?.isNotEmpty != true ||
          parameters['refresh_token']?.isNotEmpty != true ||
          parameters['token_type'] != 'bearer' ||
          expires == null ||
          expires <= 0) {
        return const EmailVerificationResult(
          email: null,
          hasSession: false,
          isVerified: false,
        );
      }
      // The SDK calls Auth /user to validate the supplied access token. Do not
      // save callback credentials before confirmation and email matching pass.
      final parsed = await client.auth.getSessionFromUrl(
        callback,
        storeSession: false,
      );
      final user = _confirmed(parsed.session.user, expectedEmail);
      try {
        // Validate/rotate the refresh token too, rather than persisting an
        // arbitrary refresh token alongside a legitimate access token.
        final restored = await client.auth.setSession(
          parameters['refresh_token']!,
        );
        final current = _confirmed(restored.user, expectedEmail);
        if (current.id != user.id ||
            client.auth.currentSession?.user.id != user.id) {
          throw const AuthFailure(
            'The confirmation credentials do not belong to the same account.',
          );
        }
        return EmailVerificationResult(email: user.email, hasSession: true);
      } on AuthFailure {
        await _discardSession();
        rethrow;
      } catch (_) {
        await _discardSession();
        // Auth validated the access token and confirmed email, but secure
        // automatic session restoration failed. Sign-in remains necessary.
        return EmailVerificationResult(email: user.email, hasSession: false);
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) {
        throw const AuthFailure(
          'Unable to connect. Continue to sign in when you are online to check confirmation securely.',
        );
      }
      throw const AuthFailure(
        'This confirmation link is invalid, expired or already used. If you already confirmed your email, sign in to check your account.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to confirm your email. Check your connection and reopen the email link.',
      );
    }
  }

  User _confirmed(User? user, String? expectedEmail) {
    if (user == null ||
        user.isAnonymous ||
        user.emailConfirmedAt == null ||
        user.email == null ||
        user.email!.trim().isEmpty) {
      throw const AuthFailure('Email confirmation could not be verified.');
    }
    if (expectedEmail != null &&
        user.email!.toLowerCase() != expectedEmail.trim().toLowerCase()) {
      throw const AuthFailure(
        'This link belongs to a different email address. Open the confirmation email for this registration.',
      );
    }
    return user;
  }

  Future<void> _discardSession() async {
    if (client.auth.currentSession == null) return;
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The SDK clears local state before requesting remote logout.
    }
  }
}

/// Only the pending email is persisted, never passwords, links or verification
/// claims. Auth sessions remain managed by the existing Supabase SDK.
class VerificationPlatform {
  final _links = StreamController<String>.broadcast();
  Stream<String> get links => _links.stream;
  String? pendingEmail;
  Future<String?> readPendingEmail() async => pendingEmail;
  Future<void> savePendingEmail(String? email) async {
    pendingEmail = email;
  }

  Future<String?> initialLink() async => null;
  Future<bool> canOpenEmail() async => false;
  Future<bool> openEmail() async => false;
  void dispose() {
    unawaited(_links.close());
  }
}

class AndroidVerificationPlatform extends VerificationPlatform {
  static const _channel = MethodChannel('visionpark/email_verification');
  AndroidVerificationPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'verificationLink' && call.arguments is String) {
        _links.add(call.arguments as String);
      }
    });
  }
  @override
  Future<String?> readPendingEmail() =>
      _channel.invokeMethod<String>('readPendingEmail');
  @override
  Future<void> savePendingEmail(String? email) =>
      _channel.invokeMethod<void>('savePendingEmail', email);
  @override
  Future<String?> initialLink() => _channel.invokeMethod<String>('initialLink');
  @override
  Future<bool> canOpenEmail() async =>
      await _channel.invokeMethod<bool>('canOpenEmail') ?? false;
  @override
  Future<bool> openEmail() async =>
      await _channel.invokeMethod<bool>('openEmail') ?? false;
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
