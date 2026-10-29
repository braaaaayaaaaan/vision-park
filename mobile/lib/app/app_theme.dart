import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reserved for parking occupancy, not general application or session status.
abstract final class OccupancyColours {
  static const available = Color(0xFF25804B);
  static const nearlyFull = Color(0xFFE0B326);
  static const full = Color(0xFFC53D3D);
}

abstract final class AppSpacing {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const extraLarge = 32.0;
}

abstract final class AppTheme {
  static const blue = Color(0xFF2563EB);
  static const white = Color(0xFFFFFFFF);
  static const navy = Color(0xFF0F1F3D);
  static const blueSoft = Color(0xFFEFF6FF);
  static const background = Color(0xFFF4F7FB);
  static const ink = Color(0xFF172B45);
  static const cornerRadius = 20.0;
  static const contentWidth = 640.0;

  static WidgetStateProperty<Color?> buttonOverlay({bool filled = false}) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        final colour = filled ? Colors.black : blue;
        if (states.contains(WidgetState.pressed)) {
          return colour.withValues(alpha: filled ? .24 : .20);
        }
        if (states.contains(WidgetState.hovered)) {
          return colour.withValues(alpha: .16);
        }
        if (states.contains(WidgetState.focused)) {
          return colour.withValues(alpha: .18);
        }
        return null;
      });

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
        ).copyWith(
          primary: blue,
          onPrimary: white,
          primaryContainer: const Color(0xFFDBEAFE),
          onPrimaryContainer: const Color(0xFF1E3A8A),
          surface: white,
          onSurface: ink,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      hoverColor: blue.withValues(alpha: .12),
      focusColor: blue.withValues(alpha: .16),
      highlightColor: blue.withValues(alpha: .18),
      splashColor: blue.withValues(alpha: .22),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(overlayColor: buttonOverlay(filled: true)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(overlayColor: buttonOverlay()),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(overlayColor: buttonOverlay()),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(overlayColor: buttonOverlay()),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: buttonOverlay()),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        hoverColor: blue.withValues(alpha: .16),
        focusColor: blue.withValues(alpha: .20),
        splashColor: blue.withValues(alpha: .24),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: blue,
        foregroundColor: white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: white,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: navy.withValues(alpha: .08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        overlayColor: buttonOverlay(),
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
