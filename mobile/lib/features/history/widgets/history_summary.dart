import 'package:flutter/material.dart';

import '../../../shared/summary_cards.dart';

class HistorySummary extends StatelessWidget {
  const HistorySummary({required this.total, required this.average, super.key});
  final String total;
  final String average;

  @override
  Widget build(BuildContext context) => SummaryCards(
    first: SummaryMetric(
      title: 'Total Sessions',
      value: total,
      icon: Icons.history_rounded,
    ),
    second: SummaryMetric(
      title: 'Average Parking Duration',
      value: average,
      icon: Icons.schedule_rounded,
      tooltip: 'Includes completed sessions with valid entry and exit times. Load all sessions to calculate the average.',
    ),
  );
}
