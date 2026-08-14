/// Spacing scale (4px base, matches the legacy Tailwind usage) and the
/// radius scale, which the legacy app skews heavily toward large/soft
/// corners (DISCOVERY_REPORT.md §3) — never sharp corners on cards/modals.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadii {
  AppRadii._();

  static const double md = 12; // controls, small chips
  static const double lg = 16; // cards/panels (Tailwind rounded-xl/2xl)
  static const double xl = 24; // modals, hero surfaces (rounded-3xl)
  static const double pill = 999;
}
