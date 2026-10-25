import 'package:flutter/material.dart';

import '../../../app/app_config.dart';
import '../../../app/app_theme.dart';

/// Shared presentation for authentication forms and account-status feedback.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.title,
    required this.description,
    required this.child,
    this.icon = Icons.local_parking_rounded,
    this.inlineHeading = false,
    this.onBack,
    this.maxWidth = 360,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final IconData icon;
  final bool inlineHeading;
  final VoidCallback? onBack;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F8FC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
          ),
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
          errorStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w400,
            height: 1.35,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: border.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.error),
          ),
          focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          errorMaxLines: 4,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle()).merge(
            FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).merge(
            OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: onBack == null ? null : BackButton(onPressed: onBack),
          backgroundColor: Colors.white,
          title: const Text(AppConfig.name),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inlineHeading) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              icon,
                              size: 28,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          icon,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.large),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.small),
                    ],
                    Text(description),
                    const SizedBox(height: AppSpacing.large),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
