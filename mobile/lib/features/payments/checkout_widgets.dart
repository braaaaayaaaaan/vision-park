import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import '../../shared/summary_cards.dart';
import '../../shared/vision_park_brand.dart';
import 'payment_widgets.dart';

class CheckoutSummary extends StatelessWidget {
  const CheckoutSummary({
    required this.charge,
    this.reference,
    this.expired = false,
    super.key,
  });
  final ParkingCharge? charge;
  final String? reference;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = charge;
    return PaymentPanel(
      children: [
        Row(
          children: [
            const VisionParkFalcon(width: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Parking Payment',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.blueSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amount Due',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                current?.amount == null
                    ? 'Awaiting Quotation'
                    : myr(current!.amount!),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 12),
          SummaryCards(
            first: SummaryMetric(
              title: 'Vehicle Plate',
              value: current.plate,
              icon: Icons.directions_car_outlined,
            ),
            second: SummaryMetric(
              title: 'Parking Duration',
              value: current.duration == null
                  ? 'Unavailable'
                  : MalaysianDateTime.formatDuration(current.duration!),
              icon: Icons.timer_outlined,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: expired
                    ? const Color(0xFF9A3412)
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expired
                          ? 'Quotation Expired At'
                          : 'Quotation Valid Until',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current.expiresAt == null
                          ? 'Not Quoted'
                          : MalaysianDateTime.format(current.expiresAt!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ExpansionTile(
              key: PageStorageKey('checkout-tariff-details-${current.id}'),
              backgroundColor: AppTheme.background,
              collapsedBackgroundColor: AppTheme.background,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Tariff and Session Details',
                style: theme.textTheme.titleSmall,
              ),
              children: [
                _DetailSection(
                  title: 'Session',
                  icon: Icons.receipt_long_outlined,
                  rows: [
                    ('Parking Session', current.sessionId),
                    ('Payment Reference', reference ?? current.id),
                    ('Entry Time', MalaysianDateTime.format(current.entryTime)),
                    if (current.throughAt != null)
                      (
                        'Parking Calculated Until',
                        MalaysianDateTime.format(current.throughAt!),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _DetailSection(
                  title: 'Tariff',
                  icon: Icons.sell_outlined,
                  rows: [
                    (
                      'Initial Charge',
                      '${myr(paymentInt(current.tariff['initial_charge_sen']))} / ${current.tariff['initial_duration_minutes']} Min',
                    ),
                    (
                      'Subsequent Hourly Rate',
                      '${myr(paymentInt(current.tariff['subsequent_hourly_rate_sen']))} / Hr',
                    ),
                    ('Rounding', '${current.tariff['rounding_minutes']} Min'),
                    ('Grace Period', '${current.tariff['grace_minutes']} Min'),
                    (
                      'Maximum Charge',
                      current.tariff['maximum_charge_sen'] == null
                          ? 'No Maximum'
                          : myr(
                              paymentInt(current.tariff['maximum_charge_sen']),
                            ),
                    ),
                    ('Tariff Version', '${current.tariff['version_number']}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.rows,
  });
  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _DetailRow(label: rows[i].$1, value: rows[i].$2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final identifier =
          label == 'Parking Session' || label == 'Payment Reference';
      final stacked =
          identifier ||
          constraints.maxWidth < 240 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final caption = Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
      final detail = SelectableText(
        value,
        key: PageStorageKey(('checkout-detail', label, value)),
        textAlign: stacked ? TextAlign.start : TextAlign.end,
        style:
            (identifier
                    ? theme.textTheme.bodySmall
                    : theme.textTheme.bodyMedium)
                ?.copyWith(fontWeight: FontWeight.w500),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [caption, const SizedBox(height: 4), detail],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: caption),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: detail),
                ],
              ),
      );
    },
  );
}

class RenewQuotationCard extends StatelessWidget {
  const RenewQuotationCard({required this.onRenew, super.key});
  final VoidCallback? onRenew;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF7ED),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      side: const BorderSide(color: Color(0xFFFED7AA)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFFFEDD5),
                child: Icon(
                  Icons.update_rounded,
                  size: 20,
                  color: Color(0xFF9A3412),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quotation Expired',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: const Color(0xFF9A3412)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRenew,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Renew Quotation'),
          ),
        ],
      ),
    ),
  );
}

/// Bank-themed illustrations for the existing fictional gateway profiles.
/// The profile ID sent to checkout and its simulated outcome remain unchanged.
class TestCardOption extends StatelessWidget {
  const TestCardOption({
    required this.profile,
    required this.selected,
    required this.onSelect,
    super.key,
  });
  final FictionalCard profile;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bank, label, color, ink) = switch (profile.id) {
      'vp_demo_approved' => (
        'Maybank',
        'Maybank Debit',
        const Color(0xFFFFC928),
        const Color(0xFF172B45),
      ),
      'vp_demo_declined' => (
        'AmBank',
        'AmBank Debit',
        const Color(0xFFD92736),
        Colors.white,
      ),
      'vp_demo_failed' => (
        'CIMB',
        'CIMB Debit',
        const Color(0xFF8C1735),
        Colors.white,
      ),
      'vp_demo_interrupted' => (
        'Public Bank',
        'Public Bank Debit',
        const Color(0xFFBE2732),
        Colors.white,
      ),
      'vp_demo_pending' => (
        'RHB',
        'RHB Debit',
        const Color(0xFF087CA7),
        Colors.white,
      ),
      _ => ('VisionPark', profile.label, AppTheme.blue, Colors.white),
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: onSelect != null,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? AppTheme.blueSoft : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 64,
                    height: 42,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, Color.lerp(color, Colors.black, .22)!],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          bank,
                          maxLines: 1,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 11,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE4A0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Icon(
                              Icons.contactless_outlined,
                              size: 12,
                              color: ink.withValues(alpha: .8),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
