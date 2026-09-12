import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Replaces a screen's submit button while a one-shot (non-streaming) AI call
/// is in flight — originally built for Drug Recommendations (owner feedback,
/// 2026-09-11: a broad query can take over a minute, and a plain spinner
/// gave no sense of progress), now shared with Symptom Checker for the same
/// user experience. There's no real server-reported progress to show (a
/// single blocking call, not a stream), so this fills against a time
/// estimate instead, hard-capped below 100% until the real response
/// actually arrives — see the call site's "capped progress" getter, which
/// must stay hard-capped below 1.0 unless the real response is already in
/// hand, or the bar can reach 100% purely from time passing while the
/// backend is still working.
class AiAnalyzingProgressBar extends StatelessWidget {
  const AiAnalyzingProgressBar({super.key, required this.animation, required this.progressValue, required this.label});

  /// Ticks the rebuild — the actual displayed fraction always comes from
  /// [progressValue], since it depends on more than just the animation's
  /// raw value (the caller's own hard-cap logic).
  final Listenable animation;
  final double Function() progressValue;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // A dark indigo base (not the light/dark surface color) so the
          // white label stays readable throughout — the gradient fill is
          // the same hue family, just brighter, rather than contrasting
          // against a light, hard-to-read track early in the animation.
          const ColoredBox(color: Color(0xFF1E1B4B)),
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) => FractionallySizedBox(
              widthFactor: progressValue().clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.aiIndigo, AppColors.primary]),
                ),
              ),
            ),
          ),
          Align(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
