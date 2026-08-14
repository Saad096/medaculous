// End-to-end auth journey, driven on the real connected device via Patrol.
//
// Run against a backend started with TEST_MODE_OTP_BACKDOOR=true (see
// backend/README.md "E2E testing" section) — that flag exposes
// GET /auth/_test/last-otp so this suite can read a real OTP without IMAP
// access to a real inbox, while OTP_DEV_MODE stays false so the codes are
// ALSO genuinely emailed (talk2saadalam@gmail.com, +aliased per run so
// repeated runs never collide with an existing account).
//
// Finders deliberately mix three styles depending on what's actually stable:
// Keys for text inputs (label text isn't a safe target), Icons for icon-only
// controls (logout button, password visibility toggle), and visible text for
// buttons with a real, unique label.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medaculous/core/testing/test_keys.dart';
import 'package:medaculous/main.dart';
import 'package:patrol/patrol.dart';

import 'support/test_helpers.dart';

void main() {
  patrolTest('full auth journey: onboarding, register, verify, home, logout, '
      'login, wrong-password, forgot-reset password, lockout', ($) async {
    await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));

    // --- Splash resolves to either onboarding (fresh install) or login ---
    try {
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
    } catch (_) {
      // Fresh install landed on onboarding instead — handled below.
    }
    if ($('Skip').exists) {
      await $('Skip').tap();
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 5));
    }

    // --- Google/Apple "coming soon" — must respond, never do nothing ---
    await $('Continue with Google').tap();
    await $(RegExp('coming soon')).waitUntilVisible(timeout: const Duration(seconds: 3));
    await $.pump(const Duration(seconds: 2)); // let the SnackBar auto-dismiss

    // --- Register a fresh, uniquely-aliased account on the user's real inbox ---
    final email = uniqueEmail();
    const password = 'PatrolTest123';
    const newPassword = 'PatrolTestNew456';

    await $('Sign up').tap();
    await $(TestKeys.registerNameField).waitUntilVisible();
    await $(TestKeys.registerNameField).enterText('Patrol E2E');
    await $(TestKeys.registerEmailField).enterText(email);
    await $(TestKeys.registerPasswordField).enterText(password);
    await $(TestKeys.registerConfirmPasswordField).enterText(password);
    await $('Create account').tap();

    // --- OTP verify screen: email shown, expiry/resend countdowns present ---
    // The email is rendered inside a RichText ("We sent a 6-digit code to
    // {email}"), so no widget's text is ever exactly equal to just the email
    // — a regex (substring) match is required here, unlike the standalone
    // Text widget on the Home screen below. findsWidgets (not findsOneWidget)
    // because the previous route's email TextField is still mounted (just
    // offstage) underneath this pushed screen and also contains the text —
    // the test only needs to confirm the email appears here, not that it's
    // the sole match in the whole tree.
    await $(Key('otp_digit_0')).waitUntilVisible(timeout: const Duration(seconds: 15));
    expect($(RegExp(RegExp.escape(email))), findsWidgets);
    expect($(RegExp(r'Code expires in \d')), findsOneWidget);
    expect($(RegExp(r'Resend code in \d')), findsOneWidget);

    final verifyCode = await fetchOtp(email);
    await enterOtp($, verifyCode);

    // --- Home screen ---
    await $('Welcome, Patrol E2E!').waitUntilVisible(timeout: const Duration(seconds: 10));
    expect($(email), findsOneWidget);
    expect($('DEV'), findsOneWidget); // env indicator, master spec §3.2

    // --- Logout (icon-only button — found by icon, not coordinates) ---
    await $(Icons.logout_rounded).tap();
    await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));

    // --- Wrong password shows a clear, non-silent error ---
    await $(TestKeys.loginEmailField).enterText(email);
    await $(TestKeys.loginPasswordField).enterText('the-wrong-password');
    await $('Sign in').tap();
    await $('Incorrect email or password.').waitUntilVisible(timeout: const Duration(seconds: 10));

    // --- Correct password logs in ---
    await $(TestKeys.loginPasswordField).enterText(password);
    await $('Sign in').tap();
    await $('Welcome, Patrol E2E!').waitUntilVisible(timeout: const Duration(seconds: 10));
    await $(Icons.logout_rounded).tap();
    await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));

    // --- Forgot password -> reset -> login with the NEW password ---
    await $('Forgot password?').tap();
    await $(TestKeys.forgotPasswordEmailField).waitUntilVisible();
    await $(TestKeys.forgotPasswordEmailField).enterText(email);
    await $('Send reset code').tap();

    await $(Key('otp_digit_0')).waitUntilVisible(timeout: const Duration(seconds: 15));
    final resetCode = await fetchOtp(email, purpose: 'password_reset');
    await enterOtp($, resetCode);
    await $(TestKeys.resetPasswordField).waitUntilVisible();
    await $(TestKeys.resetPasswordField).enterText(newPassword);
    await $(TestKeys.resetConfirmPasswordField).enterText(newPassword);
    await $('Reset password').tap();

    // Reset always finishes back on the login screen.
    await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
    await $(TestKeys.loginEmailField).enterText(email);
    await $(TestKeys.loginPasswordField).enterText(newPassword);
    await $('Sign in').tap();
    await $('Welcome, Patrol E2E!').waitUntilVisible(timeout: const Duration(seconds: 10));
    await $(Icons.logout_rounded).tap();
    await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));

    // --- Brute-force lockout: destructive, so this account is spent last ---
    // The lockout window (backend/app/api/v1/auth.py) counts ALL login_failed
    // events in the last 15 minutes, regardless of successful logins in
    // between — it never resets. The standalone wrong-password check earlier
    // in this test already logged 1 failure, so only 4 more are needed here
    // to reach LOGIN_MAX_FAILED_ATTEMPTS (5) by the final step below.
    for (var i = 0; i < 4; i++) {
      await $(TestKeys.loginEmailField).enterText(email);
      await $(TestKeys.loginPasswordField).enterText('still-wrong-$i');
      await $('Sign in').tap();
      await $('Incorrect email or password.').waitUntilVisible(timeout: const Duration(seconds: 10));
    }
    // 6th attempt, even with the CORRECT password, must be rejected by the lockout.
    await $(TestKeys.loginEmailField).enterText(email);
    await $(TestKeys.loginPasswordField).enterText(newPassword);
    await $('Sign in').tap();
    await $('Too many failed login attempts. Please try again later or reset your password.')
        .waitUntilVisible(timeout: const Duration(seconds: 10));
  });

  patrolTest('offline banner appears when connectivity drops', ($) async {
    await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
    try {
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
    } catch (_) {
      // Fresh install landed on onboarding instead — handled below.
    }
    if ($('Skip').exists) {
      await $('Skip').tap();
    }

    // Airplane mode is deliberately avoided here — Patrol toggles it by
    // clicking a "Airplane mode" quick-settings tile via UiAutomator, which
    // doesn't exist under that label on this device's MIUI control center.
    // disableWifi/disableCellular use adb shell commands (svc wifi/data
    // disable) instead, so they work regardless of OEM UI skinning.
    await $.platform.mobile.disableWifi();
    await $.platform.mobile.disableCellular();
    await $("You're offline — some features may not work").waitUntilVisible(timeout: const Duration(seconds: 15));

    // Restore connectivity so subsequent runs (and the device generally) aren't left offline.
    await $.platform.mobile.enableCellular();
    await $.platform.mobile.enableWifi();
  });
}
