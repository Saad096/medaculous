import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Shared brand header for the auth screens — just the mark and wordmark,
/// centered. The marketing tagline/banner previously here was removed
/// (owner feedback, 2026-08-14) as noise on a functional sign-in screen.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.compact = false});

  /// Compact variant for secondary screens (forgot/reset password) where
  /// the form needs more room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 56.0 : 76.0;
    return Center(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 16 : 20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPurple.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 16 : 20),
              child: Image.asset(
                'assets/images/logo.png',
                width: logoSize,
                height: logoSize,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'medaculous',
            style: AppTextStyles.headline.copyWith(fontSize: compact ? 20 : 24),
          ),
        ],
      ),
    );
  }
}
