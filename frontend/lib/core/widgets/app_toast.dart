import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Card-style confirmation toasts, replacing the default dark SnackBar bar.
/// A floating rounded card with a tinted status icon reads as a deliberate,
/// polished confirmation instead of a black strip of text.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastKind kind = AppToastKind.success,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final (icon, tint) = switch (kind) {
    AppToastKind.success => (Icons.check_circle_rounded, AppColors.success),
    AppToastKind.info => (Icons.info_rounded, AppColors.primary),
    AppToastKind.error => (Icons.error_rounded, AppColors.danger),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.slate800 : Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(
            color: isDark ? AppColors.slate700 : AppColors.slate200,
          ),
        ),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        duration: duration,
        action: action,
        content: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body.copyWith(
                  color: isDark ? Colors.white : AppColors.slate900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

enum AppToastKind { success, info, error }
