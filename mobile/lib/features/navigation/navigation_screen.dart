import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/assigned_route_repository.dart';
import '../../data/models/driver_models.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'navigation_controller.dart';
import 'route_voice_guidance.dart';
import 'widgets/parking_confirmation.dart';
import 'widgets/route_panel.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    this.controller,
    this.routeRepository,
    this.isVisible = true,
    this.onParkingConfirmed,
    this.voiceGuidance,
    super.key,
  });
  final NavigationController? controller;
  final AssignedRouteRepository? routeRepository;
  final bool isVisible;
  final VoidCallback? onParkingConfirmed;
  final RouteVoiceGuidance? voiceGuidance;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final NavigationController _controller;
  late final RouteVoiceGuidance _voice;
  bool _dialogOpen = false;
  bool _mapTouchActive = false;

  void _setMapTouchActive(bool active) {
    if (mounted && _mapTouchActive != active) {
      setState(() => _mapTouchActive = active);
    }
  }

  Future<void> _confirmParking() async {
    if (_dialogOpen || !_controller.canConfirm) return;
    _voice.pause();
    final parking = _controller.data!.parking!;
    setState(() => _dialogOpen = true);
    try {
      await showParkingConfirmation(
        context,
        parking.zone.name,
        onConfirm: !_controller.hasConfirmationService
            ? null
            : () async {
                final confirmed = await _controller.confirmSelected(
                  parking.session.id,
                );
                if (confirmed && mounted) widget.onParkingConfirmed?.call();
              },
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceGuidance ?? RouteVoiceGuidance();
    _controller =
        widget.controller ??
        NavigationController(routeRepository: widget.routeRepository);
    if (widget.isVisible) _controller.load();
  }

  @override
  void didUpdateWidget(covariant NavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVisible) _voice.pause();
    if (widget.isVisible && !oldWidget.isVisible) _controller.load();
  }

  @override
  void dispose() {
    _voice.pause();
    if (widget.voiceGuidance == null) _voice.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _parkButton() => FilledButton.icon(
    onPressed: _controller.canConfirm && !_dialogOpen ? _confirmParking : null,
    icon: const Icon(Icons.local_parking_rounded, size: 18),
    label: Text(
      _controller.confirming ? 'Confirming Parking...' : "I've Parked",
    ),
  );

  Widget? _feedback() {
    if (_controller.confirming) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Confirming Parking',
      );
    }
    final message = _controller.confirmationMessage;
    return message == null ? null : Text(message);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final parking = _controller.data?.parking;
        final ready =
            _controller.status == NavigationStatus.ready &&
            parking != null &&
            _controller.hasActiveSession;
        return SingleChildScrollView(
          physics: _mapTouchActive
              ? const NeverScrollableScrollPhysics()
              : null,
          key: const PageStorageKey('navigation'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Navigate',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (_controller.routeRepository != null)
                          IconButton(
                            tooltip: 'Refresh Navigation',
                            onPressed:
                                _controller.confirming ||
                                    _controller.status ==
                                        NavigationStatus.loading
                                ? null
                                : _controller.load,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                      ],
                    ),
                    if (_controller.sessions.length > 1) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(_controller.selectedSessionId),
                        initialValue: _controller.selectedSessionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Parking Session',
                          isDense: true,
                        ),
                        items: [
                          for (final item in _controller.sessions)
                            DropdownMenuItem(
                              value: item.session.id,
                              child: Text(
                                '${item.vehicle.plateNumber} · ${item.zone.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged:
                            _controller.confirming ||
                                _controller.status == NavigationStatus.loading
                            ? null
                            : (id) {
                                if (id != null) _controller.selectSession(id);
                              },
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    if (_controller.status == NavigationStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Navigation',
                      ),
                      const Text('Loading Navigation'),
                    ] else if (_controller.status ==
                        NavigationStatus.error) ...[
                      EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Navigation',
                        message: _controller.message ?? 'Session and route information could not be confirmed.',
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
                        compact: true,
                        icon: Icons.local_parking_outlined,
                        title: 'No Active Parking Session',
                        message: 'Navigation requires an active parking allocation. No route is currently available.',
                      )
                    else if (ready)
                      RoutePanel(
                        controller: _controller,
                        voiceGuidance: _voice,
                        maxMapHeight: constraints.hasBoundedHeight
                            ? constraints.maxHeight * .65
                            : 440,
                        onMapTouchChanged: _setMapTouchActive,
                        previewEnabled:
                            widget.isVisible &&
                            !_dialogOpen &&
                            !_controller.confirming &&
                            parking.session.status ==
                                ParkingSessionStatus.allocated,
                        parkingAction: _parkButton(),
                        parkingFeedback: _feedback(),
                      ),
                    if (!ready) ...[
                      const SizedBox(height: 16),
                      _parkButton(),
                      if (_feedback() != null) _feedback()!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
