import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/driver_models.dart';
import '../../../shared/formatting/malaysian_date_time.dart';
import 'removal_dialog.dart';

class VehicleCard extends StatefulWidget {
  const VehicleCard({
    required this.vehicle,
    this.onRemove,
    this.busy = false,
    super.key,
  });
  final DriverVehicle vehicle;
  final Future<void> Function()? onRemove;
  final bool busy;

  @override
  State<VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<VehicleCard> {
  bool _expanded = false;
  bool _removing = false;
  Future<void> _remove() async {
    if (_removing || widget.busy) return;
    setState(() => _removing = true);
    try {
      await showVehicleRemovalDialog(
        context,
        widget.vehicle,
        onRemove: widget.onRemove,
      );
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final theme = Theme.of(context);
    final session = vehicle.activeSession;
    final sessionText = vehicle.hasActiveSession
        ? 'Active Parking Session: ${session!.status == ParkingSessionStatus.allocated ? 'Allocated' : 'Occupied'}'
        : vehicle.sessionInformationAvailable
        ? 'No Active Parking Session'
        : 'Parking Session Information Unavailable';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(vehicle.plateNumber, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.small),
            Text(
              vehicle.approvalLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(
              vehicle.lastRecognitionAt != null
                  ? 'ANPR Recognition Recorded'
                  : 'ANPR Recognition Information Unavailable',
            ),
            Text(sessionText),
            const SizedBox(height: AppSpacing.medium),
            Wrap(
              spacing: AppSpacing.small,
              runSpacing: AppSpacing.small,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(_expanded ? 'Hide Details' : 'View Details'),
                ),
                OutlinedButton(
                  onPressed: vehicle.canRemove && !widget.busy && !_removing
                      ? _remove
                      : null,
                  child: const Text('Remove Vehicle'),
                ),
              ],
            ),
            if (!vehicle.canRemove)
              Text(
                vehicle.hasActiveSession
                    ? 'Removal is unavailable while a parking session is allocated or occupied.'
                    : vehicle.removalReason ?? 'Removal permission or current session information is unavailable.',
              ),
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.medium),
              const Divider(),
              const SizedBox(height: AppSpacing.medium),
              Text('Number Plate: ${vehicle.plateNumber}'),
              Text('Approval Status: ${vehicle.approvalLabel}'),
              const SizedBox(height: AppSpacing.small),
              Text(
                vehicle.lastRecognitionAt == null
                    ? 'Last Recognition: Unavailable'
                    : 'Last Recognition: ${MalaysianDateTime.format(vehicle.lastRecognitionAt!)}',
              ),
              const Text(
                'Administrator approval and ANPR recognition are separate checks.',
              ),
              const SizedBox(height: AppSpacing.small),
              Text(sessionText),
              if (vehicle.hasActiveSession) ...[
                Text('Session ID: ${session!.id}'),
                Text('Zone ID: ${session.zoneId}'),
                Text(
                  'Entry Time: ${MalaysianDateTime.format(session.entryTime)}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
