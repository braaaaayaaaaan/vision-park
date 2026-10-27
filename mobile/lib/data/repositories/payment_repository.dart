import '../models/payment_models.dart';
import 'auth_repository.dart';

abstract interface class PaymentRepository {
  String? get ownerId;
  Stream<void> get changes;
  Future<Map<String, dynamic>> send(
    String path, {
    String method = 'GET',
    Map<String, Object>? body,
    String? key,
  });
}

/// All reads/writes go through the existing verified-token transport. No
/// Supabase tables, balances, fees or session states are written by Flutter.
class RemotePaymentRepository implements PaymentRepository {
  RemotePaymentRepository(this.api);
  final RemoteAuthRepository api;
  @override
  String? get ownerId => api.identity.userId;
  @override
  Stream<void> get changes => api.changes;
  @override
  Future<Map<String, dynamic>> send(
    String path, {
    String method = 'GET',
    Map<String, Object>? body,
    String? key,
  }) async {
    final owner = ownerId;
    if (owner == null) {
      throw const AuthFailure('Sign in to view payments.', expired: true);
    }
    final result = await api.paymentAuthenticated(
      'payments/$path',
      method: method,
      body: body,
      idempotencyKey: key,
    );
    if (ownerId != owner) {
      throw const AuthFailure(
        'Your account changed. Reopen payments.',
        expired: true,
      );
    }
    try {
      final json = paymentMap(result);
      PaymentMeta(json);
      return json;
    } catch (_) {
      throw const AuthFailure(
        'Unable to read the payment response. Refresh to recover its status.',
      );
    }
  }
}

PaymentPage<T> paymentPage<T>(
  Map<String, dynamic> json,
  String name,
  T Function(Map<String, dynamic>) parse,
) {
  final items = (json[name] as List)
      .map((row) => parse(paymentMap(row)))
      .toList();
  final offset = paymentInt(json['offset']);
  final more = json['has_more'] as bool;
  if (more && items.isEmpty) throw const FormatException();
  return PaymentPage(List.unmodifiable(items), more, offset + items.length);
}
