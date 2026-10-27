import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/driver_models.dart';
import '../../../shared/formatting/malaysian_date_time.dart';
import '../history_controller.dart';

class HistorySessionCard extends StatelessWidget {
  const HistorySessionCard({
    required this.session,
    required this.plate,
    this.onReceipt,
    super.key,
  });
  final ParkingSession session;
  final String plate;
  final VoidCallback? onReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = HistoryController.durationOf(session);
    final status = switch (session.status) {
      ParkingSessionStatus.allocated => 'Space Allocated',
      ParkingSessionStatus.occupied => 'Parked',
      ParkingSessionStatus.completed => 'Completed',
    };
    final location = [
      if (session.levelName?.trim().isNotEmpty ?? false) session.levelName!,
      if (session.zoneName?.trim().isNotEmpty ?? false) session.zoneName!,
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plate,
                        style: theme.textTheme.titleLarge?.copyWith(
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailGrid(
              columns: 2,
              children: [
                _HistoryDetail(
                  icon: Icons.location_on_outlined,
                  label: 'Zone',
                  value: location.isEmpty ? 'Not available' : location,
                ),
                _HistoryDetail(
                  icon: Icons.timelapse_rounded,
                  label: 'Parking Duration',
                  value: duration == null
                      ? 'Unavailable'
                      : MalaysianDateTime.formatDuration(duration),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DetailGrid(
              columns: 3,
              children: [
                _HistoryDetail(
                  icon: Icons.login_rounded,
                  label: 'Entry Time (MYT)',
                  value: MalaysianDateTime.format(session.entryTime),
                ),
                _HistoryDetail(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Parking Confirmed',
                  value: session.confirmedAt == null
                      ? 'Not recorded'
                      : MalaysianDateTime.format(session.confirmedAt!),
                ),
                _HistoryDetail(
                  icon: Icons.logout_rounded,
                  label: 'Exit Time (MYT)',
                  value: session.exitTime == null
                      ? 'Not recorded'
                      : MalaysianDateTime.format(session.exitTime!),
                ),
              ],
            ),
            if (session.exitTime != null && duration == null) ...[
              const SizedBox(height: AppSpacing.small),
              Text(
                'The recorded timestamps are inconsistent.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            if (onReceipt != null)
              TextButton.icon(
                onPressed: onReceipt,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View Payment Receipt'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < columns * 150 + (columns - 1) * 8 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                children[index],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(child: children[index]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryDetail extends StatelessWidget {
  const _HistoryDetail({
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
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
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
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
