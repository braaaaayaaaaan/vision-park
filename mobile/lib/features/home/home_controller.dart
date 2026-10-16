import 'package:flutter/foundation.dart';

import '../../data/models/dashboard_models.dart';
import '../../data/repositories/dashboard_repository.dart';

enum HomeStatus { disconnected, loading, ready, error }

class HomeController extends ChangeNotifier {
  HomeController({this.repository});

  final DashboardRepository? repository;
  HomeStatus status = HomeStatus.disconnected;
  DashboardData? data;
  bool _disposed = false;

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
