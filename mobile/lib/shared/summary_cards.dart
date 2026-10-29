import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';

class SummaryMetric {
  const SummaryMetric({
    required this.title,
    required this.value,
    required this.icon,
    this.tooltip,
  });
  final String title;
  final String value;
  final IconData icon;
  final String? tooltip;
}

/// Match the compact icon-and-label layout of the parking session details.
class SummaryCards extends StatelessWidget {
  const SummaryCards({required this.first, required this.second, super.key});
  final SummaryMetric first;
  final SummaryMetric second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final stacked = constraints.maxWidth < 280 || scaler.scale(14) > 20;
      final width = stacked
          ? constraints.maxWidth
          : (constraints.maxWidth - AppSpacing.small) / 2;
      final titleStyle = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final valueStyle = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      );
      double height(String text, TextStyle? style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: math.max(1, width - 46));
        final result = painter.height;
        painter.dispose();
        return result;
      }

      final titleHeight = math.max(
        height(first.title, titleStyle),
        height(second.title, titleStyle),
      );
      final valueHeight = math.max(
        height(first.value, valueStyle),
        height(second.value, valueStyle),
      );
      Widget card(SummaryMetric metric) => Card(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: metric.tooltip ?? metric.title,
                child: Icon(
                  metric.icon,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: titleHeight,
                      child: Text(metric.title, style: titleStyle),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: valueHeight,
                      child: Text(metric.value, style: valueStyle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card(first),
                const SizedBox(height: AppSpacing.small),
                card(second),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: card(first)),
                const SizedBox(width: AppSpacing.small),
                Expanded(child: card(second)),
              ],
            );
    },
  );
}
