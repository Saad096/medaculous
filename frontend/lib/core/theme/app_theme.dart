import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Plain cross-fade for every route change — including go_router redirects
/// (splash to login/home, unauthenticated bounces), which the platform
/// default transitions handle inconsistently and which the owner reported
/// as "blinking" (2026-08-15) rather than a smooth handoff. A custom
/// PageTransitionsBuilder applies via ThemeData.pageTransitionsTheme to
/// every MaterialPage go_router builds, without touching each GoRoute.
class _FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

/// Light/dark themes built from the tokens extracted in DISCOVERY_REPORT.md §3.
/// Dark mode is a first-class citizen in the legacy app (manual toggle, not
/// just system default) — both themes are equally deliberate here, not one
/// "real" theme plus an afterthought dark variant.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: isDark ? AppColors.slate900 : Colors.white,
      error: AppColors.danger,
    );

    final scaffoldBackground = isDark ? AppColors.slate950 : AppColors.slate50;
    final onSurface = isDark ? Colors.white : AppColors.slate900;
    final borderColor = isDark ? AppColors.slate700 : AppColors.slate200;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.iOS: _FadeThroughPageTransitionsBuilder(),
        },
      ),
      fontFamily: AppTextStyles.body.fontFamily,
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display.copyWith(color: onSurface),
        headlineMedium: AppTextStyles.headline.copyWith(color: onSurface),
        titleMedium: AppTextStyles.title.copyWith(color: onSurface),
        bodyLarge: AppTextStyles.body.copyWith(color: onSurface),
        bodyMedium: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate300 : AppColors.slate500),
        labelLarge: AppTextStyles.button,
        labelSmall: AppTextStyles.micro.copyWith(color: isDark ? AppColors.slate300 : AppColors.slate500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.title.copyWith(color: onSurface),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTextStyles.button,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTextStyles.button,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.bodyStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.slate800 : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        labelStyle: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate400 : AppColors.slate500),
        hintStyle: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate400 : AppColors.slate400),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.slate800 : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.slate700 : AppColors.slate900,
        contentTextStyle: AppTextStyles.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
