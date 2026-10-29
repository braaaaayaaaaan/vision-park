import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/vision_park_brand.dart';

class PaymentPanel extends StatelessWidget {
  const PaymentPanel({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class PaymentField extends StatelessWidget {
  const PaymentField(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        SelectableText(
          value,
          // SelectableText also saves a scroll offset; keep it separate from
          // both the enclosing page and any expansion panel's boolean state.
          key: PageStorageKey(('payment-field', label, value)),
        ),
      ],
    ),
  );
}

class PaymentRequiredCard extends StatelessWidget {
  const PaymentRequiredCard({
    required this.charge,
    required this.onOpen,
    this.inline = false,
    super.key,
  });
  final ParkingCharge charge;
  final VoidCallback onOpen;
  final bool inline;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = charge.amount == null
        ? 'Awaiting Quotation'
        : myr(charge.amount!);
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandIconBadge(Icons.payments_outlined, size: 32),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Required', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                '${charge.plate} · $amount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Review Payment',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final content = Semantics(
      button: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
        child: Padding(
          padding: inline
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.large,
                  vertical: 12,
                ),
          child: details,
        ),
      ),
    );
    if (inline) return content;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(clipBehavior: Clip.antiAlias, child: content),
    );
  }
}
