import 'package:flutter/material.dart';

import '../../../data/repositories/status_reminder_repository.dart';
import '../../../shared/visible_poller.dart';
import '../../../shared/formatting/malaysian_date_time.dart';
import '../status_reminder_controller.dart';

/// Persisted admin messages. Poll only while Home is visible and resumed.
class StatusReminderBanner extends StatefulWidget {
  const StatusReminderBanner({
    required this.repository,
    required this.isVisible,
    super.key,
  });
  final StatusReminderRepository repository;
  final bool isVisible;
  @override
  State<StatusReminderBanner> createState() => _StatusReminderBannerState();
}

class _StatusReminderBannerState extends State<StatusReminderBanner> {
  late final StatusReminderController _controller;
  late final VisiblePoller _poller;
  bool get _visible =>
      mounted && widget.isVisible && ModalRoute.of(context)?.isCurrent != false;
  @override
  void initState() {
    super.initState();
    _controller = StatusReminderController(widget.repository);
    _poller = VisiblePoller(
      refresh: _controller.load,
      isVisible: () => _visible,
    );
    if (widget.isVisible) _controller.load();
  }

  @override
  void didUpdateWidget(covariant StatusReminderBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _controller.load();
  }

  @override
  void dispose() {
    _poller.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _respond(ParkingStatusReminder reminder, String response) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Parking Status'),
        content: Text(
          '${response == 'still_parked' ? 'Tell the administrator you are still parked' : 'Tell the administrator you have already left'} with ${reminder.plateNumber}?',
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
    if (confirmed == true && _visible) {
      await _controller.respond(reminder, response);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      if (!widget.isVisible) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_controller.error!),
                    TextButton.icon(
                      onPressed: _controller.sending ? null : _controller.load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry Parking Reminders'),
                    ),
                  ],
                ),
              ),
            ),
          if (_controller.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _controller.notice!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          for (final reminder in _controller.reminders)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.notification_important_outlined,
                            color: Color(0xFFB45309),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Parking Status Requested by Admin',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        reminder.plateNumber,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(reminder.message),
                      const SizedBox(height: 6),
                      Text(
                        'Sent by the administrator · ${MalaysianDateTime.format(reminder.sentAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _controller.sending
                                ? null
                                : () => _respond(reminder, 'still_parked'),
                            child: const Text('Still Parked'),
                          ),
                          OutlinedButton(
                            onPressed: _controller.sending
                                ? null
                                : () => _respond(reminder, 'already_left'),
                            child: const Text('Already Left'),
                          ),
                        ],
                      ),
                      if (_controller.sending)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
