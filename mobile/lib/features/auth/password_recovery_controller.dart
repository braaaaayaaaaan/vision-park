import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/password_recovery.dart';
import 'form_validators.dart';

enum RecoveryStage {
  idle,
  request,
  sending,
  checkEmail,
  checking,
  ready,
  updating,
  updated,
  failure,
}

class PasswordRecoveryController extends ChangeNotifier {
  PasswordRecoveryController({this.service, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _initialization = _restoreRequestState();
  }
  final PasswordRecoveryService? service;
  final DateTime Function() _now;
  late final Future<void> _initialization;
  RecoveryRequestState _requestState = const RecoveryRequestState();
  bool loadingRequestState = true;
  bool _stateUnavailable = false;
  bool _startingOver = false;
  Timer? _cooldownTimer;
  String? _queuedLink;
  bool _queuedHasApplicationSession = false;
  RecoveryStage stage = RecoveryStage.idle;
  String email = '';
  String? message;
  String? _activeLink;
  bool _disposed = false;
  bool _leaving = false;
  bool get busy =>
      _leaving ||
      _startingOver ||
      {
        RecoveryStage.sending,
        RecoveryStage.checking,
        RecoveryStage.updating,
      }.contains(stage);
  bool get pendingRequest => _requestState.pending;
  int get cooldownSeconds {
    final milliseconds =
        _requestState.availableAt?.difference(_now()).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  bool get canSubmit =>
      !busy &&
      !loadingRequestState &&
      !_stateUnavailable &&
      !pendingRequest &&
      cooldownSeconds == 0;
  bool get canStartOver =>
      !busy &&
      !loadingRequestState &&
      !_stateUnavailable &&
      pendingRequest &&
      cooldownSeconds == 0;

  Future<void> _restoreRequestState() async {
    loadingRequestState = true;
    try {
      _requestState =
          await service?.requestState() ?? const RecoveryRequestState();
      _stateUnavailable = false;
    } catch (_) {
      _stateUnavailable = true;
      message =
          'Unable to read the pending request safely. Please try again later.';
    } finally {
      loadingRequestState = false;
      _startCooldownTimer();
      _notify();
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    if (_disposed || cooldownSeconds == 0 || stage == RecoveryStage.idle) {
      return;
    }
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (cooldownSeconds == 0) _cooldownTimer?.cancel();
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void showRequest([String initialEmail = '']) {
    if (busy) return;
    email = initialEmail.trim();
    message = _stateUnavailable
        ? 'Unable to read the pending request safely. Please restart the app and try again.'
        : null;
    stage = RecoveryStage.request;
    _startCooldownTimer();
    _notify();
  }

  Future<void> startOver() async {
    await _initialization;
    if (!canStartOver || service == null) return;
    _startingOver = true;
    message = null;
    _notify();
    try {
      await service!.startOver();
      _activeLink = null;
      stage = RecoveryStage.request;
    } on AuthFailure catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Unable to start over safely. Please try again later.';
    } finally {
      await _restoreRequestState();
      _startingOver = false;
      _notify();
    }
  }

  Future<void> request(String value) async {
    if (busy) return;
    final error = AuthFormValidators.email(value);
    if (error != null) {
      message = error;
      _notify();
      return;
    }
    email = value.trim();
    stage = RecoveryStage.sending;
    message = null;
    _notify();
    var attempted = false;
    try {
      await _initialization;
      if (_stateUnavailable || pendingRequest || cooldownSeconds > 0) {
        throw const AuthFailure(SupabasePasswordRecoveryService.requestWait);
      }
      if (service == null) {
        throw const AuthFailure(
          'Password recovery is unavailable. Please try again later.',
        );
      }
      attempted = true;
      await service!.request(email);
      if (_disposed) return;
      stage = RecoveryStage.checkEmail;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      message = error.message;
      stage = RecoveryStage.request;
    } catch (_) {
      if (_disposed) return;
      message = 'Unable to connect. Please try again.';
      stage = RecoveryStage.request;
    } finally {
      if (attempted) {
        await _restoreRequestState();
        // Retain an in-memory deadline if the final persistence write failed.
        final deadline = _now().add(const Duration(seconds: 60));
        if (_requestState.availableAt == null ||
            _requestState.availableAt!.isBefore(deadline)) {
          _requestState = RecoveryRequestState(
            pending: true,
            availableAt: deadline,
          );
        }
        _startCooldownTimer();
      }
    }
    _notify();
    final queued = _queuedLink;
    _queuedLink = null;
    if (!_disposed && queued != null) {
      await handleLink(
        queued,
        hasApplicationSession: _queuedHasApplicationSession,
      );
    }
  }

  Future<void> handleLink(
    String link, {
    bool hasApplicationSession = false,
  }) async {
    // Native callbacks are consumed once. Keep one while a request is sending
    // rather than losing it during a slow/ambiguous HTTP response.
    if (!_disposed && stage == RecoveryStage.sending) {
      _queuedLink = link;
      _queuedHasApplicationSession = hasApplicationSession;
      return;
    }
    if (_disposed ||
        busy ||
        (_activeLink == link && stage == RecoveryStage.ready)) {
      return;
    }
    stage = RecoveryStage.checking;
    message = null;
    _notify();
    try {
      if (hasApplicationSession) {
        throw const AuthFailure(
          'Sign out of your current account before opening a password reset link.',
        );
      }
      if (service == null) {
        throw const AuthFailure(
          'Password recovery is unavailable. Please try again later.',
        );
      }
      email = await service!.establish(Uri.parse(link));
      if (_disposed) return;
      await _restoreRequestState();
      if (_disposed) return;
      _activeLink = link;
      stage = RecoveryStage.ready;
      _cooldownTimer?.cancel();
    } on AuthFailure catch (error) {
      if (_disposed) return;
      message = error.message;
      stage = RecoveryStage.failure;
    } catch (_) {
      if (_disposed) return;
      message = SupabasePasswordRecoveryService.invalidLink;
      stage = RecoveryStage.failure;
    }
    _notify();
  }

  Future<bool> update(String password) async {
    if (stage != RecoveryStage.ready || service == null) return false;
    final error = AuthFormValidators.registrationPassword(password);
    if (error != null) {
      message = error;
      _notify();
      return false;
    }
    stage = RecoveryStage.updating;
    message = null;
    _notify();
    try {
      await service!.update(password);
      if (_disposed) return false;
      stage = RecoveryStage.updated;
      _notify();
      return true;
    } on AuthFailure catch (error) {
      if (_disposed) return false;
      message = error.message;
    } catch (_) {
      if (_disposed) return false;
      message =
          'The update could not be confirmed. Request a fresh reset link.';
    }
    stage = RecoveryStage.failure;
    _notify();
    return false;
  }

  Future<void> leave() async {
    if (busy) return;
    _leaving = true;
    _notify();
    try {
      await service?.end();
      if (_disposed) return;
      stage = RecoveryStage.idle;
      _cooldownTimer?.cancel();
      message = null;
    } finally {
      _leaving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    final recoveryService = service;
    if (recoveryService != null) {
      unawaited(recoveryService.end().whenComplete(recoveryService.dispose));
    }
    super.dispose();
  }
}
