// The default counter smoke test doesn't apply once the counter app was
// replaced. Full-app widget tests need flutter_secure_storage's platform
// channel mocked (real device/emulator or a mock method channel) since
// AuthController hits it on startup — tracked for the QA pass rather than
// stubbed here. This is a lightweight, platform-channel-free sanity check
// that the theme builds correctly for both brightnesses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medaculous/core/theme/app_theme.dart';

void main() {
  test('light and dark themes build without throwing', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
