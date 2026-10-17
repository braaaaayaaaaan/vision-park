import 'package:flutter/foundation.dart';

import '../../data/models/dashboard_models.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/active_session_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/availability_repository.dart';

enum HomeStatus { disconnected, loading, ready, error }

class HomeController extends ChangeNotifier {
  HomeController({
    this.repository,
    this.activeSessionRepository,
    this.availabilityRepository,
  });

  final AvailabilityRepository? availabilityRepository;
  HomeStatus availabilityStatus = HomeStatus.disconnected;
  ParkingAvailability? availability;
  String? availabilityError;
  bool availabilityExpired = false;

  Future<void> refreshParking() async {
    await Future.wait([loadSessions(), loadAvailability()]);
  }

  Future<void> loadAvailability() async {
    final repository = availabilityRepository;
    if (repository == null ||
        availabilityStatus == HomeStatus.loading ||
        _disposed) {
      return;
    }
    availabilityStatus = HomeStatus.loading;
    availability = null;
    availabilityError = null;
    availabilityExpired = false;
    notifyListeners();
    try {
      final result = await repository.getAvailability();
      if (_disposed) return;
      availability = result;
      availabilityStatus = HomeStatus.ready;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      availabilityError = error.message;
      availabilityExpired = error.expired;
      availabilityStatus = HomeStatus.error;
    } catch (_) {
      if (_disposed) return;
      availabilityError = 'Unable to load parking availability. Check your connection and try again.';
      availabilityStatus = HomeStatus.error;
    }
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

  Future<void> loadSessions() async {
    final repository = activeSessionRepository;
    if (!_disposed && sessionStatus == HomeStatus.loading) {
      _reloadSessions = true;
      return;
    }
    if (repository == null ||
        sessionStatus == HomeStatus.loading ||
        _disposed) {
      return;
    }
    sessionStatus = HomeStatus.loading;
    activeSessions = const [];
    sessionError = null;
    sessionExpired = false;
    notifyListeners();
    try {
      final sessions = await repository.getActiveSessions();
      if (_disposed) return;
      activeSessions = List.unmodifiable(sessions);
      sessionStatus = HomeStatus.ready;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      sessionError = error.message;
      sessionExpired = error.expired;
      sessionStatus = HomeStatus.error;
    } catch (_) {
      if (_disposed) return;
      sessionError = 'Unable to load active parking sessions. Check your connection and try again.';
      sessionStatus = HomeStatus.error;
    }
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
