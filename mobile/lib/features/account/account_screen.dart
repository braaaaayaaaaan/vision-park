import 'package:flutter/material.dart';

import '../../data/models/driver_models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/password_change.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../payments/payments_controller.dart';
import '../payments/payments_screen.dart';
import '../payments/wallet_cards.dart';
import 'account_controller.dart';
import 'change_password_screen.dart';
import 'widgets/account_confirmation.dart';
import 'widgets/account_settings_card.dart';
import 'widgets/profile_details.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.onVehiclesSelected,
    this.controller,
    this.profile,
    this.passwordChange,
    this.onSignOut,
    this.paymentsController,
    this.isVisible = true,
    this.onPaymentChanged,
    super.key,
  });
  final VoidCallback onVehiclesSelected;
  final AccountController? controller;
  final AuthProfile? profile;
  final PasswordChangeService? passwordChange;
  final Future<void> Function()? onSignOut;
  final PaymentsController? paymentsController;
  final bool isVisible;
  final VoidCallback? onPaymentChanged;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountController _controller;
  bool _signingOut = false;
  bool _changing = false;
  bool _openingWallet = false;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AccountController();
    if (widget.profile == null) _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    if (_signingOut || widget.onSignOut == null) return;
    setState(() => _signingOut = true);
    try {
      if (await confirmAccountAction(context, signOut: true) && mounted) {
        await widget.onSignOut!();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _changePassword() async {
    if (_changing || _signingOut || widget.passwordChange == null) return;
    setState(() => _changing = true);
    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(service: widget.passwordChange!),
        ),
      );
      if (changed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _openWallet([
    WalletDestination destination = WalletDestination.overview,
  ]) async {
    final payments = widget.paymentsController;
    if (payments == null || _openingWallet) return;
    _openingWallet = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaymentsScreen(
            controller: payments,
            initialDestination: destination,
            onChanged: widget.onPaymentChanged,
          ),
        ),
      );
      if (mounted) widget.onPaymentChanged?.call();
    } finally {
      _openingWallet = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final authenticated = widget.profile;
      final profile = authenticated == null
          ? _controller.profile
          : DriverProfile(
              id: authenticated.id,
              fullName: authenticated.fullName,
              email: authenticated.email,
              tenantName: authenticated.companyName,
              isActive: authenticated.isActive,
            );
      final status = authenticated == null
          ? null
          : !authenticated.isActive
          ? 'Inactive'
          : switch (authenticated.approvalStatus) {
              'approved' => 'Approved',
              'pending' => 'Pending Approval',
              'rejected' => 'Rejected',
              _ => 'Unavailable',
            };
      Widget heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Semantics(
          header: true,
          child: Text(text, style: theme.textTheme.titleMedium),
        ),
      );
      return SingleChildScrollView(
        key: const PageStorageKey('account'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFEAF2FC),
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Account',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage your profile and security',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                heading('Personal Information'),
                if (profile != null)
                  Card(
                    margin: EdgeInsets.zero,
                    child: ProfileDetails(
                      profile: profile,
                      statusLabel: status,
                    ),
                  )
                else if (_controller.status == AccountStatus.loading) ...[
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading Account',
                  ),
                  const SizedBox(height: 8),
                  const Text('Loading Account'),
                ] else if (_controller.status == AccountStatus.error) ...[
                  const EmptyStateCard(
                    icon: Icons.info_outline,
                    title: 'Unable to Load Account',
                    message: 'Your account information could not be confirmed. Please try again.',
                  ),
                  TextButton(
                    onPressed: _controller.load,
                    child: const Text('Try Again'),
                  ),
                ] else
                  const EmptyStateCard(
                    icon: Icons.person_outline_rounded,
                    title: 'Your Profile Will Appear Here',
                    message: 'Not Connected. Sign in to view your profile.',
                  ),
                if (widget.paymentsController != null) ...[
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: widget.paymentsController!,
                    builder: (context, _) => WalletAccountCard(
                      balance: widget.paymentsController!.wallet?.balance,
                      loading: widget.paymentsController!.loading,
                      unavailable:
                          widget.paymentsController!.error != null ||
                          !widget.paymentsController!.isCurrentOwner,
                      onOpen: () => _openWallet(),
                      onTransactions: () =>
                          _openWallet(WalletDestination.transactions),
                      onSettings: () => _openWallet(WalletDestination.settings),
                    ),
                  ),
                ],
                heading('Security'),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    minTileHeight: 64,
                    minVerticalPadding: 8,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: SizedBox(
                      width: 24,
                      child: Icon(
                        Icons.lock_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: const Text('Change Password'),
                    subtitle: const Text('Update your account password'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        widget.passwordChange == null ||
                            _signingOut ||
                            _changing
                        ? null
                        : _changePassword,
                  ),
                ),
                heading('Account Actions'),
                AccountSettingsCard(
                  onVehiclesSelected: widget.onVehiclesSelected,
                  onSignOut: widget.onSignOut == null ? null : _signOut,
                  busy: _signingOut,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
