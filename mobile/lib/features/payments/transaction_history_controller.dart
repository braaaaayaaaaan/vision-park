import 'package:flutter/foundation.dart';

import '../../data/models/payment_models.dart';
import '../../data/repositories/payment_repository.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import 'payments_controller.dart';

/// Owns the filtered ledger without changing the wallet's recent transactions.
class TransactionHistoryController extends ChangeNotifier {
  TransactionHistoryController(this.payments, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PaymentsController payments;
  final DateTime Function() _clock;
  List<WalletEntry> entries = const [];
  bool loading = false, refreshing = false, hasMore = false;
  String? error;
  int days = 0;
  DateTime? startDate, endDate;
  int _offset = 0, _request = 0;
  bool _disposed = false;

  DateTime get today {
    final local = _clock().toUtc().add(const Duration(hours: 8));
    return DateTime.utc(local.year, local.month, local.day);
  }

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> selectDays(int value) async {
    if (![0, 1, 3, 7, 30].contains(value)) return;
    days = value;
    startDate = endDate = null;
    _clear();
    await _read(reset: true);
  }

  Future<bool> selectRange(DateTime start, DateTime end) async {
    final first = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    if (first.isBefore(DateTime.utc(1982)) ||
        first.isAfter(last) ||
        last.isAfter(today) ||
        last.difference(first).inDays >= 90) {
      return false;
    }
    days = -1;
    startDate = first;
    endDate = last;
    _clear();
    await _read(reset: true);
    return true;
  }

  void _clear() {
    ++_request;
    entries = const [];
    _offset = 0;
    hasMore = false;
    loading = refreshing = false;
    error = null;
  }

  Future<void> refresh({bool background = false}) async {
    if (loading || refreshing) return;
    await _read(reset: true, preserveCount: true, background: background);
  }

  Future<void> loadMore() async {
    if (loading || refreshing || !hasMore) return;
    await _read(reset: false);
  }

  Future<void> _read({
    required bool reset,
    bool preserveCount = false,
    bool background = false,
  }) async {
    if (_disposed || !payments.isCurrentOwner) return;
    final request = ++_request;
    final first = days > 0
        ? today.subtract(Duration(days: days - 1))
        : startDate;
    final last = days > 0 ? today : endDate;
    final target = preserveCount ? entries.length : 0;
    loading = !background;
    refreshing = background;
    error = null;
    notifyListeners();
    try {
      final items = <WalletEntry>[];
      var offset = reset ? 0 : _offset;
      late PaymentPage<WalletEntry> page;
      do {
        final query = <String, String>{
          'limit': '30',
          'offset': '$offset',
          if (first != null) 'start_date': dateKey(first),
          if (last != null) 'end_date': dateKey(last),
        };
        page = paymentPage(
          await payments.send(
            'wallet/transactions?${Uri(queryParameters: query).query}',
          ),
          'entries',
          WalletEntry.new,
        );
        if (_disposed || request != _request || !payments.isCurrentOwner) {
          return;
        }
        // Boundaries use calendar days in Malaysia, including the entire end day.
        if (first != null && last != null) {
          final lower = first.subtract(const Duration(hours: 8));
          final upper = last
              .add(const Duration(days: 1))
              .subtract(const Duration(hours: 8));
          if (page.items.any(
            (entry) =>
                entry.createdAt.isBefore(lower) ||
                !entry.createdAt.isBefore(upper),
          )) {
            throw const FormatException();
          }
        }
        if (page.hasMore && (page.items.isEmpty || page.nextOffset <= offset)) {
          throw const FormatException();
        }
        items.addAll(page.items);
        offset = page.nextOffset;
      } while (page.hasMore && items.length < target);
      entries =
          {
            for (final entry in [
              ...(reset ? <WalletEntry>[] : entries),
              ...items,
            ])
              entry.id: entry,
          }.values.toList()..sort((a, b) {
            final order = b.createdAt.compareTo(a.createdAt);
            return order == 0 ? b.id.compareTo(a.id) : order;
          });
      _offset = page.nextOffset;
      hasMore = page.hasMore;
    } catch (failure) {
      if (_disposed || request != _request) return;
      if (!background || entries.isEmpty || !payments.isCurrentOwner) {
        error = payments.message(failure);
      }
    } finally {
      if (!_disposed && request == _request) {
        loading = refreshing = false;
        notifyListeners();
      }
    }
  }

  String dayLabel(DateTime instant) {
    final day = MalaysianDateTime.startOfDayUtc(instant)
        .add(const Duration(hours: 8));
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return MalaysianDateTime.format(instant).split(', ').first;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    super.dispose();
  }
}
