import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/dashboard_models.dart';
import '../allocation_notifications.dart';
import '../home_controller.dart';

/// Home-only notification. No overlay, automatic navigation or extra polling.
class AllocationBanner extends StatefulWidget {
  const AllocationBanner({
    required this.controller,
    required this.isVisible,
    required this.paymentSessionIds,
    required this.onViewNavigation,
    super.key,
  });

  final HomeController controller;
  final bool isVisible;
  final Set<String> paymentSessionIds;
  final ValueChanged<ActiveParking> onViewNavigation;

  @override
  State<AllocationBanner> createState() => _AllocationBannerState();
}

class _AllocationBannerState extends State<AllocationBanner>
    with WidgetsBindingObserver {
  String? _sessionId;
  int _minimumRevision = 0;
  bool _active = false, _scheduled = false;

  bool get _canShow =>
      widget.isVisible &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent != false;

  ActiveParking? get _parking =>
      widget.controller.sessionStatus == HomeStatus.ready
      ? widget.controller.activeSessions
            .where(
              (parking) =>
                  parking.session.id == _sessionId &&
                  AllocationNotifications.isAllocated(parking) &&
                  !widget.paymentSessionIds.contains(parking.session.id),
            )
            .firstOrNull
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant AllocationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final active = _canShow;
    if (!active) {
      // A shown notice never reappears after leaving Home. Queued notices must
      // be checked against a fresh snapshot on return/background resumption.
      _sessionId = null;
      _minimumRevision = widget.controller.sessionRevision + 1;
    }
    _active = active;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          !_canShow ||
          widget.controller.sessionStatus != HomeStatus.ready ||
          widget.controller.sessionRevision < _minimumRevision) {
        return;
      }
      if (_parking != null) return;
      final next = widget.controller.allocationNotifications.takeNext(
        widget.paymentSessionIds,
      );
      final id = next?.session.id;
      if (_sessionId != id) setState(() => _sessionId = id);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(_update);
  }

  void _dismiss() {
    setState(() => _sessionId = null);
    _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parking = _parking;
    if (!_active || parking == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.contentWidth - 48,
          ),
          child: Material(
            color: const Color(0xFFF0F6FD),
            elevation: 2,
            shadowColor: AppTheme.ink.withValues(alpha: .12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
              side: const BorderSide(color: Color(0xFFDCE7F5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: MaterialBanner(
              backgroundColor: const Color(0xFFF0F6FD),
              elevation: 0,
              dividerColor: Colors.transparent,
              forceActionsBelow: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.ink,
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Assigned Parking Zone',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss Assignment',
                        onPressed: _dismiss,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  Text(
                    'Park at ${parking.zone.levelName}, ${parking.zone.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vehicle: ${parking.vehicle.plateNumber}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      final current = _parking;
                      if (!_canShow || current == null) return;
                      _dismiss();
                      widget.onViewNavigation(current);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('View Navigation'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
