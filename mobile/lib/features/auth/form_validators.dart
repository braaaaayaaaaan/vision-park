import 'dart:convert';

/// UI feedback mirrors registration policy; the backend remains authoritative.
abstract final class AuthFormValidators {
  static String? changePassword(String? value) {
    final error = registrationPassword(value);
    if (error != null) return error;
    // Hosted Auth uses bcrypt's 72-byte password limit (not 72 Unicode runes).
    if (utf8.encode(value!).length > 72) {
      return 'Use at most 72 bytes (fewer characters for some symbols).';
    }
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email.';
    if (email.length > 254 ||
        !RegExp(r'^[^\s@<>]+@[^\s@<>.]+(?:\.[^\s@<>.]+)+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? fullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your full name.';
    if (name.length > 150 || name.runes.any((character) => character < 32)) {
      return 'Enter a valid name of up to 150 characters.';
    }
    return null;
  }

  static String? loginPassword(String? value) =>
      value == null || value.isEmpty ? 'Enter your password.' : null;

  static String? registrationPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    if (value.runes.length < 8 || value.runes.length > 128) {
      return 'Use 8 to 128 characters.';
    }
    const symbols = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
    final missing = <String>[
      if (!RegExp(r'[A-Z]').hasMatch(value)) 'an uppercase letter',
      if (!RegExp(r'[a-z]').hasMatch(value)) 'a lowercase letter',
      if (!RegExp(r'[0-9]').hasMatch(value)) 'a number',
      if (!value.runes.any(
        (rune) => symbols.contains(String.fromCharCode(rune)),
      ))
        'a special character',
    ];
    if (missing.isNotEmpty) return 'Include ${missing.join(', ')}.';
    return null;
  }
}
