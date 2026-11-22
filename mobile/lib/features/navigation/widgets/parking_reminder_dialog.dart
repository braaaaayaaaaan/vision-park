import 'package:flutter/material.dart';

class ParkingReminderDialog extends StatefulWidget {
  const ParkingReminderDialog({
    required this.levelName,
    required this.zoneName,
    required this.plateNumber,
    required this.onConfirm,
    super.key,
  });

  final String levelName;
  final String zoneName;
  final String plateNumber;
  final Future<String?> Function() onConfirm;

  @override
  State<ParkingReminderDialog> createState() => _ParkingReminderDialogState();
}

class _ParkingReminderDialogState extends State<ParkingReminderDialog> {
  bool _confirming = false;
  String? _error;

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    final error = await widget.onConfirm();
    if (!mounted || ModalRoute.isCurrentOf(context) != true) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _confirming = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final level = widget.levelName.trim();
    final zone = widget.zoneName.trim();
    final plate = widget.plateNumber.trim();
    final details = {
      if (level.isNotEmpty) 'Parking Level': level,
      if (zone.isNotEmpty) 'Parking Zone': zone,
      if (plate.isNotEmpty) 'Vehicle': plate,
    };
    return PopScope(
      canPop: !_confirming,
      child: AlertDialog(
        scrollable: true,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: colors.surface,
        icon: Center(
          child: CircleAvatar(
            radius: 28,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: const Icon(Icons.notifications_active_outlined, size: 26),
          ),
        ),
        title: const Text('Have you parked?', textAlign: TextAlign.center),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowButtonSpacing: 4,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Once you've parked safely in your assigned zone, tap below to confirm your parking.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    for (final MapEntry(:key, :value) in details.entries)
                      Text.rich(
                        TextSpan(
                          text: '$key: ',
                          children: [
                            TextSpan(
                              text: value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_confirming) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                semanticsLabel: 'Confirming parking',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _confirming
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Remind Me Later'),
          ),
          FilledButton(
            onPressed: _confirming ? null : _confirm,
            child: Text(_confirming ? 'Confirming…' : "I've Parked"),
          ),
        ],
      ),
    );
  }
}
