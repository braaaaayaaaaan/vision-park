import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';
import '../../shared/formatting/malaysian_date_time.dart';
import 'payments_controller.dart';
import 'payment_widgets.dart';
import 'checkout_screen.dart';
import 'receipt_screen.dart';
import 'top_up_sheet.dart';
import 'wallet_cards.dart';
import 'transaction_history_screen.dart';
import 'transaction_entry.dart';
import '../../shared/visible_poller.dart';

enum WalletDestination { overview, topUp, transactions, settings, receipts }

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    required this.controller,
    this.onChanged,
    this.embedded = false,
    this.isVisible = true,
    this.initialDestination = WalletDestination.overview,
    super.key,
  });
  final PaymentsController controller;
  final VoidCallback? onChanged;
  final bool embedded, isVisible;
  final WalletDestination initialDestination;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with WidgetsBindingObserver {
  PaymentsController get controller => widget.controller;
  bool _openingCheckout = false, _openingAction = false;
  late final VisiblePoller _poller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poller = VisiblePoller(
      refresh: () => controller.refresh(history: true, background: true),
      isVisible: () =>
          mounted &&
          widget.isVisible &&
          !_openingCheckout &&
          !_openingAction &&
          controller.isCurrentOwner &&
          ModalRoute.of(context)?.isCurrent != false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isVisible) unawaited(_refresh());
      if (widget.initialDestination != WalletDestination.overview) {
        unawaited(_openAction(widget.initialDestination));
      }
    });
  }

  Future<void> _refresh() async {
    await controller.refresh(history: true, background: true);
  }

  @override
  void didUpdateWidget(covariant PaymentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isVisible) unawaited(_refresh());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isVisible) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  Future<void> _checkout(ParkingCharge charge) async {
    if (_openingCheckout) return;
    _openingCheckout = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CheckoutScreen(payments: controller, chargeId: charge.id),
        ),
      );
      if (mounted) {
        await controller.refresh(history: true);
        widget.onChanged?.call();
      }
    } finally {
      _openingCheckout = false;
    }
  }

  Future<void> _openAction(WalletDestination destination) async {
    if (_openingAction || !controller.isCurrentOwner) return;
    _openingAction = true;
    try {
      switch (destination) {
        case WalletDestination.overview:
          break;
        case WalletDestination.topUp:
          await showWalletTopUp(context, controller);
        case WalletDestination.transactions:
          await _openActivity();
        case WalletDestination.receipts:
          await _openActivity(receipts: true);
        case WalletDestination.settings:
          await showModalBottomSheet<void>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _PaymentSettings(controller: controller),
          );
      }
      if (mounted) widget.onChanged?.call();
    } finally {
      _openingAction = false;
    }
  }

  Future<void> _openActivity({bool receipts = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => receipts
              ? _WalletActivity(controller: controller, receipts: true)
              : TransactionHistoryScreen(payments: controller),
        ),
      );

  Widget _section(
    String title,
    List<Widget> children, {
    VoidCallback? onViewAll,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (onViewAll != null)
              TextButton(onPressed: onViewAll, child: const Text('View All')),
          ],
        ),
      ),
      PaymentPanel(children: children),
    ],
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      controller.loading
          ? 'Loading…'
          : controller.error != null
          ? 'Unable to load. Try again.'
          : text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isCurrentOwner) {
          return const Center(
            child: Text('Sign in again to access your payments.'),
          );
        }
        final entries = controller.entries.take(3).toList();
        final receipts = controller.receipts.take(3).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.contentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WalletBalanceCard(
                      balance: controller.wallet?.balance,
                      loading: controller.loading,
                      unavailable: controller.error != null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WalletAction(
                          icon: Icons.add_rounded,
                          label: 'Top Up',
                          onTap: () => _openAction(WalletDestination.topUp),
                        ),
                        _WalletAction(
                          icon: Icons.swap_vert_rounded,
                          label: 'Transactions',
                          onTap: () =>
                              _openAction(WalletDestination.transactions),
                        ),
                        _WalletAction(
                          icon: Icons.tune_rounded,
                          label: 'Payment Settings',
                          onTap: () => _openAction(WalletDestination.settings),
                        ),
                      ],
                    ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 16),
                      Text(controller.error!),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _refresh,
                          child: const Text('Try Again'),
                        ),
                      ),
                    ],
                    if (controller.wallet != null && !controller.active) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Parking payments are not activated.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _section('Pending Payments', [
                      if (controller.pending.isEmpty)
                        _empty('No pending payments.'),
                      for (
                        var index = 0;
                        index < controller.pending.length;
                        index++
                      ) ...[
                        if (index > 0) ...[
                          const Divider(),
                          const SizedBox(height: 16),
                        ],
                        PaymentRequiredCard(
                          charge: controller.pending[index],
                          inline: true,
                          onOpen: () => _checkout(controller.pending[index]),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 24),
                    _section(
                      'Recent Transactions',
                      [
                        if (entries.isEmpty) _empty('No transactions yet.'),
                        for (
                          var index = 0;
                          index < entries.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(),
                          TransactionEntry(
                            payments: controller,
                            entry: entries[index],
                            showDate: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ],
                      ],
                      onViewAll: () =>
                          _openAction(WalletDestination.transactions),
                    ),
                    const SizedBox(height: 24),
                    _section(
                      'Payment Receipts',
                      [
                        if (receipts.isEmpty) _empty('No receipts yet.'),
                        for (
                          var index = 0;
                          index < receipts.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(),
                          _receiptEntry(context, controller, receipts[index]),
                        ],
                      ],
                      onViewAll: () => _openAction(WalletDestination.receipts),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet and Payments'),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => IconButton(
              tooltip: 'Refresh Payments',
              onPressed: controller.loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }
}

class _WalletAction extends StatelessWidget {
  const _WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('wallet-action-$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PaymentSettings extends StatelessWidget {
  const _PaymentSettings({required this.controller});
  final PaymentsController controller;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Payment Settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close Payment Settings',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (!controller.isCurrentOwner)
            const Text('Sign in again to access your payments.')
          else if (controller.wallet == null) ...[
            const Text('Payment settings are unavailable.'),
            TextButton(
              onPressed: controller.loading ? null : () => controller.refresh(),
              child: const Text('Try Again'),
            ),
          ] else ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic Payment'),
              subtitle: const Text(
                'Use your wallet at exit when you have enough balance.',
              ),
              value: controller.wallet!.automatic,
              onChanged: controller.busy ? null : controller.setAutomatic,
            ),
            if (controller.busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Saving Payment Settings',
              ),
            if (controller.actionMessage != null)
              Text(
                controller.actionMessage!,
                style: controller.actionSucceeded
                    ? const TextStyle(color: Color(0xFF24613D))
                    : null,
              ),
          ],
        ],
      ),
    ),
  );
}

