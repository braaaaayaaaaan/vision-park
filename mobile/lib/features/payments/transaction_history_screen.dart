import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/visible_poller.dart';
import 'payments_controller.dart';
import 'transaction_entry.dart';
import 'transaction_history_controller.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({required this.payments, super.key});
  final PaymentsController payments;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  late final TransactionHistoryController _history;
  late final VisiblePoller _poller;

  @override
  void initState() {
    super.initState();
    _history = TransactionHistoryController(widget.payments);
    _poller = VisiblePoller(
      refresh: () => _history.refresh(background: true),
      isVisible: () =>
          mounted &&
          !_history.loading &&
          widget.payments.isCurrentOwner &&
          ModalRoute.of(context)?.isCurrent != false,
    );
    unawaited(_history.refresh());
  }

  @override
  void dispose() {
    _poller.dispose();
    _history.dispose();
    super.dispose();
  }

  String _date(DateTime date) =>
      MalaysianDateTime.format(date.subtract(const Duration(hours: 8)))
          .split(', ')
          .first;

  String get _rangeLabel => _history.days == 0
      ? 'Recent'
      : _history.days > 0
      ? 'Last ${_history.days} ${_history.days == 1 ? 'Day' : 'Days'}'
      : '${_date(_history.startDate!)} – ${_date(_history.endDate!)}';

  Future<void> _selectRange(int days) async {
    if (days != -1) {
      await _history.selectDays(days);
      return;
    }
    final today = _history.today;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1982),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: _history.startDate == null
          ? null
          : DateTimeRange(start: _history.startDate!, end: _history.endDate!),
      helpText: 'Select Date Range',
      saveText: 'Apply',
    );
    if (!mounted || range == null) return;
    if (!await _history.selectRange(range.start, range.end) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a date range of up to 90 days.')),
      );
    }
  }

  Widget _dateFilter(ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => PopupMenuButton<int>(
              key: const ValueKey('transaction-date-range'),
              tooltip: 'Select Date Range',
              position: PopupMenuPosition.under,
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: _selectRange,
              itemBuilder: (_) => [
                for (final days in [0, 1, 3, 7, 30, -1])
                  CheckedPopupMenuItem<int>(
                    value: days,
                    checked: _history.days == days,
                    child: Text(
                      days == 0
                          ? 'Recent'
                          : days == -1
                          ? 'Custom Range'
                          : 'Last $days ${days == 1 ? 'Day' : 'Days'}',
                    ),
                  ),
              ],
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date Range',
                  isDense: true,
                  prefixIcon: const Icon(Icons.date_range_outlined, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_rangeLabel)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Filter by the transaction date.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaction History')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([_history, widget.payments]),
        builder: (context, _) {
          if (!widget.payments.isCurrentOwner) {
            return const Center(
              child: Text('Sign in again to access your payments.'),
            );
          }
          final theme = Theme.of(context);
          final groups = <String, List<WalletEntry>>{};
          for (final entry in _history.entries) {
            groups
                .putIfAbsent(_history.dayLabel(entry.createdAt), () => [])
                .add(entry);
          }
          return RefreshIndicator(
            onRefresh: _history.refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.contentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dateFilter(theme),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                _history.days == 0 ? 'Recent' : 'Transactions',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (_history.days != 0)
                            TextButton(
                              onPressed: () => _history.selectDays(0),
                              child: const Text('Clear Filter'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_history.loading) ...[
                        const LinearProgressIndicator(
                          semanticsLabel: 'Loading Transactions',
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_history.error != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _history.error!,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _history.loading
                                      ? null
                                      : _history.refresh,
                                  child: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (!_history.loading && groups.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 36,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 40,
                                  color: AppTheme.blue,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _history.days == 0
                                      ? 'No Transactions Yet'
                                      : 'No Transactions in This Period',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _history.days == 0
                                      ? 'Your top-ups and parking payments will appear here.'
                                      : 'Choose another date range to view your transactions.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final group in groups.entries) ...[
                        Semantics(
                          header: true,
                          child: Text(
                            group.key,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < group.value.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  const Divider(indent: 16, endIndent: 16),
                                TransactionEntry(
                                  entry: group.value[index],
                                  payments: widget.payments,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_history.hasMore)
                        TextButton(
                          onPressed: _history.loading || _history.refreshing
                              ? null
                              : _history.loadMore,
                          child: const Text('Load More Transactions'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
