import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/auth_repository.dart';

class MfaFactor {
  const MfaFactor(this.id, this.name, {required this.verified});
  final String id;
  final String name;
  final bool verified;
}

class MfaSnapshot {
  const MfaSnapshot({required this.ready, this.factors = const []});
  final bool ready;
  final List<MfaFactor> factors;
  List<MfaFactor> get verified =>
      factors.where((factor) => factor.verified).toList();
  List<MfaFactor> get pending =>
      factors.where((factor) => !factor.verified).toList();
}

class MfaEnrollment {
  const MfaEnrollment(this.id, this.secret, {this.qrCode});
  final String id;
  final String secret;
  final String? qrCode;

  /// Supabase supplies the QR itself. Its Dart SDK wraps the SVG in a data URI;
  /// decode that wrapper locally without regenerating or uploading the secret.
  String? get qrSvg {
    var svg = qrCode;
    if (svg == null) return null;
    try {
      if (svg.startsWith('data:')) {
        final comma = svg.indexOf(',');
        if (comma < 0 ||
            !svg.substring(0, comma).startsWith('data:image/svg+xml')) {
          return null;
        }
        final metadata = svg.substring(0, comma);
        final payload = svg.substring(comma + 1);
        svg = metadata.contains(';base64')
            ? utf8.decode(base64Decode(payload))
            : payload.trimLeft().startsWith('<')
            ? payload
            : Uri.decodeComponent(payload);
      }
      return RegExp(r'<svg(?:\s|>)').hasMatch(svg) ? svg : null;
    } on FormatException {
      return null;
    }
  }
}

abstract interface class MfaService {
  Future<MfaSnapshot> inspect();
  Future<MfaEnrollment> enroll({String? replaceUnverifiedId});
  Future<void> verify(String factorId, String code);
}

/// Supabase owns all TOTP generation, challenge validation, and session signing.
/// This adapter never persists setup secrets or codes and never calls admin APIs.
class SupabaseMfaService implements MfaService {
  SupabaseMfaService(this.client);
  final SupabaseClient client;

  String _owner() {
    final session = client.auth.currentSession;
    if (session == null) {
      throw const AuthFailure(
        'Your session has expired. Sign in again.',
        expired: true,
      );
    }
    return session.user.id;
  }

  void _sameOwner(String owner) {
    if (_owner() != owner) {
      throw const AuthFailure('Your account changed. Sign in again.');
    }
  }

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) {
        throw const AuthFailure(
          'The result could not be confirmed. Check your connection and current setup before retrying.',
        );
      }
      throw AuthFailure(
        switch (error.code) {
          'mfa_verification_failed' ||
          'mfa_challenge_expired' ||
          'mfa_verification_rejected' ||
          'mfa_challenge_not_found' => 'That code was not accepted or has expired. Enter the current six-digit code.',
          'over_request_rate_limit' || 'over_mfa_rate_limit' =>
            'Too many attempts. Wait before trying again.',
          'invalid_jwt' ||
          'bad_jwt' ||
          'session_not_found' ||
          'refresh_token_not_found' =>
            'Your session has expired. Sign in again.',
          'insufficient_aal' =>
            'Verify an existing authenticator before changing MFA setup.',
          _ => 'Authenticator verification is unavailable. Check your setup or contact your VisionPark operator.',
        },
        expired: const {
          'invalid_jwt',
          'bad_jwt',
          'session_not_found',
          'refresh_token_not_found',
        }.contains(error.code),
      );
    } catch (_) {
      throw const AuthFailure(
        'The result could not be confirmed. Check your connection and current setup before retrying.',
      );
    }
  }

  @override
  Future<MfaSnapshot> inspect() => _safe(() async {
    final owner = _owner();
    if (client.auth.currentSession!.isExpired) {
      await client.auth.refreshSession();
    }
    _sameOwner(owner);
    // listFactors() in the installed SDK always refreshes. A fresh getUser()
    // obtains native factor state without a tokenRefreshed -> inspect loop.
    final user = (await client.auth.getUser()).user;
    _sameOwner(owner);
    if (user == null ||
        user.id != owner ||
        user.emailConfirmedAt == null ||
        user.isAnonymous) {
      throw const AuthFailure('Confirm your account and sign in again.');
    }
    final factors = [
      for (final factor in user.factors ?? <Factor>[])
        if (factor.factorType == FactorType.totp)
          MfaFactor(
            factor.id,
            factor.friendlyName ?? 'Authenticator',
            verified: factor.status == FactorStatus.verified,
          ),
    ];
    final aal = client.auth.mfa.getAuthenticatorAssuranceLevel();
    return MfaSnapshot(
      ready:
          aal.currentLevel == AuthenticatorAssuranceLevels.aal2 &&
          factors.any((factor) => factor.verified),
      factors: factors,
    );
  });

  @override
  Future<MfaEnrollment> enroll({String? replaceUnverifiedId}) => _safe(
    () async {
      final owner = _owner();
      final state = await inspect();
      if (state.verified.isNotEmpty) {
        throw const AuthFailure(
          'Verify your existing authenticator instead of enrolling another.',
        );
      }
      if (replaceUnverifiedId != null) {
        if (!state.pending.any((factor) => factor.id == replaceUnverifiedId)) {
          throw const AuthFailure(
            'Setup changed. Check your current authenticator setup.',
          );
        }
        await client.auth.mfa.unenroll(replaceUnverifiedId);
        _sameOwner(owner);
      } else if (state.pending.isNotEmpty) {
        throw const AuthFailure(
          'An unfinished setup already exists. Restart that setup explicitly.',
        );
      }
      final factor = await client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'VisionPark',
        friendlyName: 'VisionPark ${DateTime.now().microsecondsSinceEpoch}',
      );
      _sameOwner(owner);
      return MfaEnrollment(
        factor.id,
        factor.totp!.secret,
        qrCode: factor.totp!.qrCode,
      );
    },
  );

  @override
  Future<void> verify(String factorId, String code) => _safe(() async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const AuthFailure(
        'Enter the six-digit code from your authenticator.',
      );
    }
    final owner = _owner();
    final state = await inspect();
    if (!state.factors.any((factor) => factor.id == factorId)) {
      throw const AuthFailure(
        'Setup changed. Check your current authenticator setup.',
      );
    }
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
    _sameOwner(owner);
    if (!(await inspect()).ready) {
      throw const AuthFailure(
        'Verification could not be confirmed. Check your current session and retry.',
      );
    }
  });
}
