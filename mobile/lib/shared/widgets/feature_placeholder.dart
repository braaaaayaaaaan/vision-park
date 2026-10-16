import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'empty_state_card.dart';

/// An explicit unconnected state, not a successful query with zero records.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.title,
    required this.description,
    required this.icon,
    required this.emptyTitle,
    required this.emptyMessage,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.small),
                Text(description, style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.extraLarge),
                EmptyStateCard(
                  icon: icon,
                  title: emptyTitle,
                  message: emptyMessage,
                ),
                const SizedBox(height: AppSpacing.large),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.small),
                    Expanded(
                      child: Text(
                        'Not Connected\nLive parking data is not available in this version.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
