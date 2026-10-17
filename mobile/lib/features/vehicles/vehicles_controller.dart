import 'package:flutter/foundation.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/driver_repository.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../data/repositories/auth_repository.dart';

enum VehiclesStatus { disconnected, loading, ready, error }

enum VehicleFilter { all, approved, pending }

class VehiclesController extends ChangeNotifier {
  VehiclesController({this.repository, this.vehicleRepository});
  final VehicleRepository? vehicleRepository;
  bool submitting = false;
  String? message;
  String? notice;

  Future<void> register(String plate) async {
    if (submitting || _disposed || vehicleRepository == null) return;
    submitting = true;
    notifyListeners();
    try {
      await vehicleRepository!.register(plate);
      if (_disposed) return;
      notice = 'Vehicle registered. Administrator approval is pending.';
      filter = VehicleFilter.all;
      await load();
    } finally {
      submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    if (submitting || _disposed || vehicleRepository == null) return;
    if (!vehicles.any((v) => v.id == id && v.canRemove)) {
      throw const AuthFailure(
        'This vehicle cannot be removed. Refresh your vehicles.',
      );
    }
    submitting = true;
    notifyListeners();
    try {
      await vehicleRepository!.remove(id);
      if (_disposed) return;
      notice = 'Vehicle removed.';
      await load();
    } finally {
      submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

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
    if ((repository == null && vehicleRepository == null) ||
        _disposed ||
        status == VehiclesStatus.loading) {
      return;
    }
    status = VehiclesStatus.loading;
    vehicles = const [];
    message = null;
    notifyListeners();
    try {
      final result =
          await (vehicleRepository?.getVehicles() ?? repository!.getVehicles());
      if (_disposed) return;
      vehicles = List.unmodifiable(result);
      status = VehiclesStatus.ready;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      message = error.message;
      status = VehiclesStatus.error;
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
