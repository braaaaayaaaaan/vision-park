import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import 'payments_controller.dart';
import 'receipt_screen.dart';

/// Shared transaction presentation for the wallet preview and full history.
class TransactionEntry extends StatelessWidget {
  const TransactionEntry({
    required this.entry,
    required this.payments,
    this.showDate = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 10,
    ),
    super.key,
  });

  final WalletEntry entry;
  final PaymentsController payments;
  final bool showDate;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit = entry.kind == 'mock_top_up';
    final color = theme.colorScheme.primary;
    return ListTile(
      contentPadding: contentPadding,
      titleAlignment: ListTileTitleAlignment.top,
      leading: CircleAvatar(
        backgroundColor: AppTheme.blueSoft,
        child: Icon(
          credit ? Icons.add_rounded : Icons.receipt_long_outlined,
          color: color,
        ),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(16) > 21;
          final title = Text(
            credit ? 'Top Up' : 'Parking Deduction',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          );
          final amount = Text(
            '${credit ? '+' : '−'}${myr(entry.amount)}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          );
          final timestamp = MalaysianDateTime.format(entry.createdAt);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stacked) ...[
                title,
                const SizedBox(height: 4),
                amount,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 8),
                    amount,
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                showDate ? timestamp : timestamp.split(', ').last,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Balance After: ${myr(entry.balanceAfter)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
      onTap: entry.attemptId == null
          ? null
          : () => openReceipt(context, payments, entry.attemptId!),
    );
  }
}
