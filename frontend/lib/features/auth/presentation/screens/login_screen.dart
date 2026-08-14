import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/testing/test_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/oauth_service.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_header.dart';
import '../widgets/oauth_sign_in_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  OAuthProvider? _oauthLoading;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: _passwordController.text);
      ref.read(authControllerProvider.notifier).setAuthenticated(user);
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      if (e.code == 'email_not_verified') {
        // Correct password, just never finished OTP verification — send a
        // fresh code and route straight there instead of dead-ending on a
        // generic error the user can't act on. A cooldown-rejected resend
        // just means a still-valid code already exists, so route through anyway.
        try {
          await ref.read(authRepositoryProvider).resendOtp(email: email);
        } on ApiException {
          // ignore — an unexpired code from an earlier request still works.
        }
        if (mounted) context.push('/verify-email', extra: email);
        return;
      }
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithGoogle() => _handleOAuth(OAuthProvider.google);

  Future<void> _signInWithApple() => _handleOAuth(OAuthProvider.apple);

  Future<void> _handleOAuth(OAuthProvider provider) async {
    setState(() {
      _oauthLoading = provider;
      _errorMessage = null;
    });
    try {
      final user = provider == OAuthProvider.google
          ? await ref.read(authRepositoryProvider).signInWithGoogle()
          : await ref.read(authRepositoryProvider).signInWithApple();
      ref.read(authControllerProvider.notifier).setAuthenticated(user);
      if (mounted) context.go('/home');
    } on OAuthCancelledException {
      // User backed out of the native sheet — not an error.
    } on OAuthNotConfiguredException {
      _showComingSoon(provider);
    } on ApiException catch (e) {
      if (e.statusCode == 501) {
        _showComingSoon(provider);
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _oauthLoading = null);
    }
  }

  void _showComingSoon(OAuthProvider provider) {
    if (!mounted) return;
    final label = provider == OAuthProvider.google ? 'Google' : 'Apple';
    showAppToast(
      context,
      '$label sign-in is coming soon. Email sign-in works today.',
      kind: AppToastKind.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                const AuthHeader(),
                const SizedBox(height: AppSpacing.xl),
                Text('Welcome back', style: AppTextStyles.display),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sign in to continue your clinical work',
                  style: AppTextStyles.body.copyWith(color: context.secondaryText),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppTextField(
                  fieldKey: TestKeys.loginEmailField,
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return 'Enter your email';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  fieldKey: TestKeys.loginPasswordField,
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Enter your password'
                      : null,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => context.push('/forgot-password'),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Sign in',
                  onPressed: _submit,
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        'or',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.slate400,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                OAuthSignInButton(
                  provider: OAuthProvider.google,
                  onPressed: _signInWithGoogle,
                  isLoading: _oauthLoading == OAuthProvider.google,
                ),
                const SizedBox(height: AppSpacing.md),
                OAuthSignInButton(
                  provider: OAuthProvider.apple,
                  onPressed: _signInWithApple,
                  isLoading: _oauthLoading == OAuthProvider.apple,
                ),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account? ", style: AppTextStyles.body),
                    GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () => context.push('/register'),
                      child: Text(
                        'Sign up',
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