class _WalletActivity extends StatefulWidget {
  const _WalletActivity({required this.controller, required this.receipts});
  final PaymentsController controller;
  final bool receipts;
  @override
  State<_WalletActivity> createState() => _WalletActivityState();
}

class _WalletActivityState extends State<_WalletActivity> {
  bool _loading = false;
  late final VisiblePoller _poller;
  @override
  void initState() {
    super.initState();
    _poller = VisiblePoller(
      refresh: () => widget.receipts
          ? widget.controller.loadReceipts(reset: true, preserveCount: true)
          : widget.controller.loadEntries(reset: true, preserveCount: true),
      isVisible: () =>
          mounted &&
          !_loading &&
          widget.controller.isCurrentOwner &&
          ModalRoute.of(context)?.isCurrent != false,
    );
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (reset) {
        await widget.controller.refresh(history: true);
      } else if (widget.receipts) {
        await widget.controller.loadReceipts();
      } else {
        await widget.controller.loadEntries();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.receipts ? 'Payment Receipts' : 'Transaction History'),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          if (!controller.isCurrentOwner) {
            return const Center(
              child: Text('Sign in again to access your payments.'),
            );
          }
          final empty = widget.receipts
              ? controller.receipts.isEmpty
              : controller.entries.isEmpty;
          final more = widget.receipts
              ? controller.moreReceipts
              : controller.moreEntries;
          return RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.contentWidth,
                  ),
                  child: PaymentPanel(
                    children: [
                      if (controller.loading || _loading)
                        const LinearProgressIndicator(),
                      if (controller.error != null) ...[
                        Text(controller.error!),
                        TextButton(
                          onPressed: _loading || controller.loading
                              ? null
                              : () => _load(reset: true),
                          child: const Text('Try Again'),
                        ),
                      ] else if (empty)
                        Text(
                          controller.loading
                              ? 'Loading…'
                              : widget.receipts
                              ? 'No receipts yet.'
                              : 'No transactions yet.',
                        ),
                      if (widget.receipts)
                        for (
                          var index = 0;
                          index < controller.receipts.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(),
                          _receiptEntry(
                            context,
                            controller,
                            controller.receipts[index],
                          ),
                        ]
                      else
                        for (
                          var index = 0;
                          index < controller.entries.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(),
                          TransactionEntry(
                            payments: controller,
                            entry: controller.entries[index],
                            showDate: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ],
                      if (more)
                        TextButton(
                          onPressed: _loading || controller.loading
                              ? null
                              : () => _load(),
                          child: Text(
                            widget.receipts
                                ? 'Load More Receipts'
                                : 'Load More Transactions',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _receiptEntry(
  BuildContext context,
  PaymentsController controller,
  PaymentTransaction receipt,
) => ListTile(
  contentPadding: EdgeInsets.zero,
  leading: CircleAvatar(
    backgroundColor: Theme.of(context).colorScheme.primary
        .withValues(alpha: .08),
    child: Icon(
      Icons.receipt_long_outlined,
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
  title: Text(receipt.charge.plate),
  subtitle: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        myr(receipt.attempt.amount),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      Text(receipt.attempt.receiptNumber!),
      Text(MalaysianDateTime.format(receipt.attempt.settledAt!)),
    ],
  ),
  trailing: const Icon(Icons.chevron_right_rounded),
  onTap: () => openReceipt(context, controller, receipt.attempt.id),
);
