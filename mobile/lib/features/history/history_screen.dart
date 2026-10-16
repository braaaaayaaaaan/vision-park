import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'history_controller.dart';
import 'widgets/history_session_card.dart';
import 'widgets/history_summary.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.controller, super.key});
  final HistoryController? controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  late final HistoryController _controller;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? HistoryController();
    _controller.load();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _controller.refreshPeriod(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refreshPeriod();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ready = _controller.status == HistoryStatus.ready;
        final sessions = _controller.filteredSessions;
        final average = _controller.averageDuration;
        return SingleChildScrollView(
          key: const PageStorageKey('parking-history'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Parking History',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text('Review Your Parking Visits'),
                    const SizedBox(height: AppSpacing.large),
                    HistorySummary(
                      total: ready ? '${sessions.length}' : 'Unavailable',
                      average: ready && average != null
                          ? MalaysianDateTime.formatDuration(average)
                          : 'Unavailable',
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    const Text(
                      'Average duration includes only completed sessions with valid entry and exit times.',
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Wrap(
                      spacing: AppSpacing.small,
                      runSpacing: AppSpacing.small,
                      children: [
                        for (final days in [1, 3, 7])
                          ChoiceChip(
                            label: Text(
                              'Last $days ${days == 1 ? 'Day' : 'Days'}',
                            ),
                            selected: _controller.days == days,
                            onSelected: (_) => _controller.selectDays(days),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text(
                      'Includes today and the preceding calendar days in Malaysia. Sessions are filtered by entry time.',
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _controller.vehicleId,
                          hint: const Text('All Vehicles'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All Vehicles'),
                            ),
                            for (final vehicle in _controller.vehicles)
                              DropdownMenuItem(
                                value: vehicle.id,
                                child: Text(vehicle.plateNumber),
                              ),
                          ],
                          onChanged: ready ? _controller.selectVehicle : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (_controller.status == HistoryStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Parking History',
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      const Text('Loading Parking History'),
                    ] else if (_controller.status == HistoryStatus.error) ...[
                      const EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Parking History',
                        message: 'Your history could not be confirmed. Please try again.',
                      ),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Try Again'),
                      ),
                    ] else if (!ready)
                      const EmptyStateCard(
                        icon: Icons.history_rounded,
                        title: 'Your Visits Will Appear Here',
                        message: 'Not Connected. Parking records and analytics are unavailable until parking services are connected.',
                      )
                    else if (sessions.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.history_rounded,
                        title: 'No Parking Sessions',
                        message: 'No sessions match this date period and vehicle. Try another filter.',
                      )
                    else
                      for (final session in sessions)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.medium,
                          ),
                          child: HistorySessionCard(
                            key: ValueKey(session.id),
                            session: session,
                            plate: _controller.plateFor(session),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
