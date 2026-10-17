import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'vehicles_controller.dart';
import 'widgets/registration_dialog.dart';
import 'widgets/vehicle_card.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({
    this.controller,
    this.vehicleRepository,
    this.isVisible = true,
    super.key,
  });
  final VehiclesController? controller;
  final VehicleRepository? vehicleRepository;
  final bool isVisible;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late final VehiclesController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        VehiclesController(vehicleRepository: widget.vehicleRepository);
    if (widget.isVisible) _controller.load();
  }

  @override
  void didUpdateWidget(covariant VehiclesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && !_controller.submitting) {
      _controller.load();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final ready = _controller.status == VehiclesStatus.ready;
        return SingleChildScrollView(
          key: const PageStorageKey('my-vehicles'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('My Vehicles', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.small),
                    const Text('Manage Your Registered Vehicles'),
                    if (_controller.vehicleRepository != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Refresh Vehicles',
                          onPressed:
                              _controller.submitting ||
                                  _controller.status == VehiclesStatus.loading
                              ? null
                              : _controller.load,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ),
                    if (_controller.notice != null) Text(_controller.notice!),
                    if (_controller.submitting)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Saving Vehicle',
                      ),
                    const SizedBox(height: AppSpacing.large),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.large),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: AppSpacing.large,
                              runSpacing: AppSpacing.medium,
                              children: [
                                Text(
                                  'Approved Vehicles: ${ready ? _controller.count('approved') : 'Unavailable'}',
                                ),
                                Text(
                                  'Pending Approval: ${ready ? _controller.count('pending') : 'Unavailable'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.large),
                            FilledButton(
                              onPressed:
                                  _controller.submitting ||
                                      _controller.status ==
                                          VehiclesStatus.loading
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      barrierDismissible:
                                          _controller.vehicleRepository == null,
                                      builder: (_) => RegistrationDialog(
                                        onRegister:
                                            _controller.vehicleRepository ==
                                                null
                                            ? null
                                            : _controller.register,
                                      ),
                                    ),
                              child: const Text('Register New Vehicle'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Wrap(
                      spacing: AppSpacing.small,
                      runSpacing: AppSpacing.small,
                      children: [
                        for (final (filter, label) in [
                          (VehicleFilter.all, 'All'),
                          (VehicleFilter.approved, 'Approved'),
                          (VehicleFilter.pending, 'Pending'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _controller.filter == filter,
                            onSelected: ready
                                ? (_) => _controller.selectFilter(filter)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    if (_controller.status == VehiclesStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Vehicles',
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      const Text('Loading Vehicles'),
                    ] else if (_controller.status == VehiclesStatus.error) ...[
                      EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Vehicles',
                        message: _controller.message ?? 'Vehicle information could not be confirmed. Please try again.',
                      ),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Try Again'),
                      ),
                    ] else if (!ready)
                      const EmptyStateCard(
                        icon: Icons.directions_car_outlined,
                        title: 'Your Vehicles Will Appear Here',
                        message: 'Not Connected. Registered vehicles and their approval details are unavailable until parking services are connected.',
                      )
                    else if (_controller.filteredVehicles.isEmpty)
                      EmptyStateCard(
                        icon: Icons.directions_car_outlined,
                        title: _controller.vehicles.isEmpty
                            ? 'No Registered Vehicles'
                            : 'No Matching Vehicles',
                        message: _controller.vehicles.isEmpty
                            ? 'You have no registered vehicles. New registrations require administrator approval.'
                            : 'Choose another filter to view your vehicles.',
                      )
                    else
                      for (final vehicle in _controller.filteredVehicles)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.medium,
                          ),
                          child: VehicleCard(
                            key: ValueKey(vehicle.id),
                            vehicle: vehicle,
                            busy: _controller.submitting,
                            onRemove: _controller.vehicleRepository == null
                                ? null
                                : () => _controller.remove(vehicle.id),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
