import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'form_validators.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onLogin,
    required this.onRegister,
    this.onForgotPassword,
    this.message,
    this.messageIsError = false,
    this.initialEmail,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback onRegister;
  final void Function(String email)? onForgotPassword;
  final String? message;
  final bool messageIsError;
  final String? initialEmail;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      await widget.onLogin(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    centered: true,
    title: 'Login',
    child: Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                widget.message!,
                style: widget.messageIsError
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
          ],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: AuthFormValidators.email,
            decoration: const InputDecoration(
              labelText: 'Email',
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _password,
            label: 'Password',
            validator: AuthFormValidators.loginPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (widget.onForgotPassword != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _password.clear();
                  FocusScope.of(context).unfocus();
                  widget.onForgotPassword!(_email.text);
                },
                child: const Text('Forgot Password?'),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _submit, child: const Text('Login')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _password.clear();
              FocusScope.of(context).unfocus();
              widget.onRegister();
            },
            child: const Text('Create an Account'),
          ),
        ],
      ),
    ),
  );
}
