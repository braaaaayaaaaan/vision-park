import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'email_verification_controller.dart';
import 'widgets/auth_layout.dart';

class EmailVerificationScreen extends StatelessWidget {
  const EmailVerificationScreen({
    required this.controller,
    required this.onContinue,
    required this.onSignInElsewhere,
    required this.onLeave,
    required this.hasSession,
    super.key,
  });
  final EmailVerificationController controller;
  final VoidCallback onContinue;
  final VoidCallback onSignInElsewhere;
  final VoidCallback onLeave;
  final bool hasSession;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    final verified = stage == VerificationStage.verified;
    final checking = stage == VerificationStage.checking;
    final failure = stage == VerificationStage.failure;
    final signInRequired = stage == VerificationStage.signInRequired;
    final colours = Theme.of(context).colorScheme;
    void goBack() {
      if (verified) {
        onContinue();
      } else if (failure) {
        controller.showWaiting();
      } else {
        onLeave();
      }
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !checking) {
          goBack();
        }
      },
      child: AuthLayout(
        inlineHeading: true,
        onBack: checking ? null : goBack,
        icon: verified
            ? Icons.mark_email_read_outlined
            : Icons.mail_outline_rounded,
        title: verified
            ? 'Email Verified'
            : checking
            ? 'Verifying Your Email'
            : signInRequired
            ? 'Continue to Sign In'
            : failure
            ? 'Unable to Verify Email'
            : 'Check Your Email',
        description: verified
            ? 'Your email is confirmed. Parking access still requires administrator approval.'
            : checking
            ? 'Please wait while we securely check your email confirmation.'
            : signInRequired
            ? 'Sign in to securely check your email confirmation and account status.'
            : failure
            ? 'Your account access has not changed. Follow the guidance below to continue.'
            : 'Confirm your email to continue your registration.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.email != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FE),
                  border: Border.all(color: const Color(0xFFDCE7F5)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email Address',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colours.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.email!,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.large),
            ],
            if (controller.message != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: failure
                      ? colours.errorContainer
                      : const Color(0xFFF4F8FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    controller.message!,
                    style: TextStyle(
                      color: failure
                          ? colours.onErrorContainer
                          : colours.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
            ],
            if (checking)
              const LinearProgressIndicator(semanticsLabel: 'Verifying Email'),
            if (verified) ...[
              FilledButton(
                onPressed: onContinue,
                child: Text(
                  controller.callbackHasSession
                      ? 'Continue'
                      : 'Continue to Sign In',
                ),
              ),
              if (controller.callbackHasSession)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.medium),
                  child: Text(
                    'Continuing to your account automatically…',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            if (signInRequired)
              FilledButton(
                onPressed: onSignInElsewhere,
                child: const Text('Continue to Sign In'),
              ),
            if (!verified && !checking && !signInRequired) ...[
              _EmailStep(
                number: '1',
                title: 'Open Your Inbox',
                description: controller.emailAppAvailable
                    ? 'Open your email app using the button below.'
                    : 'Open your email app manually on this device.',
              ),
              const SizedBox(height: 18),
              const _EmailStep(
                number: '2',
                title: 'Follow the Confirmation Link',
                description: 'Tap the link in the VisionPark email. Check spam if needed.',
              ),
              if (controller.emailAppAvailable) ...[
                const SizedBox(height: AppSpacing.large),
                FilledButton.icon(
                  onPressed: controller.openEmail,
                  icon: const Icon(Icons.mail_outline_rounded, size: 20),
                  label: const Text('Open Email App'),
                ),
              ],
              const SizedBox(height: AppSpacing.large),
              const Divider(),
              const SizedBox(height: AppSpacing.medium),
              Text(
                hasSession ? 'Already Signed In' : 'Already Confirmed?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                hasSession
                    ? 'Continue with the account signed in on this device.'
                    : 'Confirmed on another device, or already registered? Sign in here to check your account.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colours.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: hasSession ? onContinue : onSignInElsewhere,
                child: Text(
                  hasSession ? 'Continue to Account' : 'Continue to Sign In',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.number,
    required this.title,
    required this.description,
  });
  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
