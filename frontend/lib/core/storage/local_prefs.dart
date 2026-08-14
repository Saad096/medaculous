import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive local flags (onboarding seen, dark-mode override). Tokens
/// never go here — see TokenStorage for those.
class LocalPrefs {
  static const _onboardingKey = 'has_seen_onboarding';
  static const _darkModeKey = 'dark_mode_enabled';

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingKey) ?? false;
  }

  Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  /// null = follow system, true = dark, false = light.
  Future<bool?> getDarkModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_darkModeKey) ? prefs.getBool(_darkModeKey) : null;
  }

  Future<void> setDarkModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, enabled);
  }
}
