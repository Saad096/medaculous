import 'package:flutter/material.dart';

/// Tokens sampled directly (via pixel-color extraction, not eyeballed) from
/// the client-supplied reference screenshots in `screenshots/` — these
/// supersede the earlier DISCOVERY_REPORT.md §3 best-effort-inferred values
/// now that real reference UI exists. See docs/OPEN_QUESTIONS.md (Branding).
class AppColors {
  AppColors._();

  // Brand / primary
  static const Color primary = Color(0xFF2B7FFF); // primary CTA / active-nav blue
  static const Color primaryDark = Color(0xFF155DFC); // deeper accent blue (Systems icon, Appearance icon)
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color brandNavy = Color(0xFF0D0E1A); // logo background
  static const Color brandPurple = Color(0xFF6D28D9);
  static const Color brandMagenta = Color(0xFFA21CAF);

  // Header logo box (Home screen top bar)
  static const Color headerLogoBg = Color(0xFF2E244B);
  static const Color headerLogoGlyph = Color(0xFF7E69AC);

  // AI-feature accent family (chat "thinking" orb, sparkle-glow keyframe)
  static const Color aiPurple = Color(0xFFA855F7);
  static const Color aiIndigo = Color(0xFF6366F1);
  static const Color aiPink = Color(0xFFEC4899);

  // Semantic
  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color danger = Color(0xFFEF4444); // red-500
  static const Color warning = Color(0xFFF59E0B); // amber-500

  // Slate neutral scale
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate950 = Color(0xFF020617);

  // Surfaces
  static const Color pageBackground = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color searchBarBackground = Color(0xFFF3F4F6);
  static const Color titleText = Color(0xFF06051D);
  static const Color cardTitleText = Color(0xFF1D293D);

  // Bottom nav
  static const Color navActiveBg = Color(0xFFE9F2FF);
  static const Color navInactiveIcon = Color(0xFF6C717D);
  static const Color navLabel = Color(0xFF0F172B);

  /// Per-feature pastel background + saturated icon color pairs, sampled
  /// from each Home-screen feature card in the reference screenshots.
  static const Color systemsCardBg = Color(0xFFE8F2FF);
  static const Color systemsIcon = Color(0xFF155DFC);
  static const Color symptomsCardBg = Color(0xFFE8F8EE);
  static const Color symptomsIcon = Color(0xFF009966);
  static const Color drugRecsCardBg = Color(0xFFFEF9C3);
  static const Color drugRecsIcon = Color(0xFFE17100);
  static const Color formularyCardBg = Color(0xFFFFF0E6);
  static const Color formularyIcon = Color(0xFFF54900);
  static const Color notesCardBg = Color(0xFFF2E8FF);
  static const Color notesIcon = Color(0xFF9810FA);
  static const Color aiCardBg = Color(0xFFE8F0F8);
  static const Color aiIcon = Color(0xFF28B681);
  static const Color calculatorCardBg = Color(0xFFFFF0F0);
  static const Color calculatorIcon = Color(0xFFEC003F);
  static const Color knowledgeHubCardBg = Color(0xFFEEF2FF);
  static const Color knowledgeHubIcon = Color(0xFF4F39F6);
  static const Color wardCardBg = Color(0xFFECFEFF);
  static const Color wardIcon = Color(0xFF0092B8);
  static const Color examPlannerCardBg = Color(0xFFEEF2FF);
  static const Color examPlannerIcon = Color(0xFF4F39F6);
  static const Color osceCardBg = Color(0xFFE8F8EE);
  static const Color osceIcon = Color(0xFF009966);
}

/// Theme-aware text colors. Secondary text hardcoded to [AppColors.slate500]
/// reads muddy on dark surfaces (contrast ~3:1 on slate800 cards); this
/// resolves to a brighter slate in dark mode so body copy stays rich and
/// readable in both themes.
extension AppTextColors on BuildContext {
  Color get secondaryText => Theme.of(this).brightness == Brightness.dark
      ? AppColors.slate300
      : AppColors.slate500;
}
