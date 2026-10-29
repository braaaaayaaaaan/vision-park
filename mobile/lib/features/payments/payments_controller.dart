import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/payment_models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/services/payment_operations.dart';

class PaymentsController extends ChangeNotifier {
  PaymentsController(this.repository, this.operations)
    : owner = repository.ownerId {
    _subscription = repository.changes.listen((_) {
      if (!isCurrentOwner) {
        wallet = null;
        pending = [];
        entries = [];
        receipts = [];
        _notify();
      }
    });
  }
  final PaymentRepository repository;
  final PaymentOperationStore operations;
  final String? owner;
  late final StreamSubscription<void> _subscription;
  bool _disposed = false, loading = false, busy = false;
  Future<void>? _refreshing;
  bool active = false;
  String? error, actionMessage;
  bool actionSucceeded = false;
  DriverWallet? wallet;
  List<ParkingCharge> pending = [];
  List<WalletEntry> entries = [];
  List<PaymentTransaction> receipts = [];
  bool moreEntries = false, moreReceipts = false;
  int _entryOffset = 0, _receiptOffset = 0;
  Map<String, dynamic>? topUpOperation;
  bool get isCurrentOwner => owner != null && repository.ownerId == owner;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> send(
    String path, {
    String method = 'GET',
    Map<String, Object>? body,
    String? key,
  }) async {
    if (!isCurrentOwner || _disposed) {
      throw const AuthFailure('Sign in again to view payments.', expired: true);
    }
    final result = await repository.send(
      path,
      method: method,
      body: body,
      key: key,
    );
    if (!isCurrentOwner || _disposed) {
      throw const AuthFailure(
        'Your account changed. Reopen payments.',
        expired: true,
      );
    }
    return result;
  }

  String message(Object failure) => failure is AuthFailure
      ? failure.message
      : 'Unable to load payment details. Try again.';

