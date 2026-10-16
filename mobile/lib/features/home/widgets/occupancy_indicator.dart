import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

class OccupancyIndicator extends StatelessWidget {
  const OccupancyIndicator({
    required this.occupancy,
    required this.totalSpaces,
    super.key,
  });

  final double? occupancy;
  final int totalSpaces;

  @override
  Widget build(BuildContext context) {
    final value = occupancy;
    if (totalSpaces <= 0 ||
        value == null ||
        !value.isFinite ||
        value < 0 ||
        value > 1) {
      return const Text('Occupancy Unavailable');
    }

    final (label, colour) = value >= 1
        ? ('Full', OccupancyColours.full)
        : value >= 0.75
        ? ('Nearly Full', OccupancyColours.nearlyFull)
        : ('Available', OccupancyColours.available);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.small),
        LinearProgressIndicator(
          value: value,
          minHeight: 8,
          borderRadius: BorderRadius.circular(AppSpacing.small),
          color: colour,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          semanticsLabel: 'Parking Occupancy: $label',
          semanticsValue: '${(value * 100).round()}%',
        ),
      ],
    );
  }
}
