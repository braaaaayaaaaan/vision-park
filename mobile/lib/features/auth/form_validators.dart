/// Basic UI checks only. The future backend remains authoritative.
abstract final class AuthFormValidators {
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
    if (value.length < 12 || value.length > 128) {
      return 'Use 12 to 128 characters.';
    }
    return null;
  }
}
