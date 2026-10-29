import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import 'form_validators.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    required this.repository,
    required this.onBack,
    required this.onRegistered,
    this.onComplete,
    this.completion = false,
    this.message,
    super.key,
  });

  final AuthRepository repository;
  final VoidCallback onBack;
  final ValueChanged<String> onRegistered;
  final Future<void> Function(String name, String companyId)? onComplete;
  final bool completion;
  final String? message;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  List<AuthCompany> _companies = [];
  String? _companyId;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companies = await widget.repository.companies();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _companyId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is AuthFailure
            ? error.message
            : 'Unable to load companies. Please retry.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _email, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.completion) {
        await widget.onComplete!(_name.text, _companyId!);
      } else {
        await widget.repository.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          companyId: _companyId!,
        );
        if (mounted) {
          _password.clear();
          _confirmation.clear();
          widget.onRegistered(_email.text.trim());
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthFailure
              ? error.message
              : 'Unable to submit. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _backToLogin() {
    FocusScope.of(context).unfocus();
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    centered: true,
    title: widget.completion ? 'Complete Registration' : 'Create an Account',
    description: widget.completion
        ? 'Confirm your details to request company access.'
        : '',
    child: Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null || widget.message != null) ...[
            Semantics(liveRegion: true, child: Text(_error ?? widget.message!)),
            const SizedBox(height: AppSpacing.medium),
          ],
          TextFormField(
            controller: _name,
            enabled: !_submitting,
            autofillHints: const [AutofillHints.name],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: AuthFormValidators.fullName,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.completion) ...[
            TextFormField(
              controller: _email,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.email],
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
              enabled: !_submitting,
              label: 'Password',
              hintText: 'At least 8 characters',
              validator: AuthFormValidators.registrationPassword,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirmation,
              enabled: !_submitting,
              label: 'Confirm Password',
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Confirm your password.';
                }
                return value != _password.text ? 'Passwords must match.' : null;
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading Companies'),
          if (!_loading && _companies.isEmpty) ...[
            Text(
              _error == null
                  ? 'No companies are currently available.'
                  : 'Company List Unavailable',
            ),
            TextButton(
              onPressed: _loadCompanies,
              child: const Text('Retry Companies'),
            ),
          ],
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Company',
              errorMaxLines: 3,
            ),
            items: [
              for (final company in _companies)
                DropdownMenuItem(
                  value: company.id,
                  child: Text(company.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _loading || _submitting
                ? null
                : (value) => setState(() => _companyId = value),
            validator: (value) => value == null ? 'Select a company.' : null,
          ),
          const SizedBox(height: AppSpacing.small),
          const Text(
            'Company access requires administrator approval.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.large),
          FilledButton(
            onPressed: _loading || _submitting || _companies.isEmpty
                ? null
                : _submit,
            child: Text(
              _submitting
                  ? 'Submitting…'
                  : widget.completion
                  ? 'Complete Registration'
                  : 'Register',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _submitting ? null : _backToLogin,
            child: Text(widget.completion ? 'Sign Out' : 'Back to Login'),
          ),
        ],
      ),
    ),
  );
}
