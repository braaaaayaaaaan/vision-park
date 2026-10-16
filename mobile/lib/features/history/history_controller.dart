import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/driver_repository.dart';
import '../../shared/formatting/malaysian_date_time.dart';

enum HistoryStatus { disconnected, loading, ready, error }

class HistoryController extends ChangeNotifier {
  HistoryController({this.repository, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DriverRepository? repository;
  final DateTime Function() _clock;
  HistoryStatus status = HistoryStatus.disconnected;
  List<ParkingSession> sessions = const [];
  List<DriverVehicle> vehicles = const [];
  int days = 7;
  String? vehicleId;
  bool _disposed = false;

  List<ParkingSession> get filteredSessions {
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
    notifyListeners();
  }

  void selectVehicle(String? value) {
    vehicleId = value;
    notifyListeners();
  }

  /// Re-evaluates the calendar window at midnight or after app resumption.
  void refreshPeriod() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
