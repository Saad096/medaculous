import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Landing screen with all 11 DISCOVERY_REPORT.md feature areas, rebuilt to
/// match the client scope doc's "Home Screen and Settings" section: header +
/// Settings button top-right, global search field, feature card grid, and a
/// persistent bottom nav (see AppBottomNav).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _FeatureCardData {
  const _FeatureCardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.bg,
    required this.iconColor,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color bg;
  final Color iconColor;
  final String route;
}

// All 11 features, in the exact order the client specified (2026-08-15
// feedback PDF) — Systems/Symptoms/Formulary/Notes/Medaculous AI are also
// reachable via the bottom nav + AI FAB, but the client explicitly wants
// both entry points, not one or the other. Subtext is deliberately brief
// (client reference: "browse by body system", "search by symptoms") so it
// never gets cut off, and titles wrap to 2 lines instead of being clipped
// (the "Drug Recommendations" cutoff the client reported).
const _features = [
  _FeatureCardData(
    icon: Icons.grid_view_rounded,
    title: 'Systems',
    description: 'Browse by body system',
    bg: AppColors.systemsCardBg,
    iconColor: AppColors.systemsIcon,
    route: '/systems',
  ),
  _FeatureCardData(
    icon: Icons.medical_services_rounded,
    title: 'Symptoms',
    description: 'Search by symptoms',
    bg: AppColors.symptomsCardBg,
    iconColor: AppColors.symptomsIcon,
    route: '/symptom-checker',
  ),
  _FeatureCardData(
    icon: Icons.medication_rounded,
    title: 'Symptom-Based Drug Recommendations',
    description: 'AI Clinical Pharmacist',
    bg: AppColors.drugRecsCardBg,
    iconColor: AppColors.drugRecsIcon,
    route: '/drug-recommendations',
  ),
  _FeatureCardData(
    icon: Icons.local_pharmacy_rounded,
    title: 'Formulary',
    description: 'Drug information',
    bg: AppColors.formularyCardBg,
    iconColor: AppColors.formularyIcon,
    route: '/formulary',
  ),
  _FeatureCardData(
    icon: Icons.note_alt_rounded,
    title: 'Notes',
    description: 'Your saved items',
    bg: AppColors.notesCardBg,
    iconColor: AppColors.notesIcon,
    route: '/notes',
  ),
  _FeatureCardData(
    icon: Icons.auto_awesome_rounded,
    title: 'Medaculous AI',
    description: 'Ask AI',
    bg: AppColors.aiCardBg,
    iconColor: AppColors.aiIcon,
    route: '/ai-chat',
  ),
  _FeatureCardData(
    icon: Icons.calculate_rounded,
    title: 'Calculator',
    description: 'Clinical tools',
    bg: AppColors.calculatorCardBg,
    iconColor: AppColors.calculatorIcon,
    route: '/calculator',
  ),
  _FeatureCardData(
    icon: Icons.menu_book_rounded,
    title: 'Knowledge Hub',
    description: 'PDF library & search',
    bg: AppColors.knowledgeHubCardBg,
    iconColor: AppColors.knowledgeHubIcon,
    route: '/knowledge-hub',
  ),
  _FeatureCardData(
    icon: Icons.local_hospital_rounded,
    title: 'Ward Companion',
    description: 'Shift rounds & handovers',
    bg: AppColors.wardCardBg,
    iconColor: AppColors.wardIcon,
    route: '/ward-companion',
  ),
  _FeatureCardData(
    icon: Icons.school_rounded,
    title: 'Exam Planner',
    description: 'Postgraduate study schedule',
    bg: AppColors.examPlannerCardBg,
    iconColor: AppColors.examPlannerIcon,
    route: '/exam-planner',
  ),
  _FeatureCardData(
    icon: Icons.checklist_rtl_rounded,
    title: 'OSCE Preparation',
    description: 'Clinical exam stations & timer',
    bg: AppColors.osceCardBg,
    iconColor: AppColors.osceIcon,
    route: '/osce',
  ),
];

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime? _lastBackPress;

  Future<void> _handleBack() async {
    final now = DateTime.now();
    final isDoubleTap =
        _lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2);
    if (isDoubleTap) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    showAppToast(
      context,
      'Press back again to exit',
      kind: AppToastKind.info,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: NavShell(
        current: AppNavTab.home,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.md),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 44,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MEDACULOUS',
                            style: AppTextStyles.title.copyWith(
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            user?.displayName != null
                                ? 'Welcome, ${user!.displayName}'
                                : (user?.email ?? ''),
                            style: AppTextStyles.caption.copyWith(
                              color: context.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (user != null)
                      InkWell(
                        onTap: () => context.push('/settings'),
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: UserAvatar(user: user, radius: 20),
                        ),
                      ),
                  ],
                ),
              ),
              if (user != null && !user.isTrialActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: _TrialBanner(user: user),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: _SearchBar(onTap: () => context.push('/search')),
              ),
              Expanded(
                // A fixed aspect ratio (rather than one computed from
                // available height) means a short viewport — landscape, a
                // small phone, or larger system font size — makes the grid
                // scroll internally instead of forcing cards shorter than
                // their content can fit into (that computed-height version
                // overflowed by ~110px in landscape — owner report,
                // 2026-08-14). GridView scrolls on its own by default, so
                // this can never overflow regardless of viewport size.
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    // Taller than before (owner feedback, 2026-08-17: never
                    // truncate a title — "Symptom-Based Drug Recommendations"
                    // needs up to 3 lines to show in full).
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _features.length,
                  itemBuilder: (context, index) => _FeatureCard(
                    data: _features[index],
                    isDark: isDark,
                    onTap: () => context.push(_features[index].route),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate800 : AppColors.searchBarBackground,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Search conditions, medications',
              style: AppTextStyles.body.copyWith(
                color: isDark ? AppColors.slate400 : AppColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.data,
    required this.isDark,
    required this.onTap,
  });

  final _FeatureCardData data;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        // Whole card tinted with the feature's own color (owner feedback,
        // 2026-08-17: "boxes should be filled with background colored
        // different colors") rather than a plain white/slate card with only
        // a small colored icon chip.
        decoration: BoxDecoration(
          color: data.bg,
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        // Centered layout (owner feedback, 2026-08-17: left-aligned icon and
        // text looked wrong — "must be in center"). Text has no maxLines/
        // ellipsis so a long title like "Symptom-Based Drug Recommendations"
        // always shows in full, wrapping onto as many lines as it needs —
        // the grid's taller aspect ratio (see childAspectRatio above) gives
        // it the room to do that without overflowing the cell.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(data.icon, color: data.iconColor, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyStrong.copyWith(color: AppColors.cardTitleText),
            ),
            const SizedBox(height: 4),
            Text(
              data.description,
              textAlign: TextAlign.center,
              style: AppTextStyles.micro.copyWith(color: AppColors.cardTitleText.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trial-status indicator — informational only, doesn't block access (no
/// pricing/payment provider decided yet, see OPEN_QUESTIONS.md). Only shown
/// once the trial has actually expired; active-trial status lives in Settings.
class _TrialBanner extends StatelessWidget {
  const _TrialBanner({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_bottom_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Trial expired — paid plans coming soon',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
