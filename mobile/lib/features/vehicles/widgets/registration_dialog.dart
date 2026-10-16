import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

class RegistrationDialog extends StatefulWidget {
  const RegistrationDialog({super.key});

  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // Preserve internal spacing and punctuation; do not assume a plate pattern.
    _plate.text = _plate.text.trim().toUpperCase();
    setState(() => _submitted = true);
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
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(
              _submitted
                  ? 'Registration Unavailable. No vehicle has been registered. Please try again once parking services are connected.'
                  : 'Registration is not connected yet. Submitting this form will not register a vehicle.',
              semanticsLabel: _submitted
                  ? 'Registration Unavailable. No vehicle has been registered.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}
