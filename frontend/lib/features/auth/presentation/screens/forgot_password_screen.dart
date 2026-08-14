import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/testing/test_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../core/widgets/primary_button.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_header.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
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
      // Backend always returns success here regardless of whether the account
      // exists, to avoid leaking account existence — the UI treats it the same way.
      await ref.read(authRepositoryProvider).forgotPassword(email: email);
      if (mounted) context.push('/reset-password', extra: email);
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
                const AuthHeader(compact: true),
                const SizedBox(height: AppSpacing.xl),
                Text('Reset your password', style: AppTextStyles.display),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Enter your email and we'll send you a code to reset your password",
                  style: AppTextStyles.body.copyWith(color: context.secondaryText),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_errorMessage != null) ...[
                  ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppTextField(
                  fieldKey: TestKeys.forgotPasswordEmailField,
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return 'Enter your email';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xxl),
                PrimaryButton(
                  label: 'Send reset code',
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
