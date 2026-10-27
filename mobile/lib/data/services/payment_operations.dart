import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Only retry identifiers and their immutable request payloads are persisted.
/// Never store credentials, personal labels, card data or authoritative balances.
abstract interface class PaymentOperationStore {
  Future<Map<String, dynamic>?> read(String owner, String operation);
  Future<void> write(
    String owner,
    String operation,
    Map<String, dynamic>? value,
  );
}

class PreferencesPaymentOperations implements PaymentOperationStore {
  String _name(String owner, String operation) =>
      'vp_payment_v1:$owner:$operation';
  @override
  Future<Map<String, dynamic>?> read(String owner, String operation) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_name(owner, operation));
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> write(
    String owner,
    String operation,
    Map<String, dynamic>? value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = value == null
        ? await prefs.remove(_name(owner, operation))
        : await prefs.setString(_name(owner, operation), jsonEncode(value));
    if (!saved) throw const FormatException('Unable to save retry state');
  }
}

String paymentKey() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
