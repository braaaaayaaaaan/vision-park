import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import 'payment_widgets.dart';
import 'payments_controller.dart';
import 'receipt_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    required this.payments,
    required this.chargeId,
    super.key,
  });
  final PaymentsController payments;
  final String chargeId;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  late final CheckoutController controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = CheckoutController(widget.payments, widget.chargeId);
    unawaited(controller.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.resume();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('VisionPark Checkout'),
      actions: [
        IconButton(
          tooltip: 'Refresh Payment',
          onPressed: controller.busy ? null : controller.load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: Listenable.merge([controller, widget.payments]),
      builder: (context, _) {
        if (!widget.payments.isCurrentOwner) {
          return const Center(
            child: Text('Sign in again to view this payment.'),
          );
        }
        if (controller.receipt != null) {
          return ReceiptContent(transaction: controller.receipt!);
        }
        final request = controller.request;
        final charge = request?.charge;
        final attempt = controller.attempt;
        final canPay =
            !controller.busy &&
            request?.meta.active == true &&
            charge?.status == 'pending' &&
            (request?.quoteState == 'valid' || controller.operation != null) &&
            attempt?.inFlight != true;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.medium),
          children: [
            PaymentPanel(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_parking_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'VisionPark',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const Text('Parking Payment · MYR'),
                const SimulationNotice(),
                if (charge != null) ...[
                  Text(
                    charge.amount == null
                        ? 'Awaiting Quotation'
                        : myr(charge.amount!),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  PaymentField('Vehicle Plate', charge.plate),
                  PaymentField(
                    'Parking Duration',
                    charge.duration == null
                        ? 'Unavailable'
                        : MalaysianDateTime.formatDuration(charge.duration!),
                  ),
                  PaymentField(
                    'Payment Reference',
                    attempt?.reference ?? charge.id,
                  ),
                  PaymentField(
                    'Quotation Valid Until',
                    charge.expiresAt == null
                        ? 'Not Quoted'
                        : MalaysianDateTime.format(charge.expiresAt!),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Tariff and Session Details'),
                    children: [
                      PaymentField('Parking Session', charge.sessionId),
                      PaymentField(
                        'Entry Time',
                        MalaysianDateTime.format(charge.entryTime),
                      ),
                      PaymentField(
                        'Tariff Version',
                        '${charge.tariff['version_number']}',
                      ),
                      PaymentField(
                        'Initial Charge',
                        '${myr(paymentInt(charge.tariff['initial_charge_sen']))} / ${charge.tariff['initial_duration_minutes']} Min',
                      ),
                      PaymentField(
                        'Subsequent Hourly Rate',
                        myr(
                          paymentInt(
                            charge.tariff['subsequent_hourly_rate_sen'],
                          ),
                        ),
                      ),
                      PaymentField(
                        'Rounding / Grace',
                        '${charge.tariff['rounding_minutes']} Min / ${charge.tariff['grace_minutes']} Min',
                      ),
                      PaymentField(
                        'Maximum Charge',
                        charge.tariff['maximum_charge_sen'] == null
                            ? 'No Maximum'
                            : myr(
                                paymentInt(charge.tariff['maximum_charge_sen']),
                              ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (controller.busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Processing Payment',
              ),
            if (controller.error != null)
              PaymentPanel(
                children: [
                  Text(controller.error!),
                  TextButton(
                    onPressed: controller.busy ? null : controller.load,
                    child: const Text('Check Payment Status'),
                  ),
                ],
              ),
            if (request != null && !request.meta.active)
              const PaymentPanel(
                children: [
                  Text(
                    'Parking payments are not activated.',
                  ),
                ],
              ),
            if (attempt != null)
              PaymentPanel(
                children: [
                  Text(switch (attempt.status) {
                    'unknown' => 'Payment Status Uncertain',
                    'processing' => 'Payment Processing',
                    'declined' => 'Payment Declined',
                    'failed' => 'Payment Unsuccessful',
                    _ => 'Verifying Receipt',
                  }, style: Theme.of(context).textTheme.titleMedium),
                  Text(switch (attempt.status) {
                    'unknown' => 'Check this payment before paying again.',
                    'processing' => 'Payment is not confirmed yet. Check its status before trying again.',
                    'declined' => 'Choose another test card. Your parking session is still active.',
                    'failed' => 'Please try again. Your parking session is still active.',
                    _ => 'Payment received. Check its status to view your receipt.',
                  }),
                  if (attempt.inFlight || attempt.status == 'succeeded')
                    FilledButton(
                      onPressed: controller.busy || request?.meta.active != true
                          ? null
                          : controller.verify,
                      child: Text(
                        attempt.status == 'unknown'
                            ? 'Check Payment Status'
                            : 'Check Payment Status',
                      ),
                    ),
                ],
              ),
            if (request?.quoteState == 'expired' && !controller.unresolved)
              PaymentPanel(
                children: [
                  const Text(
                    'Your quotation expired. Renew it before paying.',
                  ),
                  FilledButton(
                    onPressed: controller.busy || !request!.meta.active
                        ? null
                        : controller.renew,
                    child: const Text('Renew Quotation'),
                  ),
                ],
              ),
            if (charge?.status == 'open')
              const Text(
                'Payment will be available at exit.',
              ),
            if (attempt?.inFlight != true && charge?.status == 'pending') ...[
              const SizedBox(height: 16),
              PaymentPanel(
                children: [
                  Text(
                    'Select a Test Card',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'No card numbers or security codes needed.',
                  ),
                  const SizedBox(height: 12),
                  for (final profile in controller.profiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: controller.selectedProfile == profile.id
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          leading: const Icon(Icons.credit_card_rounded),
                          title: Text('${profile.label} · ${profile.lastFour}'),
                          subtitle: Text(profile.hint),
                          trailing: controller.selectedProfile == profile.id
                              ? const Icon(Icons.check_circle_outline)
                              : null,
                          onTap: controller.busy || controller.unresolved
                              ? null
                              : () => controller.select(profile.id),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: canPay && controller.selectedProfile != null
                        ? () => controller.pay()
                        : null,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(
                      controller.operation != null
                          ? 'Retry Payment'
                          : 'Pay ${charge?.amount == null ? '' : myr(charge!.amount!)}',
                    ),
                  ),
                  if (widget.payments.wallet?.automatic == true &&
                      controller.operation == null)
                    OutlinedButton(
                      onPressed: canPay
                          ? () => controller.pay(wallet: true)
                          : null,
                      child: const Text('Pay With Wallet'),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}
