import 'package:flutter/material.dart';

import '../../data/models/payment_models.dart';
import 'payments_controller.dart';

/// UI conversion only. The existing API remains authoritative (1–100,000,000 sen).
int topUpAmountSen(String input) {
  final text = input.trim();
  if (!RegExp(r'^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(text)) {
    throw const FormatException(
      'Enter an RM amount with up to two decimal places.',
    );
  }
  final parts = text.split('.');
  final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null || whole > 1000000) {
    throw const FormatException(
      'Enter an amount from RM 0.01 to RM 1,000,000.00.',
    );
  }
  final cents = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final amount = whole * 100 + cents;
  if (amount < 1 || amount > 100000000) {
    throw const FormatException(
      'Enter an amount from RM 0.01 to RM 1,000,000.00.',
    );
  }
  return amount;
}

Future<void> showWalletTopUp(
  BuildContext context,
  PaymentsController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _TopUpSheet(controller: controller),
);

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet({required this.controller});
  final PaymentsController controller;
  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  late final TextEditingController _amount;
  final _form = GlobalKey<FormState>();
  bool _confirming = false, _submitted = false;
  int? _pendingAmount;

  @override
  void initState() {
    super.initState();
    _pendingAmount = widget.controller.topUpOperation?['amount_sen'] as int?;
    _amount = TextEditingController(
      text: _pendingAmount == null ? '20.00' : _decimal(_pendingAmount!),
    );
    widget.controller.addListener(_restoreAmount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refresh();
    });
  }

  String _decimal(int sen) =>
      '${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';

  void _restoreAmount() {
    final pending = widget.controller.topUpOperation?['amount_sen'] as int?;
    if (pending != null && pending != _pendingAmount) {
      _amount.text = _decimal(pending);
    }
    _pendingAmount = pending;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_restoreAmount);
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final controller = widget.controller;
    if (_confirming ||
        controller.busy ||
        controller.loading ||
        !controller.isCurrentOwner) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    final amount = topUpAmountSen(_amount.text);
    setState(() => _confirming = true);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Confirm Top Up'),
          content: Text('Add ${myr(amount)} to your wallet?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Top Up'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        setState(() => _submitted = true);
        await controller.topUp(amount);
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final busy = _confirming || controller.busy || controller.loading;
      final recovering = controller.topUpOperation != null;
      final ready =
          !busy &&
          controller.isCurrentOwner &&
          controller.wallet != null &&
          controller.error == null;
      final theme = Theme.of(context);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Top Up',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close Top Up',
                        onPressed: _confirming || controller.busy
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.wallet == null
                        ? 'Balance Unavailable'
                        : 'Wallet Balance ${myr(controller.wallet!.balance)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const ValueKey('top-up-amount'),
                    controller: _amount,
                    enabled: ready && !recovering,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'RM ',
                      hintText: '0.00',
                      errorMaxLines: 3,
                      border: OutlineInputBorder(),
                    ),
                    style: theme.textTheme.headlineSmall,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      try {
                        topUpAmountSen(value ?? '');
                        return null;
                      } on FormatException catch (error) {
                        return error.message;
                      }
                    },
                    onFieldSubmitted: (_) => ready ? _confirm() : null,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final amount in [20, 50, 100])
                        ActionChip(
                          label: Text('RM$amount'),
                          onPressed: ready && !recovering
                              ? () => _amount.text = '$amount.00'
                              : null,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: .06,
                          ),
                          side: BorderSide(
                            color: theme.colorScheme.primary.withValues(
                              alpha: .16,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                        ),
                    ],
                  ),
                  if (recovering) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Check your previous top-up before adding another amount.',
                    ),
                  ],
                  if (controller.busy || controller.loading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Processing Top Up',
                    ),
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 16),
                    Text(controller.error!),
                    TextButton(
                      onPressed: busy ? null : () => controller.refresh(),
                      child: const Text('Try Again'),
                    ),
                  ],
                  if (_submitted && controller.actionMessage != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        controller.actionMessage!,
                        style: controller.actionSucceeded
                            ? const TextStyle(color: Color(0xFF24613D))
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('top-up-submit'),
                    onPressed: ready ? _confirm : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    child: Text(recovering ? 'Retry Top Up' : 'Continue'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
