import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';

enum AuthStatus {
  loading,
  signedOut,
  completion,
  blocked,
  mfa,
  approved,
  error,
}

class AuthController extends ChangeNotifier {
  AuthController(this.repository) {
    _subscription = repository.changes.listen(
      (_) {
        if (!_busy) unawaited(refresh());
      },
      onError: (Object error) {
        // SDK refresh failures must never become unhandled stream errors.
        if (!_busy) {
          _epoch++;
          status = AuthStatus.error;
          message = 'Unable to refresh your session. Check your connection and retry.';
          _notify();
        }
      },
    );
  }
  final AuthRepository repository;
  late final StreamSubscription<void> _subscription;
  AuthStatus status = AuthStatus.loading;
  String? message;
  AuthProfile? profile;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() => _run(() async {});
  Future<void> signIn(String email, String password) =>
      _run(() => repository.signIn(email, password));
  Future<void> complete(String name, String companyId) =>
      _run(() => repository.complete(name: name, companyId: companyId));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _disposed) return;
    _busy = true;
    final epoch = ++_epoch;
    status = AuthStatus.loading;
    profile = null;
    message = null;
    _notify();
    try {
      await action();
      if (_disposed || epoch != _epoch) return;
      if (!repository.hasSession) {
        status = AuthStatus.signedOut;
      } else {
        final profile = await repository.profile();
        if (_disposed || epoch != _epoch) return;
        // A sign-out event during a request must not restore dashboard access.
        status = !repository.hasSession
            ? AuthStatus.signedOut
            : profile.role == 'driver' &&
                  profile.approvalStatus == 'approved' &&
                  !profile.mfaVerified
            ? AuthStatus.mfa
            : profile.canEnter
            ? AuthStatus.approved
            : AuthStatus.blocked;
        if (status == AuthStatus.blocked) message = profile.statusMessage;
        // Retain driver identity for account-status feedback. The gate limits
        // payment-only access to approved profiles without opening the shell.
        if (status == AuthStatus.approved ||
            status == AuthStatus.mfa ||
            (status == AuthStatus.blocked && profile.role == 'driver')) {
          this.profile = profile;
        }
      }
    } on AuthFailure catch (error) {
      if (_disposed || epoch != _epoch) return;
      message = error.message;
      if (error.expired) {
        try {
          await repository.signOut();
        } catch (_) {
          /* Keep access closed. */
        }
        status = AuthStatus.signedOut;
      } else if (error.missingProfile) {
        status = AuthStatus.completion;
      } else {
        status = repository.hasSession
            ? AuthStatus.error
            : AuthStatus.signedOut;
      }
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      message = 'Unable to connect. Please try again.';
      status = repository.hasSession ? AuthStatus.error : AuthStatus.signedOut;
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> signOut() async {
    profile = null;
    // Invalidate a pending profile read before clearing the session.
    ++_epoch;
    _busy = true;
    status = AuthStatus.loading;
    message = null;
    _notify();
    try {
      await repository.signOut();
      status = AuthStatus.signedOut;
    } catch (_) {
      status = AuthStatus.error;
      message = 'Unable to sign out. Please try again.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _subscription.cancel();
    super.dispose();
  }
}
