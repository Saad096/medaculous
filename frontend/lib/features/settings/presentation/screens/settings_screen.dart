import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/theme_providers.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/copy_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import 'paywall_screen.dart';

Future<void> _showAvatarSheet(BuildContext context, WidgetRef ref) async {
  final hasAvatar = ref.read(authControllerProvider).user?.hasAvatar ?? false;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(sheetContext).pop('camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheetContext).pop('gallery'),
          ),
          if (hasAvatar)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text('Remove photo', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'remove') {
    try {
      await ref.read(avatarProvider.notifier).remove();
      if (context.mounted) showAppToast(context, 'Profile photo removed');
    } on ApiException catch (e) {
      if (context.mounted) {
        showAppToast(context, e.message, kind: AppToastKind.error);
      }
    }
    return;
  }

  final picked = await ImagePicker().pickImage(
    source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 80,
  );
  if (picked == null || !context.mounted) return;
  final bytes = await picked.readAsBytes();
  try {
    await ref.read(avatarProvider.notifier).upload(bytes, picked.name);
    if (context.mounted) showAppToast(context, 'Profile photo updated');
  } on ApiException catch (e) {
    if (context.mounted) {
      showAppToast(context, e.message, kind: AppToastKind.error);
    }
  }
}

/// Support/feedback inbox for this app — same address used throughout
/// development for real end-to-end email verification (see
/// docs/OPEN_QUESTIONS.md), reused here as the single point of contact
/// since no separate support desk exists yet.
const _supportEmail = 'talk2saadalam@gmail.com';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (user != null) ...[
            _SectionCard(
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _showAvatarSheet(context, ref),
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(user: user, radius: 24),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.slate800
                                    : Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName?.isNotEmpty ?? false ? user.displayName! : user.email,
                          style: AppTextStyles.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(user.email, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                        const SizedBox(height: 4),
                        _SignInBadge(method: user.signInMethod),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel('Subscription'),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              child: _SectionCard(
                child: Row(
                  children: [
                    Icon(
                      user.isTrialActive ? Icons.hourglass_top_rounded : Icons.hourglass_bottom_rounded,
                      color: user.isTrialActive ? AppColors.primary : AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.isTrialActive ? 'Free trial active' : 'Trial expired',
                            style: AppTextStyles.bodyStrong,
                          ),
                          Text(
                            user.isTrialActive
                                ? '${user.trialDaysLeft} day${user.trialDaysLeft == 1 ? '' : 's'} left · tap to see plans'
                                : 'Tap to see upgrade plans',
                            style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (user.isAdmin) ...[
              _SectionLabel('Admin'),
              InkWell(
                onTap: () => context.push('/admin'),
                borderRadius: BorderRadius.circular(AppSpacing.lg),
                child: _SectionCard(
                  child: Row(
                    children: [
                      const Icon(Icons.shield_rounded, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Text('Admin Dashboard', style: AppTextStyles.bodyStrong),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
          _SectionLabel('Appearance'),
          _SectionCard(
            child: Row(
              children: [
                Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: AppSpacing.md),
                // Static label naming what the toggle enables, not the current
                // state — "Light Mode" as a label while OFF read as confusing
                // (owner feedback, 2026-08-14): a switch you turn on should be
                // named for what turning it ON does.
                const Expanded(
                  child: Text('Dark Mode', style: AppTextStyles.bodyStrong),
                ),
                Switch(
                  value: isDark,
                  onChanged: (value) => ref.read(themeModeProvider.notifier).setDark(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('Sync'),
          _SectionCard(
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: AppColors.success),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All synced', style: AppTextStyles.bodyStrong),
                      Text(
                        'Notes, Knowledge Hub, Formulary favourites and AI chat history sync automatically to your account.',
                        style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('Feedback & Bug Reports'),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, color: context.secondaryText),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(_supportEmail, style: AppTextStyles.body)),
                    // Flips to a green check inline instead of raising a
                    // snackbar — confirmation stays where the user tapped.
                    const CopyIconButton(
                      text: _supportEmail,
                      tooltip: 'Copy email',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri(
                        scheme: 'mailto',
                        path: _supportEmail,
                        query: 'subject=Medaculous Feedback / Bug Report',
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Report a Bug / Send Feedback'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    ref.read(avatarProvider.notifier).clear();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '© ${DateTime.now().year} Medaculous',
                  style: AppTextStyles.micro.copyWith(color: AppColors.slate400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInBadge extends StatelessWidget {
  const _SignInBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (method) {
      'google' => (Icons.g_mobiledata_rounded, 'Google account'),
      'apple' => (Icons.apple_rounded, 'Apple account'),
      _ => (Icons.email_outlined, 'Email account'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.secondaryText),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4),
      child: Text(
        label,
        style: AppTextStyles.micro.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
