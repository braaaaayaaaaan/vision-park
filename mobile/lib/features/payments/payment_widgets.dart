import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';

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
        SelectableText(value),
      ],
    ),
  );
}

class SimulationNotice extends StatelessWidget {
  const SimulationNotice({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Demo payments only. No real money is processed.',
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
    final children = <Widget>[
      Row(
        children: [
          Icon(
            Icons.payment_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Payment Required',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(charge.plate, style: Theme.of(context).textTheme.titleMedium),
      Text(
        charge.amount == null ? 'Awaiting Quotation' : myr(charge.amount!),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(
        'Parking Duration: ${charge.duration == null ? 'Unavailable' : MalaysianDateTime.formatDuration(charge.duration!)}',
      ),
      const Text(
        'Your parking session stays active until payment is confirmed.',
      ),
      ExpansionTile(
        title: const Text('View Session Details'),
        tilePadding: EdgeInsets.zero,
        children: [PaymentField('Parking Session', charge.sessionId)],
      ),
      FilledButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('Review Payment'),
      ),
    ];
    if (inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PaymentPanel(children: children),
    );
  }
}
