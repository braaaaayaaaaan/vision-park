import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'mfa_controller.dart';
import 'widgets/auth_layout.dart';

class MfaScreen extends StatefulWidget {
  const MfaScreen({
    required this.controller,
    required this.onComplete,
    required this.onSignOut,
    this.recovery = false,
    super.key,
  });
  final MfaController controller;
  final Future<void> Function() onComplete;
  final Future<void> Function() onSignOut;
  final bool recovery;
  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  final _code = TextEditingController();
  bool _leaving = false;
  @override
  void dispose() {
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final verified = await widget.controller.verify(_code.text);
    if (!mounted) return;
    _code.clear();
    if (verified) await widget.onComplete();
  }

  Future<void> _leave() async {
    if (_leaving || widget.controller.busy) return;
    setState(() => _leaving = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final state = controller.state;
      final enrollment = controller.enrollment;
      final qrSvg = enrollment?.qrSvg;
      final verifying =
          enrollment != null || (state?.verified.isNotEmpty ?? false);
      final disabled = controller.busy || _leaving;
      return PopScope<void>(
        canPop: false,
        child: AuthLayout(
          centered: true,
          showBackButton: false,
          title: verifying
              ? 'Verify Your Authenticator'
              : 'Set Up Your Authenticator',
          description: widget.recovery
              ? 'Verify your authenticator to continue password recovery.'
              : 'Two-step verification is required to continue.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.busy) const LinearProgressIndicator(),
              if (enrollment != null) ...[
                if (qrSvg != null) ...[
                  const Text('Scan this QR code with your authenticator app.'),
                  const SizedBox(height: 12),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 248),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ColoredBox(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: SvgPicture.string(
                              qrSvg,
                              key: const ValueKey('mfa-enrollment-qr'),
                              semanticsLabel:
                                  'VisionPark authenticator setup QR code',
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                    child: Text('Use the setup key below.'),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Using an authenticator on this phone? Add the setup key below instead and select time-based codes.',
                  ),
                ] else
                  const Text(
                    'In your authenticator app, add an account using the setup key below. Select time-based codes.',
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    enrollment.secret,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Keep this setup key private. Enter a code below to finish enrollment.',
                ),
              ],
              if (verifying && state?.ready != true) ...[
                if (enrollment == null && state!.verified.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: controller.selectedFactor,
                    decoration: const InputDecoration(
                      labelText: 'Authenticator',
                    ),
                    items: [
                      for (final factor in state.verified)
                        DropdownMenuItem(
                          value: factor.id,
                          child: Text(factor.name),
                        ),
                    ],
                    onChanged: disabled ? null : controller.selectFactor,
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  enabled: !disabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Six-Digit Code',
                    counterText: '',
                  ),
                  onSubmitted: (_) {
                    if (!disabled) _verify();
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: disabled ? null : _verify,
                  child: const Text('Verify and Continue'),
                ),
              ] else if (state?.ready == true) ...[
                const Text('Your authenticator is verified.'),
                FilledButton(
                  onPressed: disabled ? null : widget.onComplete,
                  child: const Text('Continue'),
                ),
              ] else if (state != null && controller.allowEnrollment) ...[
                Text(
                  state.pending.isNotEmpty
                      ? 'An earlier setup was interrupted. Restart it for a new key, and remove the unfinished authenticator entry.'
                      : 'Use an authenticator app to generate your time-based verification codes.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: disabled ? null : controller.enroll,
                  child: Text(
                    state.pending.isEmpty ? 'Begin Setup' : 'Restart Setup',
                  ),
                ),
              ],
              if (controller.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    controller.message!,
                    semanticsLabel: controller.message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (state == null)
                OutlinedButton(
                  onPressed: disabled ? null : controller.load,
                  child: const Text('Retry'),
                ),
              const SizedBox(height: 16),
              const Text(
                'Lost your authenticator? Contact your VisionPark operator for identity-verified recovery.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: disabled ? null : _leave,
                child: Text(widget.recovery ? 'Return to Sign In' : 'Sign Out'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
