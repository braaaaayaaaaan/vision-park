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
    final colors = theme.colorScheme;
    final approved = vehicle.registrationStatus == 'approved';
    final badgeColor = vehicle.registrationStatus == 'rejected'
        ? colors.errorContainer
        : approved
        ? colors.primaryContainer
        : colors.secondaryContainer;
    final badgeInk = vehicle.registrationStatus == 'rejected'
        ? colors.onErrorContainer
        : approved
        ? colors.onPrimaryContainer
        : colors.onSecondaryContainer;
    final removalReason = vehicle.hasActiveSession
        ? 'Removal is unavailable during an active parking session.'
        : vehicle.removalReason ??
              'Removal is unavailable until session information is confirmed.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.plateNumber,
                        style: theme.textTheme.titleLarge?.copyWith(
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          vehicle.approvalLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: badgeInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.medium),
            if (vehicle.hasActiveSession)
              Container(
                padding: const EdgeInsets.all(AppSpacing.medium),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Active Parking Session',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session!.status == ParkingSessionStatus.allocated
                          ? 'Space Allocated'
                          : 'Parked',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    _ParkingDetail(
                      icon: Icons.location_on_outlined,
                      label: 'Zone',
                      value: [
                        if (session.levelName?.trim().isNotEmpty ?? false)
                          session.levelName!,
                        if (session.zoneName?.trim().isNotEmpty ?? false)
                          session.zoneName!,
                      ].join(' · '),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    _ParkingDetail(
                      icon: Icons.schedule_rounded,
                      label: 'Entry Time (MYT)',
                      value: MalaysianDateTime.format(session.entryTime),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Icon(
                    Icons.local_parking_outlined,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: Text(
                      vehicle.sessionInformationAvailable
                          ? 'No active parking session'
                          : 'Parking session unavailable',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.medium),
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: vehicle.canRemove
                    ? 'Remove this vehicle'
                    : removalReason,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    side: BorderSide(color: colors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: vehicle.canRemove && !widget.busy && !_removing
                      ? _remove
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove Vehicle'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingDetail extends StatelessWidget {
  const _ParkingDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? 'Not available' : value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
