import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'form_validators.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onLogin,
    required this.onRegister,
    this.message,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback onRegister;
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

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
    title: 'Login',
    description: 'Welcome to VisionPark. Sign in to your driver account.',
    child: Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Semantics(liveRegion: true, child: Text(widget.message!)),
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
              border: OutlineInputBorder(),
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          PasswordField(
            controller: _password,
            label: 'Password',
            validator: AuthFormValidators.loginPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.large),
          FilledButton(onPressed: _submit, child: const Text('Login')),
          const SizedBox(height: AppSpacing.small),
          TextButton(
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
