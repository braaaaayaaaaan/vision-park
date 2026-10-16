import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/driver_models.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'navigation_controller.dart';
import 'widgets/parking_confirmation.dart';
import 'widgets/route_panel.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({this.controller, super.key});
  final NavigationController? controller;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final NavigationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? NavigationController();
    _controller.load();
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
        final parking = _controller.data?.parking;
        return SingleChildScrollView(
          key: const PageStorageKey('navigation'),
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
                    Text(
                      'Route to Your Zone',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text('Fixed Route Guidance'),
                    const SizedBox(height: AppSpacing.large),
                    if (_controller.status == NavigationStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Navigation',
                      ),
                      const Text('Loading Navigation'),
                    ] else if (_controller.status ==
                        NavigationStatus.error) ...[
                      const EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Navigation',
                        message: 'Session and route information could not be confirmed.',
                      ),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Try Again'),
                      ),
                    ] else if (_controller.status ==
                        NavigationStatus.disconnected)
                      const EmptyStateCard(
                        icon: Icons.route_outlined,
                        title: 'Your Route Will Appear Here',
                        message: 'Not Connected. Your session, route and map are unavailable until parking services are connected.',
                      )
                    else if (!_controller.hasActiveSession)
                      const EmptyStateCard(
                        icon: Icons.local_parking_outlined,
                        title: 'No Active Parking Session',
                        message: 'Navigation requires an active parking allocation. No route is currently available.',
                      )
                    else if (parking != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.large),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                parking.vehicle.plateNumber,
                                style: theme.textTheme.titleLarge,
                              ),
                              Text(
                                'Session Status: ${parking.session.status == ParkingSessionStatus.allocated ? 'Allocated' : 'Occupied'}',
                              ),
                              Text(
                                parking.anprInformation ??
                                    'ANPR Recognition Information Unavailable',
                              ),
                              const SizedBox(height: AppSpacing.medium),
                              Text('Allocated Zone: ${parking.zone.name}'),
                              Text(
                                'Destination Level: ${parking.zone.levelName}',
                              ),
                              Text(
                                _controller.routeError == null
                                    ? 'Dijkstra Route Distance: ${parking.route!.distanceMetres.toStringAsFixed(0)} m'
                                    : 'Route Distance: Unavailable',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      RoutePanel(controller: _controller),
                      const SizedBox(height: AppSpacing.large),
                    ],
                    const SizedBox(height: AppSpacing.medium),
                    FilledButton(
                      onPressed: _controller.canConfirm
                          ? () => showParkingConfirmation(
                              context,
                              parking!.zone.name,
                            )
                          : null,
                      child: const Text("I've Parked"),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text(
                      'Confirmation requires an eligible allocated session and driver authorisation. Confirmation services are not connected yet.',
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
