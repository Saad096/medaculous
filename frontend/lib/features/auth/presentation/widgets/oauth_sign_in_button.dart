import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

enum OAuthProvider { google, apple }

/// Google/Apple sign-in buttons. The backend endpoints (`/auth/google`,
/// `/auth/apple`) are fully implemented and verify real tokens server-side —
/// see docs/SECURITY_CHECKLIST.md. Until real OAuth client IDs land in .env
/// (see docs/OPEN_QUESTIONS.md), tapping these will fail with a clear error
/// from the native SDK or backend (501 "not configured") rather than silently
/// doing nothing, so the failure mode is honest either way.
class OAuthSignInButton extends StatelessWidget {
  const OAuthSignInButton({
    super.key,
    required this.provider,
    required this.onPressed,
    this.isLoading = false,
  });

  final OAuthProvider provider;
  final VoidCallback onPressed;
  final bool isLoading;

  String get _label => switch (provider) {
    OAuthProvider.google => 'Continue with Google',
    OAuthProvider.apple => 'Continue with Apple',
  };

  // Real brand mark for Google (owner-supplied asset) instead of a generic
  // glyph — owner feedback, 2026-08-14.
  Widget get _icon => switch (provider) {
    OAuthProvider.google => Image.asset(
      'assets/images/google.png',
      width: 18,
      height: 18,
    ),
    OAuthProvider.apple => const Icon(Icons.apple, size: 22),
  };

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.slate700
        : AppColors.slate200;

    return PressableScale(
      enabled: !isLoading,
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _icon,
                    const SizedBox(width: AppSpacing.sm),
                    Text(_label, style: AppTextStyles.bodyStrong),
                  ],
                ),
        ),
      ),
    );
  }
}
