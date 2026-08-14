import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../testing/test_keys.dart';

/// Global entry point to Medaculous AI: a circular gradient floating action
/// button shown bottom-right on every top-level tab screen (via [NavShell]).
/// The AI feature is not a bottom-nav tab (owner decision: the bar has
/// exactly 5 positions) but must stay reachable from anywhere.
///
/// Owner feedback (2026-08-13): the earlier app-bar corner icon felt
/// awkward/misplaced. Bottom-right FAB is the standard reach-friendly spot,
/// and the earlier concern about a FAB covering scrolled content is solved
/// by NavShell hiding the FAB (together with the nav bar) while the user
/// scrolls/reads, restoring it on scroll-up or tap.
class AiFab extends StatelessWidget {
  const AiFab({super.key, this.mini = false});

  /// Smaller variant used when stacked above a screen-specific FAB
  /// (e.g. the Notes screen's "add note" button).
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final size = mini ? 46.0 : 58.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.aiPurple, AppColors.aiIndigo],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.aiIndigo.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        key: TestKeys.aiFab,
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push('/ai-chat'),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: mini ? 22 : 26,
            ),
          ),
        ),
      ),
    );
  }
}
