import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Branded animated reveal shown while AuthController resolves whether a
/// session already exists — the router redirects away as soon as that
/// finishes, so this screen has no logic of its own.
///
/// Redesigned 2026-08-13 (owner feedback: previous version felt flat):
/// brand-gradient backdrop, soft radial glow behind the logo, staggered
/// logo/wordmark reveal and a subtle breathing pulse on the glow so the
/// screen feels alive rather than frozen while auth resolves.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Shortened from 1100ms (owner feedback, 2026-08-15: splash held the
  // screen too long) — still long enough to read as an intentional reveal,
  // short enough that a fast session check doesn't feel like a stall.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  // Gentle infinite pulse on the glow, separate from the one-shot reveal.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _reveal,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.8, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _reveal,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
        ),
      );
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _reveal,
    curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
  );
  late final Animation<Offset> _textSlide =
      Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _reveal,
          curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
        ),
      );

  @override
  void dispose() {
    _reveal.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF11122B), AppColors.brandNavy, Color(0xFF160E2E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) {
                              final glow = 0.25 + 0.2 * _pulse.value;
                              return Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.brandPurple.withValues(
                                        alpha: glow,
                                      ),
                                      blurRadius: 70,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: child,
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 120,
                                height: 120,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: _textFade,
                        child: SlideTransition(
                          position: _textSlide,
                          child: Column(
                            children: [
                              Text(
                                'medaculous',
                                style: AppTextStyles.display.copyWith(
                                  color: Colors.white,
                                  fontSize: 32,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'AI POWERED MEDICAL REFERENCE',
                                style: AppTextStyles.micro.copyWith(
                                  color: const Color(0xFFB79DF0),
                                  letterSpacing: 2.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Quiet progress cue anchored at the bottom so the wait never
              // reads as a hang.
              FadeTransition(
                opacity: _textFade,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.brandPurple.withValues(alpha: 0.8),
                    ),
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
