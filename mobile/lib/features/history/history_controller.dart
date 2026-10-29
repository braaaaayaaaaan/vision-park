import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/driver_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../shared/formatting/malaysian_date_time.dart';

enum HistoryStatus { disconnected, loading, ready, error }

class HistoryController extends ChangeNotifier {
  HistoryController({
    this.repository,
    this.historyRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DriverRepository? repository;
  final HistoryRepository? historyRepository;
  String? nextCursor;
  String? message;
  bool loadingMore = false;
  int? _total;
  int _request = 0;
  DateTime? _loadedDay;
  int get totalSessions => _total ?? filteredSessions.length;
  bool get summaryComplete => nextCursor == null && !loadingMore;
  final DateTime Function() _clock;
  HistoryStatus status = HistoryStatus.disconnected;
  List<ParkingSession> sessions = const [];
  List<DriverVehicle> vehicles = const [];
  int days = 7;
  String? vehicleId;
  bool _disposed = false;
  bool _refreshing = false;

  /// Re-read the loaded window, retaining filters and the number of visible rows.
  Future<void> refreshInBackground() async {
    if (_disposed ||
        _refreshing ||
        loadingMore ||
        status == HistoryStatus.loading ||
        historyRepository == null) {
      return;
    }
    _refreshing = true;
    final request = ++_request;
    final target = sessions.length;
    final records = <ParkingSession>[];
    String? cursor;
    try {
      HistoryPage? latest;
      do {
        final page = await historyRepository!.getHistory(
          days: days,
          vehicleId: vehicleId,
          cursor: cursor,
        );
        if (_disposed || request != _request) return;
        if ((latest != null && latest.totalSessions != page.totalSessions) ||
            (page.nextCursor != null &&
                (page.nextCursor == cursor || page.sessions.isEmpty))) {
          throw const FormatException();
        }
        latest = page;
        records.addAll(page.sessions);
        cursor = page.nextCursor;
      } while (cursor != null && records.length < target);
      if (records.map((item) => item.id).toSet().length != records.length ||
          (cursor == null && records.length != latest.totalSessions)) {
        throw const FormatException();
      }
      sessions = List.unmodifiable(records);
      vehicles = latest.vehicles;
      _total = latest.totalSessions;
      nextCursor = cursor;
      _loadedDay = MalaysianDateTime.startOfDayUtc(_clock());
      status = HistoryStatus.ready;
      message = null;
    } on AuthFailure catch (error) {
      if (_disposed || request != _request) return;
      sessions = const [];
      vehicles = const [];
      _total = null;
      nextCursor = null;
      status = HistoryStatus.error;
      message = error.message;
    } catch (_) {
      // Keep the last successful snapshot and retry on the next visible tick.
    } finally {
      _refreshing = false;
      if (!_disposed && request == _request) notifyListeners();
    }
  }

  List<ParkingSession> get filteredSessions {
    if (historyRepository != null) return sessions;
    final today = MalaysianDateTime.startOfDayUtc(_clock());
    final start = today.subtract(Duration(days: days - 1));
    final end = today.add(const Duration(days: 1));
    final filtered = sessions
        .where(
          (session) =>
              !session.entryTime.isBefore(start) &&
              session.entryTime.isBefore(end) &&
              (vehicleId == null || session.vehicleId == vehicleId),
        )
        .toList();
    filtered.sort((a, b) {
      final time = b.entryTime.compareTo(a.entryTime);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    return filtered;
  }

  static Duration? durationOf(ParkingSession session) {
    final exit = session.exitTime;
    if (exit == null || exit.isBefore(session.entryTime)) return null;
    return exit.difference(session.entryTime);
  }

  Duration? get averageDuration {
    if (!summaryComplete) return null;
    final durations = filteredSessions
        .where((session) => session.status == ParkingSessionStatus.completed)
        .map(durationOf)
        .whereType<Duration>()
        .toList();
    if (durations.isEmpty) return null;
    final total = durations.fold<int>(
      0,
      (sum, item) => sum + item.inMicroseconds,
    );
    return Duration(microseconds: (total / durations.length).round());
  }

  String plateFor(ParkingSession session) {
    if (session.plateNumber?.trim().isNotEmpty == true) {
      return session.plateNumber!;
    }
    for (final vehicle in vehicles) {
      if (vehicle.id == session.vehicleId) return vehicle.plateNumber;
    }
    return 'Number Plate Unavailable';
  }

  void selectDays(int value) {
    if (![1, 3, 7].contains(value)) return;
    days = value;
    if (historyRepository != null) {
      load();
      return;
    }
    notifyListeners();
  }

  void selectVehicle(String? value) {
    vehicleId = value;
    if (historyRepository != null) {
      load();
      return;
    }
    notifyListeners();
  }

  /// Re-evaluates the calendar window at midnight or after app resumption.
  void refreshPeriod() {
    if (historyRepository != null &&
        _loadedDay != MalaysianDateTime.startOfDayUtc(_clock())) {
      load();
      return;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (historyRepository != null) {
      await _loadRemote();
      return;
    }
    final repository = this.repository;
    if (repository == null || _disposed || status == HistoryStatus.loading) {
      return;
    }
    status = HistoryStatus.loading;
    sessions = const [];
    vehicles = const [];
    notifyListeners();
    try {
      final registered = await repository.getVehicles();
      if (_disposed) return;
      final records = <ParkingSession>[];
      while (true) {
        final page = await repository.getParkingHistory(
          offset: records.length,
          limit: 100,
        );
        if (_disposed) return;
        if (page.isEmpty) break;
        records.addAll(page);
      }
      vehicles = List.unmodifiable(registered);
      sessions = List.unmodifiable(records);
      if (!vehicles.any((v) => v.id == vehicleId)) vehicleId = null;
      status = HistoryStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = HistoryStatus.error;
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (nextCursor == null ||
        loadingMore ||
        _refreshing ||
        status != HistoryStatus.ready) {
      return;
    }
    await _loadRemote(more: true);
  }

  Future<void> _loadRemote({bool more = false}) async {
    if (_disposed) return;
    final request = ++_request;
    final cursor = more ? nextCursor : null;
    message = null;
    loadingMore = more;
    if (!more) {
      status = HistoryStatus.loading;
      sessions = const [];
      nextCursor = null;
      _total = null;
    }
    notifyListeners();
    try {
      final page = await historyRepository!.getHistory(
        days: days,
        vehicleId: vehicleId,
        cursor: cursor,
      );
      if (_disposed || request != _request) return;
      if (vehicleId != null && !page.vehicles.any((v) => v.id == vehicleId)) {
        vehicleId = null;
        await load();
        return;
      }
      final combined = more ? [...sessions, ...page.sessions] : page.sessions;
      final ids = combined.map((s) => s.id).toSet();
      if (ids.length != combined.length ||
          (more && _total != page.totalSessions) ||
          (page.nextCursor != null &&
              (page.nextCursor == cursor || page.sessions.isEmpty)) ||
          (page.nextCursor == null && combined.length != page.totalSessions)) {
        throw const AuthFailure(
          'History changed while loading. Refresh to view the latest records.',
        );
      }
      sessions = List.unmodifiable(combined);
      vehicles = page.vehicles;
      _total = page.totalSessions;
      nextCursor = page.nextCursor;
      _loadedDay = MalaysianDateTime.startOfDayUtc(_clock());
      status = HistoryStatus.ready;
    } catch (error) {
      if (_disposed || request != _request) return;
      // Never retain another page's private records after an authorization failure.
      sessions = const [];
      _total = null;
      nextCursor = null;
      status = HistoryStatus.error;
      vehicles = const [];
      vehicleId = null;
      message = error is AuthFailure
          ? error.message
          : 'Your history could not be loaded. Please try again.';
    }
    loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