  Future<void> refresh({bool history = false, bool background = false}) async {
    final current = _refreshing;
    if (current != null) {
      await current;
      if (!background && history && isCurrentOwner && !_disposed) {
        await refresh(history: true);
      }
      return;
    }
    if (!isCurrentOwner || _disposed || (background && busy)) return;
    final work = _refresh(history: history, background: background);
    _refreshing = work;
    try {
      await work;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refresh({
    required bool history,
    required bool background,
  }) async {
    loading = !background || wallet == null;
    error = null;
    _notify();
    try {
      final result = await send('wallet');
      final nextWallet = DriverWallet(paymentMap(result['wallet']));
      final charges = <ParkingCharge>[];
      var offset = 0;
      while (true) {
        final page = paymentPage(
          await send('requests?status=pending&limit=100&offset=$offset'),
          'charges',
          ParkingCharge.new,
        );
        charges.addAll(page.items);
        if (!page.hasMore) break;
        offset = page.nextOffset;
        if (offset > 1000000) throw const FormatException();
      }
      final saved = await operations.read(owner!, 'topup');
      if (!isCurrentOwner || _disposed) return;
      wallet = nextWallet;
      active = PaymentMeta(result).active;
      pending = charges;
      topUpOperation = saved;
      if (history) {
        await loadEntries(reset: true, preserveCount: background);
        await loadReceipts(reset: true, preserveCount: background);
      }
    } catch (failure) {
      error = message(failure);
    } finally {
      loading = false;
      _notify();
    }
  }

  bool _entriesLoading = false, _receiptsLoading = false;

  Future<void> loadEntries({
    bool reset = false,
    bool preserveCount = false,
  }) async {
    if (_entriesLoading || _disposed || !isCurrentOwner) return;
    _entriesLoading = true;
    try {
      final target = preserveCount ? entries.length : 0;
      final items = <WalletEntry>[];
      var offset = reset ? 0 : _entryOffset;
      late PaymentPage<WalletEntry> page;
      do {
        page = paymentPage(
          await send('wallet/transactions?limit=30&offset=$offset'),
          'entries',
          WalletEntry.new,
        );
        items.addAll(page.items);
        offset = page.nextOffset;
      } while (page.hasMore && items.length < target);
      entries = _merge(reset ? [] : entries, items, (item) => item.id);
      moreEntries = page.hasMore;
      _entryOffset = page.nextOffset;
    } catch (failure) {
      error = message(failure);
    } finally {
      _entriesLoading = false;
    }
    _notify();
  }

  Future<void> loadReceipts({
    bool reset = false,
    bool preserveCount = false,
  }) async {
    if (_receiptsLoading || _disposed || !isCurrentOwner) return;
    _receiptsLoading = true;
    try {
      final target = preserveCount ? receipts.length : 0;
      final items = <PaymentTransaction>[];
      var offset = reset ? 0 : _receiptOffset;
      late PaymentPage<PaymentTransaction> page;
      do {
        page = paymentPage(
          await send('receipts?limit=30&offset=$offset'),
          'receipts',
          PaymentTransaction.new,
        );
        if (page.items.any((item) => !item.isReceipt)) {
          throw const FormatException();
        }
        items.addAll(page.items);
        offset = page.nextOffset;
      } while (page.hasMore && items.length < target);
      receipts = _merge(
        reset ? [] : receipts,
        items,
        (item) => item.attempt.id,
      );
      moreReceipts = page.hasMore;
      _receiptOffset = page.nextOffset;
    } catch (failure) {
      error = message(failure);
    } finally {
      _receiptsLoading = false;
    }
    _notify();
  }

  List<T> _merge<T>(List<T> old, List<T> added, String Function(T) id) => {
    for (final item in [...old, ...added]) id(item): item,
  }.values.toList();

  Future<void> setAutomatic(bool value) async {
    if (busy || wallet == null) return;
    busy = true;
    actionMessage = null;
    actionSucceeded = false;
    _notify();
    try {
      await _refreshing;
      final result = await send(
        'wallet/preferences',
        method: 'PATCH',
        body: {
          'expected_revision': wallet!.revision,
          'automatic_payment_enabled': value,
        },
      );
      wallet = DriverWallet(paymentMap(result['wallet']));
      actionMessage = 'Successfully saved the payment method!';
      actionSucceeded = true;
    } catch (failure) {
      actionMessage = message(failure);
      await refresh();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> topUp(int amount) async {
    if (busy || !isCurrentOwner) return;
    busy = true;
    actionMessage = null;
    actionSucceeded = false;
    _notify();
    try {
      await _refreshing;
      // Read durable state first, including after app restart. A different amount
      // cannot replace an unconfirmed credit.
      topUpOperation = await operations.read(owner!, 'topup');
      final operation =
          topUpOperation ?? {'key': paymentKey(), 'amount_sen': amount};
      if (operation['amount_sen'] != amount) {
        throw const AuthFailure(
          'Check your previous top-up before choosing another amount.',
        );
      }
      await operations.write(owner!, 'topup', operation);
      topUpOperation = operation;
      final result = await send(
        'wallet/mock-top-ups',
        method: 'POST',
        key: operation['key'] as String,
        body: {'amount_sen': operation['amount_sen'] as int},
      );
      final entry = WalletEntry(paymentMap(result['entry']));
      if (result['status'] != 'credited' ||
          entry.amount != amount ||
          entry.kind != 'mock_top_up') {
        throw const FormatException();
      }
      await operations.write(owner!, 'topup', null);
      topUpOperation = null;
      actionMessage = 'Successful top-up to the account wallet!';
      actionSucceeded = true;
      await refresh(history: true);
    } catch (failure) {
      actionSucceeded = false;
      actionMessage =
          '${message(failure)} Retry this top-up to check the result.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

class CheckoutController extends ChangeNotifier {
  CheckoutController(this.payments, this.chargeId);
  final PaymentsController payments;
  final String chargeId;
  PaymentRequest? request;
  PaymentTransaction? receipt;
  List<FictionalCard> profiles = [];
  String? selectedProfile, error;
  bool busy = false, _disposed = false;
  Map<String, dynamic>? operation;
  Timer? _poll;
  Future<void>? _readingStatus;
  bool _paused = false;
  String get _operationName => 'checkout:$chargeId';
  PaymentAttempt? get attempt => request?.attempt;
  bool get unresolved => attempt?.inFlight == true || operation != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _readingStatus;
      await action();
    } catch (failure) {
      error = payments.message(failure);
    } finally {
      busy = false;
      _notify();
      _schedule();
    }
  }

  Future<void> load() => _guard(_load);
  Future<void> _load() async {
    operation = await payments.operations.read(payments.owner!, _operationName);
    request = PaymentRequest(await payments.send('requests/$chargeId'));
    if (request!.charge.id != chargeId) throw const FormatException();
    if (request!.charge.status == 'paid' || attempt?.status == 'succeeded') {
      await _receipt();
      return;
    }
    if (operation != null && operation!['method'] == 'card') {
      try {
        final recovered = PaymentTransaction(
          await payments.send('attempts/by-key/${operation!['key']}'),
        );
        if (recovered.charge.id != chargeId) throw const FormatException();
        if (!recovered.attempt.inFlight) {
          await payments.operations.write(
            payments.owner!,
            _operationName,
            null,
          );
          operation = null;
        }
        await _reloadAfterWrite();
      } on AuthFailure catch (failure) {
        if (failure.code != 'payment_not_found') rethrow;
      }
    }
    if (operation != null) {
      selectedProfile = operation!['card_profile'] as String?;
    }
    final data = await payments.send('gateway/card-profiles');
    profiles = (data['profiles'] as List)
        .map((row) => FictionalCard(paymentMap(row)))
        .toList();
    if (!profiles.any((profile) => profile.id == selectedProfile)) {
      selectedProfile = profiles.firstOrNull?.id;
    }
  }

  Future<void> _receipt() async {
    final id = attempt?.id;
    if (id == null) throw const FormatException();
    final value = PaymentTransaction(await payments.send('receipts/$id'));
    if (!value.isReceipt || value.charge.id != chargeId) {
      throw const FormatException();
    }
    receipt = value;
    await payments.operations.write(payments.owner!, _operationName, null);
    operation = null;
    await payments.refresh(history: true);
  }

  Future<void> _reloadAfterWrite() async {
    request = PaymentRequest(await payments.send('requests/$chargeId'));
    if (request!.charge.id != chargeId) throw const FormatException();
    if (request!.charge.status == 'paid') {
      await _receipt();
    } else if (attempt != null && !attempt!.inFlight) {
      await payments.operations.write(payments.owner!, _operationName, null);
      operation = null;
    }
  }

  void select(String? value) {
    if (!busy && !unresolved) {
      selectedProfile = value;
      _notify();
    }
  }

  Future<void> pay({bool wallet = false}) => _guard(() async {
    final current = request;
    if (current == null || !current.meta.active || receipt != null) return;
    if (attempt?.inFlight == true) {
      await _verify();
      return;
    }
    operation = await payments.operations.read(payments.owner!, _operationName);
    final saved =
        operation ??
        {
          'key': paymentKey(),
          'method': wallet ? 'wallet' : 'card',
          'quote_revision': current.charge.revision,
          if (!wallet) 'card_profile': selectedProfile,
        };
    if (saved['method'] == 'card' && saved['card_profile'] == null) {
      throw const AuthFailure('Select a test card.');
    }
    await payments.operations.write(payments.owner!, _operationName, saved);
    operation = saved;
    late PaymentTransaction result;
    try {
      result = PaymentTransaction(
        await payments.send(
          'requests/$chargeId/${saved['method'] == 'wallet' ? 'wallet-payment' : 'checkout'}',
          method: 'POST',
          key: saved['key'] as String,
          body: {
            'quote_revision': saved['quote_revision'] as int,
            if (saved['method'] == 'card')
              'card_profile': saved['card_profile'] as String,
          },
        ),
      );
    } on AuthFailure catch (failure) {
      // These definitive RPC rejections occur only after checking the original
      // idempotency key. No attempt was accepted; a fresh quote may be obtained.
      if ([
        'quote_expired',
        'stale_quote',
        'manual_required',
      ].contains(failure.code)) {
        await payments.operations.write(payments.owner!, _operationName, null);
        operation = null;
        await _load();
      }
      rethrow;
    }
    if (result.charge.id != chargeId) throw const FormatException();
    await _reloadAfterWrite();
  });
  Future<void> verify() => _guard(_verify);
  Future<void> _verify() async {
    final current = attempt;
    if (current == null) {
      await _load();
      return;
    }
    if (current.method == 'mock_card' && current.inFlight) {
      await payments.send(
        'attempts/${current.id}/${current.status == 'unknown' ? 'reconcile' : 'verify'}',
        method: 'POST',
        body: {},
      );
    }
    await _reloadAfterWrite();
  }

  Future<void> renew() => _guard(() async {
    // Never discard a lost write's key based solely on local quote time.
    if (unresolved) {
      throw const AuthFailure(
        'Check the current payment before renewing this quotation.',
      );
    }
    await payments.send(
      'requests/$chargeId/refresh-quote',
      method: 'POST',
      body: {'expected_revision': request!.charge.revision},
    );
    await _load();
  });
  void pause() {
    _paused = true;
    _poll?.cancel();
  }

  void resume() {
    _paused = false;
    unawaited(load());
  }

  Future<void> _pollStatus() async {
    if (busy || _disposed || _paused || !payments.isCurrentOwner) return;
    try {
      final next = PaymentRequest(await payments.send('requests/$chargeId'));
      if (_disposed || _paused) return;
      if (next.charge.id != chargeId) throw const FormatException();
      request = next;
      if (next.charge.status == 'paid') await _receipt();
      error = null;
    } catch (_) {
      // Retain the current checkout and retry a read. Never verify or pay here.
    } finally {
      _notify();
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (_disposed ||
        _paused ||
        !payments.isCurrentOwner ||
        request?.meta.active != true ||
        request?.charge.status != 'pending' ||
        receipt != null) {
      return;
    }
    // Read only. Payment verification/reconciliation remains an explicit action.
    _poll = Timer(
      Duration(seconds: attempt?.inFlight == true ? 5 : 15),
      () async {
        final work = _pollStatus();
        _readingStatus = work;
        try {
          await work;
        } finally {
          _readingStatus = null;
          if (!busy) _schedule();
        }
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }
}
