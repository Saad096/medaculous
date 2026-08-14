import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/local_prefs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/primary_button.dart';

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    icon: Icons.menu_book_rounded,
    title: 'A structured medical reference',
    body:
        'Evidence-based coverage of diseases, drugs, and clinical calculators — organized for fast lookup on the ward or during revision.',
  ),
  _Slide(
    icon: Icons.auto_awesome_rounded,
    title: 'AI that understands context',
    body:
        'Ask Medaculous AI in Ward, ER, or Exam mode and get answers tuned to what you actually need right now.',
  ),
  _Slide(
    icon: Icons.sync_rounded,
    title: 'Your notes, everywhere',
    body:
        'Sign in once and your notes, exam plans, and saved references sync across every device.',
  ),
];

/// Master spec §3.2: "Onboarding carousel (2-3 slides, skippable)".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  Future<void> _finish() async {
    await LocalPrefs().setOnboardingSeen();
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide.icon,
                            size: 56,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.headline,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : AppColors.slate200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: PrimaryButton(
                label: isLast ? 'Get started' : 'Next',
                onPressed: isLast
                    ? _finish
                    : () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
