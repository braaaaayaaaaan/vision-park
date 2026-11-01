import 'package:flutter/foundation.dart';

import '../../data/models/dashboard_models.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/active_session_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/availability_repository.dart';
import 'allocation_notifications.dart';

enum HomeStatus { disconnected, loading, ready, error }

class HomeController extends ChangeNotifier {
  HomeController({
    this.repository,
    this.activeSessionRepository,
    this.availabilityRepository,
    AllocationNotifications? allocationNotifications,
  }) : allocationNotifications =
           allocationNotifications ?? AllocationNotifications();

  final AllocationNotifications allocationNotifications;
  int sessionRevision = 0;

  final AvailabilityRepository? availabilityRepository;
  HomeStatus availabilityStatus = HomeStatus.disconnected;
  ParkingAvailability? availability;
  String? availabilityError;
  bool availabilityExpired = false;
  DateTime? availabilityVerifiedAt;
  DateTime? sessionsVerifiedAt;
  bool get availabilityRefreshing => _availabilityLoading;
  bool get sessionsRefreshing => _sessionsLoading;
  Future<void>? _availabilityRead, _sessionRead;

  Future<void> refreshParking({
    bool background = false,
    bool afterChange = false,
  }) async {
    if (afterChange) {
      // Each section waits only for its own older read. Concurrent change
      // notifications then coalesce into one fresh read per section.
      await Future.wait([
        () async {
          await _sessionRead;
          await loadSessions(background: background);
        }(),
        () async {
          await _availabilityRead;
          await loadAvailability(background: background);
        }(),
      ]);
      return;
    }
    await Future.wait([
      loadSessions(background: background),
      loadAvailability(background: background),
    ]);
  }

  bool _availabilityLoading = false;
  bool _sessionsLoading = false;

  Future<void> loadAvailability({bool background = false}) {
    if (_availabilityRead != null) return _availabilityRead!;
    final work = _loadAvailability(background: background);
    _availabilityRead = work;
    return work.whenComplete(() => _availabilityRead = null);
  }

  Future<void> _loadAvailability({bool background = false}) async {
    final repository = availabilityRepository;
    if (repository == null || _availabilityLoading || _disposed) {
      return;
    }
    _availabilityLoading = true;
    final keepData = availabilityVerifiedAt != null;
    if (!keepData) {
      availabilityStatus = HomeStatus.loading;
      availability = null;
      availabilityError = null;
      availabilityExpired = false;
    }
    availabilityError = null;
    notifyListeners();
    try {
      final result = await repository.getAvailability();
      if (_disposed) return;
      availability = result;
      availabilityStatus = HomeStatus.ready;
      availabilityError = null;
      availabilityExpired = false;
      availabilityVerifiedAt = DateTime.now();
    } on AuthFailure catch (error) {
      if (_disposed) return;
      availabilityError = error.message;
      availabilityExpired = error.expired;
      if (!keepData || (!error.retryable && error.code != 'read_cancelled')) {
        availabilityStatus = HomeStatus.error;
        availability = null;
        availabilityVerifiedAt = null;
      }
    } catch (_) {
      if (_disposed) return;
      availabilityError = 'Unable to load parking availability. Check your connection and try again.';
      if (!keepData) availabilityStatus = HomeStatus.error;
    }
    _availabilityLoading = false;
    notifyListeners();
  }

  final DashboardRepository? repository;
  final ActiveSessionRepository? activeSessionRepository;
  HomeStatus sessionStatus = HomeStatus.disconnected;
  List<ActiveParking> activeSessions = const [];
  String? sessionError;
  bool sessionExpired = false;
  HomeStatus status = HomeStatus.disconnected;
  DashboardData? data;
  bool _disposed = false;

  Future<void> loadSessions({bool background = false}) {
    if (_sessionRead != null) return _sessionRead!;
    final work = _loadSessions(background: background);
    _sessionRead = work;
    return work.whenComplete(() => _sessionRead = null);
  }

  Future<void> _loadSessions({bool background = false}) async {
    final repository = activeSessionRepository;
    if (repository == null ||
        sessionStatus == HomeStatus.loading ||
        _disposed) {
      return;
    }
    _sessionsLoading = true;
    final keepData = sessionsVerifiedAt != null;
    if (!keepData) {
      sessionStatus = HomeStatus.loading;
      activeSessions = const [];
      sessionError = null;
      sessionExpired = false;
    }
    sessionError = null;
    notifyListeners();
    try {
      final sessions = await repository.getActiveSessions();
      if (_disposed) return;
      activeSessions = List.unmodifiable(sessions);
      allocationNotifications.update(activeSessions);
      sessionRevision++;
      sessionStatus = HomeStatus.ready;
      sessionError = null;
      sessionExpired = false;
      sessionsVerifiedAt = DateTime.now();
    } on AuthFailure catch (error) {
      if (_disposed) return;
      sessionError = error.message;
      sessionExpired = error.expired;
      if (!keepData || (!error.retryable && error.code != 'read_cancelled')) {
        sessionStatus = HomeStatus.error;
        activeSessions = const [];
        sessionsVerifiedAt = null;
      }
    } catch (_) {
      if (_disposed) return;
      sessionError = 'Unable to load active parking sessions. Check your connection and try again.';
      if (!keepData) sessionStatus = HomeStatus.error;
    }
    _sessionsLoading = false;
    notifyListeners();
  }

  Future<void> load() async {
    final repository = this.repository;
    if (repository == null || status == HomeStatus.loading || _disposed) return;

    status = HomeStatus.loading;
    data = null;
    notifyListeners();
    try {
      final result = await repository.getDashboard();
      if (_disposed) return;
      data = result;
      status = HomeStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = HomeStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
