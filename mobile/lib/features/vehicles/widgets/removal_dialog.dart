import 'package:flutter/material.dart';

import '../../../data/models/driver_models.dart';

Future<void> showVehicleRemovalDialog(
  BuildContext context,
  DriverVehicle vehicle,
) async {
  if (!vehicle.canRemove) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Remove Vehicle?'),
      content: Text(
        'Remove ${vehicle.plateNumber} from your registered vehicles? '
        'Removal would withdraw its parking registration. '
        'Vehicles with an allocated or occupied session cannot be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove Vehicle'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Removal Unavailable'),
      content: const Text(
        'Vehicle removal is not connected yet. No vehicle has been removed or changed.',
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
