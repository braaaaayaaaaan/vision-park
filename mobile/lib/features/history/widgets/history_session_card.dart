import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/models/driver_models.dart';
import '../../../shared/formatting/malaysian_date_time.dart';
import '../history_controller.dart';

class HistorySessionCard extends StatefulWidget {
  const HistorySessionCard({
    required this.session,
    required this.plate,
    super.key,
  });
  final ParkingSession session;
  final String plate;

  @override
  State<HistorySessionCard> createState() => _HistorySessionCardState();
}

class _HistorySessionCardState extends State<HistorySessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final duration = HistoryController.durationOf(session);
    final status = switch (session.status) {
      ParkingSessionStatus.allocated => 'Allocated',
      ParkingSessionStatus.occupied => 'Occupied',
      ParkingSessionStatus.completed => 'Completed',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.plate, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.small),
            Text(
              status,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text('Zone: ${session.zoneName ?? 'Unavailable'}'),
            Text('Level: ${session.levelName ?? 'Unavailable'}'),
            const SizedBox(height: AppSpacing.medium),
            Text('Entry: ${MalaysianDateTime.format(session.entryTime)}'),
            Text(
              'Exit: ${session.exitTime == null ? 'Not Recorded' : MalaysianDateTime.format(session.exitTime!)}',
            ),
            Text(
              'Duration: ${duration == null ? 'Unavailable' : MalaysianDateTime.formatDuration(duration)}',
            ),
            if (session.exitTime != null && duration == null)
              const Text('The recorded timestamps are inconsistent.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Hide Details' : 'View Details'),
              ),
            ),
            if (_expanded) ...[
              const Divider(),
              const SizedBox(height: AppSpacing.medium),
              Text('Session ID: ${session.id}'),
              Text('Vehicle ID: ${session.vehicleId}'),
              Text('Zone ID: ${session.zoneId}'),
              Text(
                'Parking Confirmed: ${session.confirmedAt == null ? 'Not Recorded' : MalaysianDateTime.format(session.confirmedAt!)}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
