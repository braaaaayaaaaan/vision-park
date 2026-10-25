import 'package:flutter/material.dart';

import 'form_validators.dart';
import 'password_recovery_controller.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    required this.controller,
    required this.onReturnToSignIn,
    super.key,
  });
  final PasswordRecoveryController controller;
  final Future<void> Function() onReturnToSignIn;
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.controller.email);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (widget.controller.busy || _emailForm.currentState?.validate() != true) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.request(_email.text);
  }

  Future<void> _update() async {
    if (widget.controller.busy ||
        _passwordForm.currentState?.validate() != true) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.update(_password.text);
    if (!mounted) return;
    _password.clear();
    _confirmation.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final stage = controller.stage;
    final request =
        stage == RecoveryStage.request || stage == RecoveryStage.sending;
    final create =
        stage == RecoveryStage.ready || stage == RecoveryStage.updating;
    final updated = stage == RecoveryStage.updated;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !controller.busy) widget.onReturnToSignIn();
      },
      child: AuthLayout(
        inlineHeading: true,
        onBack: controller.busy
            ? null
            : () {
                widget.onReturnToSignIn();
              },
        icon: updated
            ? Icons.check_circle_outline
            : stage == RecoveryStage.checkEmail
            ? Icons.mark_email_unread_outlined
            : Icons.lock_reset_rounded,
        title: request
            ? 'Forgot Password'
            : create
            ? 'Create New Password'
            : updated
            ? 'Password Updated'
            : stage == RecoveryStage.checkEmail
            ? 'Check Your Email'
            : stage == RecoveryStage.checking
            ? 'Checking Reset Link'
            : 'Unable to Reset Password',
        description: request
            ? 'Request a reset link for your account.'
            : create
            ? 'Choose a new password for your VisionPark account.'
            : updated
            ? 'Your password has been updated. Sign in with your new password.'
            : stage == RecoveryStage.checkEmail
            ? 'If this address is eligible, a reset link may arrive.'
            : stage == RecoveryStage.checking
            ? 'Please wait while we securely check your reset link.'
            : 'Request a new link, then open it on the device where you requested it.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.message != null) ...[
              Semantics(liveRegion: true, child: Text(controller.message!)),
              const SizedBox(height: 16),
            ],
            if (stage == RecoveryStage.checkEmail) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.email,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check inbox and spam. Open the link on this device.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if ((request ||
                    stage == RecoveryStage.checkEmail ||
                    stage == RecoveryStage.failure) &&
                controller.cooldownSeconds > 0) ...[
              _RecoveryCooldown(seconds: controller.cooldownSeconds),
              const SizedBox(height: 16),
            ],
            if (request)
              Form(
                key: _emailForm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _email,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      validator: AuthFormValidators.email,
                      onFieldSubmitted: (_) => _request(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        errorMaxLines: 3,
                      ),
                    ),
                    if (controller.pendingRequest) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Starting over discards this request, so earlier links may stop working.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: controller.pendingRequest
                          ? controller.canStartOver
                                ? controller.startOver
                                : null
                          : controller.canSubmit
                          ? _request
                          : null,
                      child: Text(
                        controller.busy
                            ? 'Please Wait…'
                            : controller.pendingRequest
                            ? 'Start Over'
                            : 'Send Reset Link',
                      ),
                    ),
                  ],
                ),
              ),
            if (create)
              Form(
                key: _passwordForm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PasswordField(
                      controller: _password,
                      enabled: !controller.busy,
                      label: 'New Password',
                      hintText: 'At least 8 characters',
                      validator: AuthFormValidators.registrationPassword,
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _confirmation,
                      enabled: !controller.busy,
                      label: 'Confirm Password',
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _update(),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Confirm your password.'
                          : value != _password.text
                          ? 'Passwords must match.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: controller.busy ? null : _update,
                      child: Text(
                        controller.busy ? 'Updating…' : 'Update Password',
                      ),
                    ),
                  ],
                ),
              ),
            if (stage == RecoveryStage.checking)
              const LinearProgressIndicator(
                semanticsLabel: 'Checking Reset Link',
              ),
            if (stage == RecoveryStage.checkEmail) ...[
              FilledButton.icon(
                onPressed: () {
                  _email.text = controller.email;
                  controller.showRequest(controller.email);
                },
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('Review Pending Request'),
              ),
              const SizedBox(height: 12),
            ],
            if (stage == RecoveryStage.failure)
              FilledButton(
                onPressed: () {
                  _email.text = controller.email;
                  controller.showRequest(controller.email);
                },
                child: const Text('Request New Link'),
              ),
            if (!controller.busy && !create) ...[
              if (request || stage == RecoveryStage.failure)
                const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  widget.onReturnToSignIn();
                },
                child: const Text('Back to Sign In'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecoveryCooldown extends StatelessWidget {
  const _RecoveryCooldown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Retry available in $seconds seconds',
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (seconds / 60).clamp(0.0, 1.0),
                        strokeWidth: 3,
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                    Text(
                      remaining,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retry Cooldown', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Email limits may mean a longer wait.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
