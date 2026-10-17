import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscured,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: '${_obscured ? 'Show' : 'Hide'} ${widget.label}',
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
