import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/mfa.dart';

class MfaController extends ChangeNotifier {
  MfaController(this.service, {this.allowEnrollment = true});
  final MfaService service;
  final bool allowEnrollment;
  MfaSnapshot? state;
  MfaEnrollment? enrollment;
  String? selectedFactor;
  String? message;
  bool busy = false;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    _notify();
    try {
      final next = await service.inspect();
      if (_disposed) return;
      state = next;
      selectedFactor =
          enrollment?.id ??
          (next.verified.isEmpty ? null : next.verified.first.id);
    } on AuthFailure catch (error) {
      if (!_disposed) message = error.message;
    } catch (_) {
      if (!_disposed) {
        message = 'Unable to check your authenticator. Please retry.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> enroll() async {
    if (busy || _disposed || !allowEnrollment) return;
    busy = true;
    message = null;
    _notify();
    try {
      final pending = state?.pending ?? [];
      final next = await service.enroll(
        replaceUnverifiedId: pending.isEmpty ? null : pending.first.id,
      );
      if (_disposed) return;
      enrollment = next;
      selectedFactor = next.id;
    } on AuthFailure catch (error) {
      if (!_disposed) message = error.message;
      // A lost response may already have created the factor. Inspect once,
      // never automatically retry enrollment or delete a verified factor.
      try {
        final next = await service.inspect();
        if (!_disposed) state = next;
      } catch (_) {}
    } catch (_) {
      if (!_disposed) message = 'Setup could not be confirmed. Check the current setup before retrying.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> verify(String code) async {
    if (busy || _disposed || selectedFactor == null) return false;
    busy = true;
    message = null;
    _notify();
    try {
      await service.verify(selectedFactor!, code);
      if (_disposed) return false;
      final next = await service.inspect();
      if (_disposed) return false;
      state = next;
      if (!next.ready) {
        throw const AuthFailure(
          'Complete authenticator verification before continuing.',
        );
      }
      enrollment = null;
      return true;
    } on AuthFailure catch (error) {
      if (!_disposed) message = error.message;
      return false;
    } catch (_) {
      if (!_disposed) message = 'Verification could not be confirmed. Try the current code when connected.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void selectFactor(String? id) {
    if (busy || !(state?.verified.any((factor) => factor.id == id) ?? false)) {
      return;
    }
    selectedFactor = id;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    enrollment = null;
    super.dispose();
  }
}
