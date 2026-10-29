import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import 'payment_widgets.dart';
import 'checkout_widgets.dart';
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
          color: Theme.of(context).colorScheme.onPrimary,
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
            CheckoutSummary(
              charge: charge,
              reference: attempt?.reference,
              expired: request?.quoteState == 'expired',
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
                children: [Text('Parking payments are not activated.')],
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
                  if (attempt.inFlight || attempt.status == 'succeeded')
                    FilledButton(
                      onPressed: controller.busy || request?.meta.active != true
                          ? null
                          : controller.verify,
                      child: const Text('Check Payment Status'),
                    ),
                ],
              ),
            if (request?.quoteState == 'expired' && !controller.unresolved)
              RenewQuotationCard(
                onRenew: controller.busy || !request!.meta.active
                    ? null
                    : controller.renew,
              ),
            if (charge?.status == 'open')
              const Text('Payment will be available at exit.'),
            if (attempt?.inFlight != true && charge?.status == 'pending') ...[
              const SizedBox(height: 16),
              PaymentPanel(
                children: [
                  Text(
                    'Select a Test Card',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final profile in controller.profiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TestCardOption(
                        profile: profile,
                        selected: controller.selectedProfile == profile.id,
                        onSelect: controller.busy || controller.unresolved
                            ? null
                            : () => controller.select(profile.id),
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
