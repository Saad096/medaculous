import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Persistent bottom navigation shown on the app's 5 major entry screens
/// (Home, Diseases/Systems, Symptoms, Formulary, Notes) per the client
/// scope doc ("A persistent bottom navigation is used across major parts of
/// the app"). Medaculous AI is deliberately NOT a tab (owner decision,
/// 2026-08-13: the bar has 5 positions) — it's reachable from anywhere via
/// the global [AiFab] instead. Secondary/detail screens use a plain back
/// arrow; this widget is only meant to be set as a Scaffold's
/// `bottomNavigationBar` on those 5 top-level screens.
enum AppNavTab { home, systems, symptoms, formulary, notes }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});

  final AppNavTab current;

  static const _items = [
    (
      tab: AppNavTab.home,
      icon: Icons.home_rounded,
      label: 'Home',
      route: '/home',
    ),
    (
      tab: AppNavTab.systems,
      icon: Icons.biotech_rounded,
      label: 'Diseases',
      route: '/systems',
    ),
    (
      tab: AppNavTab.symptoms,
      icon: Icons.medical_services_rounded,
      label: 'Symptoms',
      route: '/symptom-checker',
    ),
    (
      tab: AppNavTab.formulary,
      icon: Icons.local_pharmacy_rounded,
      label: 'Formulary',
      route: '/formulary',
    ),
    (
      tab: AppNavTab.notes,
      icon: Icons.note_alt_rounded,
      label: 'Notes',
      route: '/notes',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.slate700 : AppColors.slate200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final item in _items)
                _NavButton(
                  icon: item.icon,
                  label: item.label,
                  active: item.tab == current,
                  onTap: item.tab == current
                      ? null
                      : () => context.go(item.route),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = active
        ? AppColors.primary
        : (isDark ? AppColors.slate400 : AppColors.navInactiveIcon);
    final labelColor = active
        ? AppColors.primary
        : (isDark ? AppColors.slate400 : AppColors.navLabel);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Active tab gets a soft pill highlight; inactive icons stay
              // plain (no boxes) per modern bottom-nav convention.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 32,
                decoration: BoxDecoration(
                  color: active
                      ? (isDark
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.navActiveBg)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTextStyles.micro.copyWith(
                  color: labelColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
