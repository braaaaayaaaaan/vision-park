/// Display server-calculated money only. There is no fee calculation here.
String myr(int sen) =>
    'RM ${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';

Map<String, dynamic> paymentMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);
int paymentInt(dynamic value) {
  if (value is! int || value < 0) throw const FormatException();
  return value;
}

DateTime paymentTime(dynamic value) {
  final result = DateTime.parse(value as String);
  if (!result.isUtc || result.year < 1982) throw const FormatException();
  return result;
}

class PaymentMeta {
  PaymentMeta(Map<String, dynamic> json)
    : active = json['payment_mode'] == 'active',
      serverTime = paymentTime(json['server_time']) {
    if (json['simulated'] != true ||
        json['currency'] != 'MYR' ||
        !['active', 'inactive'].contains(json['payment_mode'])) {
      throw const FormatException();
    }
  }
  final bool active;
  final DateTime serverTime;
}

class DriverWallet {
  DriverWallet(Map<String, dynamic> json)
    : balance = paymentInt(json['balance_sen']),
      revision = paymentInt(json['preference_revision']),
      automatic = json['automatic_payment_enabled'] as bool;
  final int balance, revision;
  final bool automatic;
}

class WalletEntry {
  WalletEntry(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = json['entry_type'] as String,
      amount = paymentInt(json['amount_sen']),
      balanceAfter = paymentInt(json['balance_after_sen']),
      createdAt = paymentTime(json['created_at']),
      attemptId = json['payment_attempt_id'] as String? {
    if (!['mock_top_up', 'parking_debit'].contains(kind)) {
      throw const FormatException();
    }
  }
  final String id, kind;
  final String? attemptId;
  final int amount, balanceAfter;
  final DateTime createdAt;
}

class ParkingCharge {
  ParkingCharge(Map<String, dynamic> json)
    : id = json['id'] as String,
      sessionId = json['session_id'] as String,
      status = json['status'] as String,
      revision = paymentInt(json['quote_revision']),
      amount = json['amount_sen'] == null
          ? null
          : paymentInt(json['amount_sen']),
      session = paymentMap(json['session']),
      tariff = paymentMap(json['tariff']),
      calculation = paymentMap(json['calculation_snapshot']),
      expiresAt = json['quote_expires_at'] == null
          ? null
          : paymentTime(json['quote_expires_at']),
      throughAt = json['quoted_through_at'] == null
          ? null
          : paymentTime(json['quoted_through_at']),
      paidAt = json['paid_at'] == null ? null : paymentTime(json['paid_at']),
      exitAt = (json['session'] as Map)['exit_time'] == null
          ? null
          : paymentTime((json['session'] as Map)['exit_time']) {
    if (json['currency'] != 'MYR' ||
        !['open', 'pending', 'paid'].contains(status) ||
        session['id'] != sessionId) {
      throw const FormatException();
    }
  }
  final String id, sessionId, status;
  final int revision;
  final int? amount;
  final Map<String, dynamic> session, tariff, calculation;
  final DateTime? expiresAt, throughAt, paidAt, exitAt;
  String get plate =>
      (session['current_vehicle'] as Map?)?['plate_number'] as String? ??
      'Vehicle Unavailable';
  DateTime get entryTime => paymentTime(session['entry_time']);
  Duration? get duration => throughAt?.difference(entryTime);
}

class PaymentAttempt {
  PaymentAttempt(Map<String, dynamic> json)
    : id = json['id'] as String,
      chargeId = json['charge_id'] as String,
      status = json['status'] as String,
      method = json['method'] as String,
      reference = json['provider_reference'] as String,
      amount = paymentInt(json['amount_sen']),
      revision = paymentInt(json['quote_revision']),
      receiptNumber = json['receipt_number'] as String?,
      settledAt = json['settled_at'] == null
          ? null
          : paymentTime(json['settled_at']) {
    if (json['currency'] != 'MYR' ||
        ![
          'processing',
          'unknown',
          'succeeded',
          'declined',
          'failed',
        ].contains(status)) {
      throw const FormatException();
    }
  }
  final String id, chargeId, status, method, reference;
  final int amount, revision;
  final String? receiptNumber;
  final DateTime? settledAt;
  bool get inFlight => status == 'processing' || status == 'unknown';
}

class PaymentTransaction {
  PaymentTransaction(Map<String, dynamic> json)
    : charge = ParkingCharge(paymentMap(json['charge'])),
      attempt = PaymentAttempt(paymentMap(json['attempt'])) {
    if (attempt.chargeId != charge.id) throw const FormatException();
  }
  final ParkingCharge charge;
  final PaymentAttempt attempt;
  bool get isReceipt =>
      attempt.status == 'succeeded' &&
      charge.status == 'paid' &&
      charge.session['status'] == 'completed' &&
      attempt.receiptNumber != null &&
      attempt.settledAt != null &&
      attempt.settledAt == charge.paidAt &&
      attempt.settledAt == charge.exitAt &&
      attempt.amount == charge.amount &&
      attempt.revision == charge.revision;
}

class PaymentRequest {
  PaymentRequest(Map<String, dynamic> json)
    : meta = PaymentMeta(json),
      charge = ParkingCharge(paymentMap(json['charge'])),
      quoteState = json['quote_state'] as String,
      attempt = json['latest_attempt'] == null
          ? null
          : PaymentAttempt(paymentMap(json['latest_attempt']));
  final PaymentMeta meta;
  final ParkingCharge charge;
  final String quoteState;
  final PaymentAttempt? attempt;
}

class FictionalCard {
  FictionalCard(Map<String, dynamic> json)
    : id = json['id'] as String,
      label = json['label'] as String,
      lastFour = json['last_four'] as String,
      hint = json['hint'] as String;
  final String id, label, lastFour, hint;
}

class PaymentPage<T> {
  PaymentPage(this.items, this.hasMore, this.nextOffset);
  final List<T> items;
  final bool hasMore;
  final int nextOffset;
}
