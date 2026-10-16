import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/driver_repository.dart';

enum VehiclesStatus { disconnected, loading, ready, error }

enum VehicleFilter { all, approved, pending }

class VehiclesController extends ChangeNotifier {
  VehiclesController({this.repository});

  final DriverRepository? repository;
  VehiclesStatus status = VehiclesStatus.disconnected;
  List<DriverVehicle> vehicles = const [];
  VehicleFilter filter = VehicleFilter.all;
  bool _disposed = false;

  List<DriverVehicle> get filteredVehicles => vehicles
      .where(
        (vehicle) =>
            filter == VehicleFilter.all ||
            vehicle.registrationStatus == filter.name,
      )
      .toList();

  int count(String status) =>
      vehicles.where((v) => v.registrationStatus == status).length;

  void selectFilter(VehicleFilter value) {
    filter = value;
    notifyListeners();
  }

  Future<void> load() async {
    final repository = this.repository;
    if (repository == null || _disposed || status == VehiclesStatus.loading) {
      return;
    }
    status = VehiclesStatus.loading;
    vehicles = const [];
    notifyListeners();
    try {
      final result = await repository.getVehicles();
      if (_disposed) return;
      vehicles = List.unmodifiable(result);
      status = VehiclesStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = VehiclesStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
