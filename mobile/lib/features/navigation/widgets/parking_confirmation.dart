import 'package:flutter/material.dart';

Future<void> showParkingConfirmation(
  BuildContext context,
  String zoneName,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Confirm Parking?'),
      content: Text(
        'You are confirming that you have parked in your allocated zone: $zoneName. '
        'Confirmation services are not connected yet.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Confirmation Unavailable'),
      content: const Text(
        'Parking confirmation is not connected. Your session status has not changed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
