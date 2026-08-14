// UI-level scenarios that complement auth_flow_test.dart: client-side form
// validation, screen-to-screen navigation, and negative/edge cases in the
// auth screens. Most of these never touch the network (Flutter's
// Form.validate() runs before any API call), so they're fast and don't spend
// real accounts or emails — the two exceptions are called out inline.
//
// Finders follow the same convention as auth_flow_test.dart: Keys for text
// inputs, Icons for icon-only controls, exact visible text for uniquely
// labelled buttons/messages, and RegExp only where the target text is
// embedded inside a longer sentence (RichText/TextSpan) rather than being a
// standalone widget.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medaculous/core/testing/test_keys.dart';
import 'package:medaculous/main.dart';
import 'package:patrol/patrol.dart';

import 'support/test_helpers.dart';

void main() {
  patrolTest(
    'register screen validates required fields, email format, password length, '
    'and password match — no account is created',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
      try {
        await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
      } catch (_) {
        // Fresh install landed on onboarding instead — handled below.
      }
      await skipOnboardingIfShown($);

      await $('Sign up').tap();
      await $(TestKeys.registerNameField).waitUntilVisible();

      // Everything empty: email and password are required. Confirm-password's
      // validator only compares equality against the password field, so with
      // both empty it's satisfied and shows no error of its own.
      await $('Create account').tap();
      await $('Enter your email').waitUntilVisible(timeout: const Duration(seconds: 5));
      expect($('At least 8 characters'), findsOneWidget);
      expect($('Passwords do not match'), findsNothing);

      // Invalid email format.
      await $(TestKeys.registerEmailField).enterText('not-an-email');
      await $('Create account').tap();
      await $('Enter a valid email').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Valid email, short password.
      await $(TestKeys.registerEmailField).enterText('someone@example.com');
      await $(TestKeys.registerPasswordField).enterText('short');
      await $('Create account').tap();
      await $('At least 8 characters').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Long-enough password, mismatched confirmation.
      await $(TestKeys.registerPasswordField).enterText('longenough1');
      await $(TestKeys.registerConfirmPasswordField).enterText('different1');
      await $('Create account').tap();
      await $('Passwords do not match').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Still on the register screen — no account was ever submitted.
      expect($('Create your account'), findsOneWidget);
    },
  );

  patrolTest(
    'login screen validates required fields and email format before calling the API',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
      try {
        await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
      } catch (_) {
        // Fresh install landed on onboarding instead — handled below.
      }
      await skipOnboardingIfShown($);
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 5));

      await $('Sign in').tap();
      await $('Enter your email').waitUntilVisible(timeout: const Duration(seconds: 5));
      expect($('Enter your password'), findsOneWidget);

      await $(TestKeys.loginEmailField).enterText('not-an-email');
      await $(TestKeys.loginPasswordField).enterText('whatever1');
      await $('Sign in').tap();
      await $('Enter a valid email').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Still on the login screen — no request was made with the malformed email.
      expect($('Welcome back'), findsOneWidget);
    },
  );

  patrolTest(
    'forgot password requires a valid email; reset password requires a complete '
    'code before validating the new password',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
      try {
        await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
      } catch (_) {
        // Fresh install landed on onboarding instead — handled below.
      }
      await skipOnboardingIfShown($);
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 5));

      await $('Forgot password?').tap();
      await $(TestKeys.forgotPasswordEmailField).waitUntilVisible();

      await $('Send reset code').tap();
      await $('Enter your email').waitUntilVisible(timeout: const Duration(seconds: 5));

      await $(TestKeys.forgotPasswordEmailField).enterText('not-an-email');
      await $('Send reset code').tap();
      await $('Enter a valid email').waitUntilVisible(timeout: const Duration(seconds: 5));

      // The backend never reveals whether an account exists (see
      // backend/app/api/v1/auth.py forgot-password — always 204), so a
      // syntactically valid but nonexistent email is safe here: it reaches
      // the reset-password screen without sending any real email.
      await $(TestKeys.forgotPasswordEmailField).enterText('nonexistent+patrolE2E@example.com');
      await $('Send reset code').tap();
      await $(TestKeys.resetPasswordField).waitUntilVisible(timeout: const Duration(seconds: 10));

      // No code entered yet — this is a local check that runs before
      // Form.validate(), so it fires even with valid-looking password fields.
      await $(TestKeys.resetPasswordField).enterText('longenough1');
      await $(TestKeys.resetConfirmPasswordField).enterText('longenough1');
      await $('Reset password').tap();
      await $('Enter the 6-digit code sent to your email.').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Still on the reset-password screen.
      expect($('Enter your new password'), findsOneWidget);
    },
  );

  patrolTest(
    'navigating from login to register and back lands on the correct screen each time',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
      try {
        await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
      } catch (_) {
        // Fresh install landed on onboarding instead — handled below.
      }
      await skipOnboardingIfShown($);
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 5));
      expect($('Welcome back'), findsOneWidget);

      await $('Sign up').tap();
      await $('Create your account').waitUntilVisible(timeout: const Duration(seconds: 5));

      // Register screen's AppBar has the default back arrow (Icons.arrow_back).
      await $(Icons.arrow_back).tap();
      await $('Welcome back').waitUntilVisible(timeout: const Duration(seconds: 5));

      await $('Forgot password?').tap();
      await $('Reset your password').waitUntilVisible(timeout: const Duration(seconds: 5));
      await $(Icons.arrow_back).tap();
      await $('Welcome back').waitUntilVisible(timeout: const Duration(seconds: 5));
    },
  );

  patrolTest(
    'wrong OTP code is rejected before the correct code succeeds',
    ($) async {
      await $.pumpWidgetAndSettle(const ProviderScope(child: MedaculousApp()));
      try {
        await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 10));
      } catch (_) {
        // Fresh install landed on onboarding instead — handled below.
      }
      await skipOnboardingIfShown($);
      await $(TestKeys.loginEmailField).waitUntilVisible(timeout: const Duration(seconds: 5));

      // This scenario needs a real pending OTP tied to a real account, so —
      // unlike the tests above — it does spend one real account/email.
      final email = uniqueEmail('otp');
      await $('Sign up').tap();
      await $(TestKeys.registerNameField).waitUntilVisible();
      await $(TestKeys.registerNameField).enterText('Patrol OTP Edge');
      await $(TestKeys.registerEmailField).enterText(email);
      await $(TestKeys.registerPasswordField).enterText('PatrolOtp123');
      await $(TestKeys.registerConfirmPasswordField).enterText('PatrolOtp123');
      await $('Create account').tap();
      await $(Key('otp_digit_0')).waitUntilVisible(timeout: const Duration(seconds: 15));

      final realCode = await fetchOtp(email);
      // Guaranteed different from the real code: shift every digit by 1 (mod 10).
      final wrongCode =
          realCode.split('').map((d) => ((int.parse(d) + 1) % 10).toString()).join();
      await enterOtp($, wrongCode);
      await $('Incorrect code.').waitUntilVisible(timeout: const Duration(seconds: 10));

      // The OTP field clears itself on error — re-enter the real code.
      await enterOtp($, realCode);
      await $('Welcome, Patrol OTP Edge!').waitUntilVisible(timeout: const Duration(seconds: 10));

      // NOTE: a system-back-button-from-Home check was deliberately dropped
      // from this test. home_screen.dart has no PopScope/WillPopScope, so
      // pressing back on this root-of-stack screen invokes Android's default
      // behavior: the Activity finishes and the whole app process exits.
      // That kills Patrol's own in-process test server along with it, so
      // there's no app left to assert against afterwards — confirmed via a
      // real run where pressBack() was immediately followed by the app
      // process disappearing from `adb shell ps` and the orchestrator's HTTP
      // link to it dying (EOFException: server prematurely closed the
      // connection). This is a real product/UX question, not a test bug —
      // see OPEN_QUESTIONS.md: should back-from-Home exit immediately, or
      // use a "press back again to exit" confirmation like most Android apps?
    },
  );
}
