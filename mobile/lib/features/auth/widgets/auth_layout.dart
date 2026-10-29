import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../shared/vision_park_brand.dart';

/// Shared presentation for authentication forms and account-status feedback.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.title,
    required this.child,
    this.description = '',
    this.icon,
    this.inlineHeading = false,
    this.centered = false,
    this.showBrand = false,
    this.showBackButton = true,
    this.onBack,
    this.maxWidth = 360,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final IconData? icon;
  final bool inlineHeading;
  final bool centered;
  final bool showBrand;
  final bool showBackButton;
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
        backgroundColor: centered ? AppTheme.background : Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: !centered && showBackButton,
          leading: centered || !showBackButton || onBack == null
              ? null
              : BackButton(onPressed: onBack),
          title: const VisionParkBrand(),
        ),
        body: SafeArea(
          child: centered
              ? _CenteredAuthForm(
                  title: title,
                  description: description,
                  maxWidth: maxWidth,
                  showBrand: showBrand,
                  child: child,
                )
              : SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (inlineHeading && icon != null) ...[
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
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ] else ...[
                            if (icon != null) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Icon(
                                  icon,
                                  size: 36,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.large),
                            ],
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineMedium,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.small),
                          ],
                          if (description.isNotEmpty) Text(description),
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

/// A centered form panel below the shared VisionPark app bar.
class _CenteredAuthForm extends StatelessWidget {
  const _CenteredAuthForm({
    required this.title,
    required this.description,
    required this.maxWidth,
    required this.showBrand,
    required this.child,
  });

  final String title;
  final String description;
  final double maxWidth;
  final bool showBrand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (viewport.maxHeight - 56).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth + 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(
                        AppTheme.cornerRadius,
                      ),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.navy.withValues(alpha: .05),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showBrand) ...[
                          Semantics(
                            label: 'VisionPark',
                            image: true,
                            excludeSemantics: true,
                            child: Transform.translate(
                              offset: const Offset(-8, 0),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  const VisionParkFalcon(width: 72),
                                  Text(
                                    'VisionPark',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontSize: 28,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.large),
                        ],
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.small),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.large),
                        child,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
