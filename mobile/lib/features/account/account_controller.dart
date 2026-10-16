import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/driver_repository.dart';

enum AccountStatus { disconnected, loading, ready, error }

class AccountController extends ChangeNotifier {
  AccountController({this.repository});
  final DriverRepository? repository;
  AccountStatus status = AccountStatus.disconnected;
  DriverProfile? profile;
  List<DriverVehicle> vehicles = const [];
  bool _disposed = false;

  int count(String status) =>
      vehicles.where((vehicle) => vehicle.registrationStatus == status).length;

  Future<void> load() async {
    final repository = this.repository;
    if (repository == null || _disposed || status == AccountStatus.loading) {
      return;
    }
    status = AccountStatus.loading;
    profile = null;
    vehicles = const [];
    notifyListeners();
    try {
      final result = await repository.getProfile();
      if (_disposed) return;
      final registered = await repository.getVehicles();
      if (_disposed) return;
      profile = result;
      vehicles = List.unmodifiable(registered);
      status = AccountStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = AccountStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
