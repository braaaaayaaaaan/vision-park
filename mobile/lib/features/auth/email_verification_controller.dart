import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/email_verification.dart';

enum VerificationStage {
  idle,
  waiting,
  checking,
  verified,
  signInRequired,
  failure,
}

class EmailVerificationController extends ChangeNotifier {
  EmailVerificationController({VerificationPlatform? platform, this.verifier})
    : platform = platform ?? VerificationPlatform();
  final VerificationPlatform platform;
  final EmailVerifier? verifier;
  // Both auth callbacks share the existing single native channel listener.
  Future<void> Function(String link)? onRecoveryLink;
  VerificationStage stage = VerificationStage.idle;
  String? email;
  String? message;
  bool callbackHasSession = false;
  bool emailAppAvailable = false;
  bool _disposed = false;
  bool _started = false;
  String? _lastCallback;
  StreamSubscription<String>? _links;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({required bool hasSession}) async {
    if (_started) return;
    _started = true;
    _links = platform.links.listen(
      (link) => unawaited(handleLink(link)),
      onError: (Object _) {
        message =
            'Unable to open the email link. Please reopen it from your email.';
        _notify();
      },
    );
    try {
      final saved = await platform.readPendingEmail();
      if (_disposed) return;
      if (!hasSession && stage == VerificationStage.idle && saved != null) {
        email = saved;
        stage = VerificationStage.waiting;
        _notify();
      }
      final link = await platform.initialLink();
      if (!_disposed && link != null) await handleLink(link);
    } catch (_) {
      // Unsupported platforms can still register and sign in; no false success.
    }
    try {
      final available = await platform.canOpenEmail();
      if (!_disposed) {
        emailAppAvailable = available;
        _notify();
      }
    } catch (_) {
      if (!_disposed) {
        emailAppAvailable = false;
        _notify();
      }
    }
  }

  Future<void> waitForEmail(String value) async {
    email = value.trim();
    stage = VerificationStage.waiting;
    callbackHasSession = false;
    message = null;
    _lastCallback = null;
    _notify();
    try {
      await platform.savePendingEmail(email);
    } catch (_) {
      message = 'Keep your confirmation email. This device could not save the pending registration reminder.';
      _notify();
    }
  }

  Future<void> handleLink(String link) async {
    if (!_disposed && Uri.tryParse(link)?.path == '/reset-password') {
      await onRecoveryLink?.call(link);
      return;
    }
    if (_disposed || stage == VerificationStage.checking) return;
    try {
      final uri = Uri.parse(link);
      final parameters = emailConfirmationParameters(uri);
      final key = parameters['access_token'] ?? parameters['code'];
      if (key != null && _lastCallback == key) return;
      stage = VerificationStage.checking;
      message = null;
      _notify();
      if (verifier == null) {
        throw const AuthFailure(
          'Email confirmation is unavailable on this device.',
        );
      }
      final result = await verifier!.verify(uri, expectedEmail: email);
      if (_disposed) return;
      if (result.isVerified) _lastCallback = key;
      email = result.email ?? email;
      callbackHasSession = result.hasSession;
      stage = result.isVerified
          ? VerificationStage.verified
          : VerificationStage.signInRequired;
      if (!result.isVerified) {
        message = 'Automatic sign-in is unavailable. Your email status will be checked securely when you sign in.';
      }
      _notify();
      try {
        if (!result.isVerified) return;
        await platform.savePendingEmail(null);
      } catch (_) {
        /* Reminder only. */
      }
    } on AuthFailure catch (error) {
      if (_disposed) return;
      message = error.message;
      stage = VerificationStage.failure;
      _notify();
    } catch (_) {
      if (_disposed) return;
      message =
          'Unable to read this confirmation link. Reopen it from your email.';
      stage = VerificationStage.failure;
      _notify();
    }
  }

  Future<void> openEmail() async {
    try {
      if (await platform.openEmail()) return;
    } catch (_) {
      /* Email app may not be installed. */
    }
    emailAppAvailable = false;
    message = 'Open your email app manually and look for the VisionPark confirmation email. Check your spam folder too.';
    _notify();
  }

  void showWaiting() {
    stage = email == null ? VerificationStage.idle : VerificationStage.waiting;
    message = null;
    _notify();
  }

  void continueToAccount() {
    stage = VerificationStage.idle;
    message = null;
    _notify();
  }

  Future<void> leave() async {
    continueToAccount();
    try {
      await platform.savePendingEmail(null);
    } catch (_) {
      /* Reminder only. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_links?.cancel());
    platform.dispose();
    super.dispose();
  }
}
