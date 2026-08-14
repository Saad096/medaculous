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
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../providers/auth_providers.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String _code = '';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.length != 6) {
      setState(
        () => _errorMessage = 'Enter the 6-digit code sent to your email.',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(
            email: widget.email,
            code: _code,
            newPassword: _passwordController.text,
          );
      if (mounted) {
        showAppToast(
          context,
          'Password reset. Please sign in with your new password.',
        );
        context.go('/login');
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enter your new password', style: AppTextStyles.display),
                const SizedBox(height: AppSpacing.sm),
                RichText(
                  text: TextSpan(
                    style: AppTextStyles.body.copyWith(
                      color: context.secondaryText,
                    ),
                    children: [
                      const TextSpan(text: 'Enter the code sent to '),
                      TextSpan(
                        text: widget.email,
                        style: AppTextStyles.bodyStrong,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_errorMessage != null) ...[
                  ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                OtpCodeField(
                  length: 6,
                  enabled: !_isSubmitting,
                  onCompleted: (code) => setState(() => _code = code),
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppTextField(
                  fieldKey: TestKeys.resetPasswordField,
                  label: 'New password',
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) {
                    if (value == null || value.length < 8)
                      return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  fieldKey: TestKeys.resetConfirmPasswordField,
                  label: 'Confirm new password',
                  controller: _confirmController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if (value != _passwordController.text)
                      return 'Passwords do not match';
                    return null;
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xxl),
                PrimaryButton(
                  label: 'Reset password',
                  onPressed: _submit,
                  isLoading: _isSubmitting,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
