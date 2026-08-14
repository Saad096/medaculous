import 'package:flutter/widgets.dart';

/// Stable widget keys shared between app code and the Patrol E2E suite
/// (patrol_test/). Text-based finders are preferred where a label is unique
/// and unlikely to change (button labels); these keys exist for the inputs,
/// where matching on placeholder text is brittle to copy changes.
class TestKeys {
  TestKeys._();

  static const loginEmailField = Key('login_email_field');
  static const loginPasswordField = Key('login_password_field');

  static const registerNameField = Key('register_name_field');
  static const registerEmailField = Key('register_email_field');
  static const registerPasswordField = Key('register_password_field');
  static const registerConfirmPasswordField = Key('register_confirm_password_field');

  static const forgotPasswordEmailField = Key('forgot_password_email_field');

  static const resetPasswordField = Key('reset_password_field');
  static const resetConfirmPasswordField = Key('reset_confirm_password_field');

  /// Global Medaculous AI floating button (shown on all 5 top-level tabs).
  static const aiFab = Key('ai_fab');
}
