import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/form_validators.dart';
import '../repositories/auth_repository.dart';

abstract interface class PasswordChangeService {
  Future<void> change(String currentPassword, String newPassword);
}

/// Reauthentication uses a short-lived SDK client without session persistence.
/// It never replaces the application's session or writes application records.
class SupabasePasswordChangeService implements PasswordChangeService {
  SupabasePasswordChangeService(this.client, this.createReauthenticationClient);

  final SupabaseClient client;
  final SupabaseClient Function() createReauthenticationClient;
  bool _busy = false;

  @override
  Future<void> change(String currentPassword, String newPassword) async {
    if (_busy) {
      throw const AuthFailure('A password update is already in progress.');
    }
    final validation = AuthFormValidators.changePassword(newPassword);
    if (validation != null) throw AuthFailure(validation);
    if (currentPassword.isEmpty) {
      throw const AuthFailure('Enter your current password.');
    }
    if (currentPassword == newPassword) {
      throw const AuthFailure('Choose a different new password.');
    }
    _busy = true;
    SupabaseClient? temporary;
    var updating = false;
    try {
      final id = client.auth.currentSession?.user.id;
      if (id == null) {
        throw const AuthFailure('Sign in again to change your password.');
      }
      final user = (await client.auth.getUser()).user;
      if (user == null ||
          user.id != id ||
          user.email == null ||
          user.emailConfirmedAt == null) {
        throw const AuthFailure('Sign in again to confirm your account.');
      }
      temporary = createReauthenticationClient();
      final verified = await temporary.auth.signInWithPassword(
        email: user.email!,
        password: currentPassword,
      );
      if (verified.session == null ||
          verified.user?.id != id ||
          verified.user?.emailConfirmedAt == null ||
          client.auth.currentSession?.user.id != id) {
        throw const AuthFailure('Your session changed. Sign in again.');
      }
      updating = true;
      final result = await temporary.auth.updateUser(
        UserAttributes(password: newPassword, currentPassword: currentPassword),
      );
      if (result.user?.id != id) {
        throw const AuthFailure(
          'The password update could not be confirmed. Sign in again.',
        );
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) {
        throw AuthFailure(
          updating
              ? 'The update could not be confirmed. Try signing in with your new password.'
              : 'Unable to connect. Check your connection and try again.',
        );
      }
      throw AuthFailure(switch (error.code) {
        'invalid_credentials' || 'current_password_mismatch' =>
          'Current password is incorrect.',
        'same_password' => 'Choose a different new password.',
        'weak_password' =>
          'Choose a stronger password that meets the requirements.',
        'over_request_rate_limit' =>
          'Too many attempts. Please wait and try again.',
        'reauthentication_needed' || 'reauthentication_not_valid' =>
          'Sign in again before changing your password.',
        _ =>
          'Unable to change your password. Check your details and try again.',
      });
    } catch (_) {
      throw AuthFailure(
        updating
            ? 'The update could not be confirmed. Try signing in with your new password.'
            : 'Unable to connect. Check your connection and try again.',
      );
    } finally {
      try {
        if (temporary != null) {
          try {
            await temporary.auth.signOut(scope: SignOutScope.local);
          } catch (_) {
            // No persistent storage; never turn a confirmed update into failure.
          }
          try {
            await temporary.dispose();
          } catch (_) {
            // SDK cleanup must not mask the server's password-update result.
          }
        }
      } finally {
        _busy = false;
      }
    }
  }
}
