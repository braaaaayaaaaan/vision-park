import 'package:flutter/material.dart';

/// Makes retained snapshots explicit without replacing independently ready UI.
class RefreshNotice extends StatelessWidget {
  const RefreshNotice({
    required this.refreshing,
    required this.error,
    required this.onRetry,
    super.key,
  });
  final bool refreshing;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!refreshing && error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refreshing) const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            refreshing ? 'Updating… Showing last verified information.' : 'Unable to refresh. Showing last verified information; the current status is unconfirmed.',
          ),
          if (!refreshing)
            TextButton(onPressed: onRetry, child: const Text('Try Again')),
        ],
      ),
    );
  }
}
