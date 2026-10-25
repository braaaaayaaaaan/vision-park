import '../../data/repositories/history_repository.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/widgets/empty_state_card.dart';
import 'history_controller.dart';
import 'widgets/history_session_card.dart';
import 'widgets/history_summary.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    this.controller,
    this.historyRepository,
    this.isVisible = true,
    super.key,
  });
  final HistoryRepository? historyRepository;
  final bool isVisible;
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
    _controller =
        widget.controller ??
        HistoryController(historyRepository: widget.historyRepository);
    if (widget.isVisible) _controller.load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.isVisible) _controller.refreshPeriod();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isVisible) {
      _controller.load();
    }
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _controller.load();
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
        final theme = Theme.of(context);
        return SingleChildScrollView(
          key: const PageStorageKey('parking-history'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parking History',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your past visits, in one place.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Refresh History',
                          onPressed: _controller.status == HistoryStatus.loading
                              ? null
                              : _controller.load,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    HistorySummary(
                      total: ready
                          ? '${_controller.totalSessions}'
                          : 'Unavailable',
                      average: ready && average != null
                          ? MalaysianDateTime.formatDuration(average)
                          : 'Unavailable',
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Filter History',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) => PopupMenuButton<int>(
                                key: const ValueKey('history-date-range'),
                                tooltip: 'Select Date Range',
                                position: PopupMenuPosition.under,
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                  maxWidth: constraints.maxWidth,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onSelected: _controller.selectDays,
                                itemBuilder: (_) => [
                                  for (final days in [1, 3, 7])
                                    CheckedPopupMenuItem<int>(
                                      value: days,
                                      checked: _controller.days == days,
                                      child: Text(
                                        'Last $days ${days == 1 ? 'Day' : 'Days'}',
                                      ),
                                    ),
                                ],
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Date Range',
                                    isDense: true,
                                    prefixIcon: const Icon(
                                      Icons.date_range_outlined,
                                      size: 20,
                                    ),
                                    filled: true,
                                    fillColor:
                                        theme.colorScheme.surfaceContainerLow,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Last ${_controller.days} ${_controller.days == 1 ? 'Day' : 'Days'}',
                                        ),
                                      ),
                                      const Icon(Icons.arrow_drop_down),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Vehicle Number Plate',
                                isDense: true,
                                prefixIcon: const Icon(
                                  Icons.directions_car_outlined,
                                ),
                                filled: true,
                                fillColor:
                                    theme.colorScheme.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  isDense: true,
                                  itemHeight: null,
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
                                  onChanged: ready
                                      ? _controller.selectVehicle
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'By entry date, including today · Malaysia Time (MYT).',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text('Parking Sessions', style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      'Most recent first',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_controller.status == HistoryStatus.loading) ...[
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading Parking History',
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      const Text('Loading Parking History'),
                    ] else if (_controller.status == HistoryStatus.error) ...[
                      EmptyStateCard(
                        icon: Icons.info_outline,
                        title: 'Unable to Load Parking History',
                        message: _controller.message ?? 'Your history could not be confirmed. Please try again.',
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
                        compact: true,
                        icon: Icons.history_rounded,
                        title: 'No Parking Sessions',
                        message: 'No sessions match this date period and vehicle. Try another filter.',
                      )
                    else
                      for (final session in sessions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: HistorySessionCard(
                            key: ValueKey(session.id),
                            session: session,
                            plate: _controller.plateFor(session),
                          ),
                        ),
                    if (ready && _controller.nextCursor != null) ...[
                      Text(
                        'Load all sessions to see the period’s average duration.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      OutlinedButton.icon(
                        onPressed: _controller.loadingMore
                            ? null
                            : _controller.loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          _controller.loadingMore
                              ? 'Loading More'
                              : 'Load More',
                        ),
                      ),
                    ],
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
