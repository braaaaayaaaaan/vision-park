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

  Future<void> refreshParking({bool background = false}) async {
    await Future.wait([
      loadSessions(background: background),
      loadAvailability(background: background),
    ]);
  }

  bool _availabilityLoading = false;
  bool _sessionsLoading = false;

  Future<void> loadAvailability({bool background = false}) async {
    final repository = availabilityRepository;
    if (repository == null || _availabilityLoading || _disposed) {
      return;
    }
    _availabilityLoading = true;
    final keepData = background && availabilityStatus == HomeStatus.ready;
    if (!background || availabilityStatus == HomeStatus.disconnected) {
      availabilityStatus = HomeStatus.loading;
      availability = null;
      availabilityError = null;
      availabilityExpired = false;
      notifyListeners();
    }
    try {
      final result = await repository.getAvailability();
      if (_disposed) return;
      availability = result;
      availabilityStatus = HomeStatus.ready;
      availabilityError = null;
      availabilityExpired = false;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      availabilityError = error.message;
      availabilityExpired = error.expired;
      availabilityStatus = HomeStatus.error;
      availability = null;
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
  bool _reloadSessions = false;

  Future<void> loadSessions({bool background = false}) async {
    final repository = activeSessionRepository;
    if (!_disposed && _sessionsLoading) {
      if (!background) _reloadSessions = true;
      return;
    }
    if (repository == null ||
        sessionStatus == HomeStatus.loading ||
        _disposed) {
      return;
    }
    _sessionsLoading = true;
    final keepData = background && sessionStatus == HomeStatus.ready;
    if (!background || sessionStatus == HomeStatus.disconnected) {
      sessionStatus = HomeStatus.loading;
      activeSessions = const [];
      sessionError = null;
      sessionExpired = false;
      notifyListeners();
    }
    try {
      final sessions = await repository.getActiveSessions();
      if (_disposed) return;
      activeSessions = List.unmodifiable(sessions);
      allocationNotifications.update(activeSessions);
      sessionRevision++;
      sessionStatus = HomeStatus.ready;
      sessionError = null;
      sessionExpired = false;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      sessionError = error.message;
      sessionExpired = error.expired;
      sessionStatus = HomeStatus.error;
      activeSessions = const [];
    } catch (_) {
      if (_disposed) return;
      sessionError = 'Unable to load active parking sessions. Check your connection and try again.';
      if (!keepData) sessionStatus = HomeStatus.error;
    }
    _sessionsLoading = false;
    notifyListeners();
    if (_reloadSessions) {
      _reloadSessions = false;
      await loadSessions();
    }
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
