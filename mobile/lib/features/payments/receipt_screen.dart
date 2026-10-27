import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../data/repositories/payment_repository.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import 'payment_widgets.dart';
import 'payments_controller.dart';

Future<void> openReceipt(
  BuildContext context,
  PaymentsController payments,
  String attemptId,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ReceiptScreen(payments: payments, attemptId: attemptId),
  ),
);

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({
    required this.payments,
    this.attemptId,
    this.sessionId,
    super.key,
  });
  final PaymentsController payments;
  final String? attemptId, sessionId;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  PaymentTransaction? receipt;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      PaymentTransaction? found;
      if (widget.attemptId != null) {
        found = PaymentTransaction(
          await widget.payments.send('receipts/${widget.attemptId}'),
        );
        if (found.attempt.id != widget.attemptId) throw const FormatException();
      } else {
        var offset = 0;
        while (mounted) {
          final page = paymentPage(
            await widget.payments.send('receipts?limit=100&offset=$offset'),
            'receipts',
            PaymentTransaction.new,
          );
          found = page.items
              .where((item) => item.charge.sessionId == widget.sessionId)
              .firstOrNull;
          if (found != null || !page.hasMore) break;
          offset = page.nextOffset;
          if (offset > 1000000) throw const FormatException();
        }
      }
      if (found != null && !found.isReceipt) throw const FormatException();
      if (mounted) {
        setState(() {
          receipt = found;
          error = found == null
              ? 'No receipt found for this visit.'
              : null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = widget.payments.message(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment Receipt')),
    body: AnimatedBuilder(
      animation: widget.payments,
      builder: (context, _) {
        if (!widget.payments.isCurrentOwner) {
          return const Center(
            child: Text('Sign in again to view your receipt.'),
          );
        }
        if (loading) return const Center(child: CircularProgressIndicator());
        if (error != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(error!),
                TextButton(onPressed: _load, child: const Text('Try Again')),
              ],
            ),
          );
        }
        return ReceiptContent(transaction: receipt!);
      },
    ),
  );
}

class ReceiptContent extends StatelessWidget {
  const ReceiptContent({required this.transaction, super.key});
  final PaymentTransaction transaction;
  @override
  Widget build(BuildContext context) {
    if (!transaction.isReceipt) {
      return const Center(child: Text('Payment has not been confirmed.'));
    }
    final attempt = transaction.attempt;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.medium),
      children: [
        PaymentPanel(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Payment Successful',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              myr(attempt.amount),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SimulationNotice(),
            const Text(
              'Your parking session is complete.',
            ),
            PaymentField('Vehicle Plate', transaction.charge.plate),
            PaymentField('Payment Method', switch (attempt.method) {
              'wallet' => 'VisionPark Wallet',
              'zero' => 'No Charge',
              _ => 'Card Payment',
            }),
            PaymentField(
              'Payment and Exit Time',
              MalaysianDateTime.format(attempt.settledAt!),
            ),
            PaymentField('Receipt Number', attempt.receiptNumber!),
            PaymentField('Transaction Reference', attempt.reference),
            PaymentField('Parking Session', transaction.charge.sessionId),
            PaymentField(
              'Parking Duration',
              transaction.charge.duration == null
                  ? 'Unavailable'
                  : MalaysianDateTime.formatDuration(
                      transaction.charge.duration!,
                    ),
            ),
            PaymentField(
              'Tariff Version',
              '${transaction.charge.tariff['version_number']}',
            ),
          ],
        ),
      ],
    );
  }
}
