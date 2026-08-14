// Shared helpers for the patrol_test/ suite — kept in one place so the
// real-OTP-backdoor plumbing (see backend/app/api/v1/auth.py, only present
// when TEST_MODE_OTP_BACKDOOR=true) has a single source of truth instead of
// drifting across test files.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:medaculous/core/config/env.dart';
import 'package:patrol/patrol.dart';

final api = Dio(BaseOptions(baseUrl: Env.apiBaseUrl, connectTimeout: const Duration(seconds: 15)));

/// Unique, +aliased real inbox address so every test run (and every account
/// created within a run) lands in talk2saadalam@gmail.com without colliding
/// with a prior run's account. [tag] disambiguates multiple accounts created
/// within the same test file/run.
String uniqueEmail([String tag = '']) =>
    'talk2saadalam+patrolE2E$tag${DateTime.now().millisecondsSinceEpoch}@gmail.com';

/// Reads the real OTP the backend just generated, via the test-only backdoor.
/// Small retry loop: the backdoor store is populated synchronously before the
/// register/forgot-password call even returns, so this should succeed on the
/// first try — the retry is just insurance against flakiness, not a real race.
Future<String> fetchOtp(String email, {String purpose = 'email_verification'}) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      final response = await api.get<Map<String, dynamic>>(
        '/auth/_test/last-otp',
        queryParameters: {'email': email, 'purpose': purpose},
      );
      return response.data!['code'] as String;
    } on DioException {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw StateError('No test OTP found for $email/$purpose — is TEST_MODE_OTP_BACKDOOR=true on the backend?');
}

Future<void> enterOtp(PatrolIntegrationTester $, String code) async {
  for (var i = 0; i < code.length; i++) {
    await $(Key('otp_digit_$i')).enterText(code[i]);
  }
  await $.pumpAndSettle();
}

/// Dismisses onboarding if a fresh install/app-data-clear landed there
/// instead of directly on the login screen.
Future<void> skipOnboardingIfShown(PatrolIntegrationTester $) async {
  if ($('Skip').exists) {
    await $('Skip').tap();
  }
}
