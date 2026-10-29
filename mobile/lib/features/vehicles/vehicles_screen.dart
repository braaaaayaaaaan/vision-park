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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'My Vehicles',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your vehicles and parking, at a glance.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_controller.vehicleRepository != null)
                          IconButton.filledTonal(
                            tooltip: 'Refresh Vehicles',
                            onPressed:
                                _controller.submitting ||
                                    _controller.status == VehiclesStatus.loading
                                ? null
                                : _controller.load,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                      ],
                    ),
                    if (_controller.notice != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      Semantics(
                        liveRegion: true,
                        child: Text(_controller.notice!),
                      ),
                    ],
                    if (_controller.submitting)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Saving Vehicle',
                      ),
                    const SizedBox(height: AppSpacing.large),
                    Card(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.cornerRadius,
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              ready
                                  ? '${_controller.registrationUsage} / ${VehiclesController.registrationLimit} Registered Vehicles'
                                  : 'Unavailable Registration Usage',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.add_road_rounded,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _controller.atRegistrationLimit
                                            ? 'Limit Reached'
                                            : 'Add a Vehicle',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _controller.atRegistrationLimit
                                            ? 'Remove an eligible registration or wait for a pending registration to be rejected before adding another.'
                                            : 'Register your number plate. Parking access is granted after administrator approval.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.medium),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed:
                                  _controller.submitting ||
                                      _controller.atRegistrationLimit ||
                                      (!ready &&
                                          _controller.vehicleRepository !=
                                              null) ||
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
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Register New Vehicle'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Text(
                      'Registered Vehicles',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Filter Vehicles',
                        enabled: ready,
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<VehicleFilter>(
                          value: _controller.filter,
                          isExpanded: true,
                          isDense: true,
                          itemHeight: null,
                          borderRadius: BorderRadius.circular(12),
                          items: [
                            for (final (filter, label, count) in [
                              (
                                VehicleFilter.all,
                                'All',
                                _controller.vehicles.length,
                              ),
                              (
                                VehicleFilter.approved,
                                'Approved',
                                _controller.count('approved'),
                              ),
                              (
                                VehicleFilter.pending,
                                'Pending',
                                _controller.count('pending'),
                              ),
                              (
                                VehicleFilter.active,
                                'Active',
                                _controller.activeCount,
                              ),
                              (
                                VehicleFilter.rejected,
                                'Rejected',
                                _controller.count('rejected'),
                              ),
                            ])
                              DropdownMenuItem(
                                value: filter,
                                child: Row(
                                  children: [
                                    Expanded(child: Text(label)),
                                    const SizedBox(width: AppSpacing.small),
                                    Text(
                                      ready ? '$count' : '—',
                                      semanticsLabel: ready
                                          ? '$count vehicles'
                                          : 'Count unavailable',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: ready
                              ? (filter) {
                                  if (filter != null) {
                                    _controller.selectFilter(filter);
                                  }
                                }
                              : null,
                        ),
                      ),
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
                        compact: true,
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
