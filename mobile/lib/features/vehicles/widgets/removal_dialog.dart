import 'package:flutter/material.dart';

import '../../../data/models/driver_models.dart';
import '../../../data/repositories/auth_repository.dart';

Future<void> showVehicleRemovalDialog(
  BuildContext context,
  DriverVehicle vehicle, {
  Future<void> Function()? onRemove,
}) async {
  if (!vehicle.canRemove) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Remove Vehicle?'),
      content: Text(
        'Remove ${vehicle.plateNumber} from your registered vehicles? '
        'The removal would withdraw its parking registration. ',
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
  if (onRemove != null) {
    try {
      await onRemove();
    } on AuthFailure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Removal could not be verified. Refresh your vehicles.',
            ),
          ),
        );
      }
    }
    return;
  }
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
