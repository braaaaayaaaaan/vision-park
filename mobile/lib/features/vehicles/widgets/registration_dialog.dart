import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';

class RegistrationDialog extends StatefulWidget {
  const RegistrationDialog({this.onRegister, super.key});
  final Future<void> Function(String)? onRegister;

  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    // Match the backend's existing plate convention for connected submissions.
    _plate.text = _plate.text.trim().toUpperCase();
    setState(() => _submitted = true);
    if (widget.onRegister == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRegister!(_plate.text);
      if (mounted) Navigator.pop(context);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Registration could not be verified. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Register New Vehicle'),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New vehicles require administrator approval before parking access is granted.',
            ),
            const SizedBox(height: AppSpacing.medium),
            TextFormField(
              controller: _plate,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Number Plate',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              onChanged: (_) {
                if (_submitted) setState(() => _submitted = false);
              },
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a number plate.'
                  : widget.onRegister != null &&
                        !RegExp(r'^[A-Z0-9]{1,32}$')
                            .hasMatch(value.trim().toUpperCase())
                  ? 'Use 1–32 letters and digits only.'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(
              widget.onRegister != null
                  ? (_error ??
                        (_busy
                            ? 'Submitting Registration…'
                            : 'Your vehicle will be submitted for administrator approval.'))
                  : _submitted
                  ? 'Registration Unavailable. No vehicle has been registered. Please try again once parking services are connected.'
                  : 'Registration is not connected yet. Submitting this form will not register a vehicle.',
              semanticsLabel: _submitted && widget.onRegister == null
                  ? 'Registration Unavailable. No vehicle has been registered.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Submitting…' : 'Submit'),
        ),
      ],
    );
  }
}
