import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/local_prefs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';

// Owner-supplied design, 2026-09-14: 11 fully designed slides (one per core
// feature), each a complete self-contained image — headline, body copy, and
// illustration already composed — not a template this code fills in.
const _slideCount = 11;
String _slideAsset(int index) => 'assets/images/onboarding/${index + 1}.jpeg';

/// Master spec §3.2: "Onboarding carousel (2-3 slides, skippable)" — since
/// expanded to 11 slides (one per feature) per the owner-supplied designs.
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
    final isLast = _page == _slideCount - 1;

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
                itemCount: _slideCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  // Each slide image already has its own flat background
                  // baked in behind an inner rounded card, so displayed
                  // edge-to-edge it reads as a pasted photo rather than a
                  // native UI element. Wrapping it in its own rounded clip
                  // + shadow instead gives it a proper floating-card feel
                  // consistent with the rest of the app (owner feedback,
                  // 2026-09-14: "rounder feel more good UI/UX").
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(_slideAsset(index), fit: BoxFit.contain),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slideCount,
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
