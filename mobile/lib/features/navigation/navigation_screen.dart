import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/repositories/assigned_route_repository.dart';
import '../../data/models/driver_models.dart';
import '../../data/models/dashboard_models.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/visible_poller.dart';
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
    this.refreshRevision = 0,
    this.paymentSessionIds = const {},
    this.onPaymentSelected,
    this.requestedAllocation,
    super.key,
  });
  final NavigationController? controller;
  final AssignedRouteRepository? routeRepository;
  final bool isVisible;
  final VoidCallback? onParkingConfirmed;
  final RouteVoiceGuidance? voiceGuidance;
  final int refreshRevision;
  final Set<String> paymentSessionIds;
  final ValueChanged<String>? onPaymentSelected;
  final ActiveParking? requestedAllocation;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final NavigationController _controller;
  late final RouteVoiceGuidance _voice;
  late final VisiblePoller _poller;
  bool _dialogOpen = false;
  bool _mapTouchActive = false;

  void _setMapTouchActive(bool active) {
    if (mounted && _mapTouchActive != active) {
      setState(() => _mapTouchActive = active);
    }
  }

  Future<void> _confirmParking() async {
    if (_dialogOpen ||
        !_controller.canConfirm ||
        widget.paymentSessionIds.contains(
          _controller.data?.parking?.session.id,
        )) {
      return;
    }
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
    if (widget.isVisible) _loadSelection();
    _poller = VisiblePoller(
      refresh: () => _controller.load(background: true),
      isVisible: () =>
          mounted &&
          widget.isVisible &&
          !_dialogOpen &&
          ModalRoute.of(context)?.isCurrent != false,
    );
  }

  void _loadSelection({bool background = false}) {
    final requested = widget.requestedAllocation;
    if (requested != null) {
      if (requested.session.status == ParkingSessionStatus.occupied) {
        _controller.openSession(requested);
      } else {
        _controller.openAllocation(requested);
      }
    } else {
      _controller.clearAllocationTarget();
      _controller.load(background: background);
    }
  }

  @override
  void didUpdateWidget(covariant NavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVisible) _voice.pause();
    if (widget.isVisible &&
        (!oldWidget.isVisible ||
            widget.refreshRevision != oldWidget.refreshRevision ||
            !identical(
              widget.requestedAllocation,
              oldWidget.requestedAllocation,
            ))) {
      if (!identical(
        widget.requestedAllocation,
        oldWidget.requestedAllocation,
      )) {
        _loadSelection();
      } else {
        _controller.load(background: oldWidget.isVisible);
      }
    }
    if (widget.paymentSessionIds.contains(
      _controller.data?.parking?.session.id,
    )) {
      _voice.pause();
    }
  }

  @override
  void dispose() {
    _poller.dispose();
    _voice.pause();
    if (widget.voiceGuidance == null) _voice.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _parkButton() => FilledButton.icon(
    onPressed: _controller.canConfirm && !_dialogOpen ? _confirmParking : null,
    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
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
    return message == null
        ? null
        : Text(
            message,
            style: _controller.confirmationSucceeded
                ? const TextStyle(color: Color(0xFF15803D))
                : null,
          );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final parking = _controller.data?.parking;
        if (parking != null &&
            widget.paymentSessionIds.contains(parking.session.id)) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const EmptyStateCard(
                  compact: true,
                  icon: Icons.payment_rounded,
                  title: 'Payment Required',
                  message: 'Review your outstanding payment to continue.',
                ),
                FilledButton(
                  onPressed: () =>
                      widget.onPaymentSelected?.call(parking.session.id),
                  child: const Text('Review Payment'),
                ),
              ],
            ),
          );
        }
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
                        icon: Icons.directions_car_outlined,
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
