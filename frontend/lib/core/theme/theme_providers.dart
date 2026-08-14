import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_prefs.dart';

final localPrefsProvider = Provider<LocalPrefs>((ref) => LocalPrefs());

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(ThemeMode.system) {
    _bootstrap();
  }

  final LocalPrefs _prefs;

  Future<void> _bootstrap() async {
    final darkEnabled = await _prefs.getDarkModeEnabled();
    if (darkEnabled == null) return;
    state = darkEnabled ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDark(bool enabled) async {
    await _prefs.setDarkModeEnabled(enabled);
    state = enabled ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.read(localPrefsProvider)),
);
