import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

class HistorySummary extends StatelessWidget {
  const HistorySummary({required this.total, required this.average, super.key});
  final String total;
  final String average;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final theme = Theme.of(context);
        final cardWidth = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.small) / 2;
        double textHeight(String text, TextStyle? style, {double inset = 24}) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: cardWidth - inset);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final titleHeight = math.max(
          textHeight('Total Sessions', theme.textTheme.labelMedium, inset: 48),
          textHeight(
            'Average Parking Duration',
            theme.textTheme.labelMedium,
            inset: 48,
          ),
        );
        final valueHeight = math.max(
          textHeight(
            total,
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          textHeight(
            average,
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
        final cards = [
          _SummaryCard(
            title: 'Total Sessions',
            value: total,
            icon: Icons.history_rounded,
            titleHeight: titleHeight,
            valueHeight: valueHeight,
          ),
          _SummaryCard(
            title: 'Average Parking Duration',
            value: average,
            icon: Icons.schedule_rounded,
            titleHeight: titleHeight,
            valueHeight: valueHeight,
            tooltip: 'Includes completed sessions with valid entry and exit times. Load all sessions to calculate the average.',
          ),
        ];
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cards[0],
                  const SizedBox(height: AppSpacing.small),
                  cards[1],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(child: cards[1]),
                ],
              );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.titleHeight,
    required this.valueHeight,
    this.tooltip,
  });
  final String title;
  final String value;
  final IconData icon;
  final double titleHeight;
  final double valueHeight;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: tooltip ?? title,
                  child: Icon(icon, size: 18, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: titleHeight,
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: valueHeight,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
