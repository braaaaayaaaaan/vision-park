import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/models/payment_models.dart';

/// The same balance presentation serves Home and the full wallet.
class WalletBalanceCard extends StatelessWidget {
  const WalletBalanceCard({
    required this.balance,
    this.loading = false,
    this.unavailable = false,
    this.compact = false,
    this.onOpen,
    this.onTopUp,
    super.key,
  });

  final int? balance;
  final bool loading, unavailable, compact;
  final VoidCallback? onOpen, onTopUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = compact ? theme.colorScheme.primary : Colors.white;
    final muted = compact
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white.withValues(alpha: .82);
    final value = unavailable
        ? 'Balance Unavailable'
        : balance != null
        ? myr(balance!)
        : loading
        ? 'Loading…'
        : 'Balance Unavailable';
    final balanceContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wallet Balance',
          style: theme.textTheme.labelLarge?.copyWith(color: muted),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style:
              (compact
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.headlineLarge)
                  ?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
        ),
      ],
    );
    return Card(
      color: compact ? theme.colorScheme.surface : theme.colorScheme.primary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
        side: compact
            ? BorderSide(color: theme.colorScheme.outlineVariant)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.all(compact ? 18 : 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal =
                  compact &&
                  constraints.maxWidth >= 280 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              final topUp = onTopUp == null
                  ? null
                  : FilledButton.icon(
                      onPressed: onTopUp,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Top Up'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'VisionPark Wallet',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          color: foreground,
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (horizontal)
                    Row(
                      children: [
                        Expanded(child: balanceContent),
                        if (topUp != null) ...[
                          const SizedBox(width: 12),
                          topUp,
                        ],
                      ],
                    )
                  else ...[
                    balanceContent,
                    if (topUp != null) ...[
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: topUp),
                    ],
                  ],
                  if (loading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: foreground,
                      backgroundColor: foreground.withValues(alpha: .15),
                      semanticsLabel: 'Refreshing Wallet Balance',
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class WalletAccountCard extends StatelessWidget {
  const WalletAccountCard({
    required this.balance,
    required this.onOpen,
    required this.onTransactions,
    required this.onSettings,
    this.loading = false,
    this.unavailable = false,
    super.key,
  });

  final int? balance;
  final bool loading, unavailable;
  final VoidCallback onOpen, onTransactions, onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: .08),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            title: const Text('Wallet & Payments'),
            subtitle: Text(
              unavailable
                  ? 'Balance Unavailable'
                  : balance != null
                  ? myr(balance!)
                  : loading
                  ? 'Loading…'
                  : 'Open Wallet',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpen,
          ),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onTransactions,
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('Transactions'),
                ),
                TextButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Payment Settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
