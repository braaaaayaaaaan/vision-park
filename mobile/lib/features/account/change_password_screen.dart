import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/password_change.dart';
import '../auth/form_validators.dart';
import '../auth/widgets/auth_layout.dart';
import '../auth/widgets/password_field.dart';
import 'widgets/account_confirmation.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({required this.service, super.key});
  final PasswordChangeService service;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _updating = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_current, _new, _confirm]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await confirmAccountAction(context, signOut: false) || !mounted) {
        return;
      }
      setState(() => _updating = true);
      await widget.service.change(_current.text, _new.text);
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      Navigator.of(context).pop(true);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to confirm the update. Please try signing in again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _updating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthLayout(
      maxWidth: 420,
      inlineHeading: true,
      icon: Icons.lock_outline_rounded,
      title: 'Change Password',
      description: 'Confirm your current password to set a new one.',
      onBack: _busy ? null : () => Navigator.pop(context),
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _current,
              label: 'Current Password',
              enabled: !_busy,
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your current password.'
                  : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _new,
              label: 'New Password',
              enabled: !_busy,
              validator: (value) =>
                  AuthFormValidators.changePassword(value) ??
                  (value == _current.text
                      ? 'Choose a different new password.'
                      : null),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              label: 'Confirm New Password',
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Confirm your new password.'
                  : value != _new.text
                  ? 'Passwords must match.'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Please Wait…' : 'Update Password'),
            ),
            if (_updating) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                semanticsLabel: 'Updating Password',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
