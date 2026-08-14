import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../providers/auth_providers.dart';

const _resendCooldownSeconds =
    60; // must match backend OTP_RESEND_COOLDOWN_SECONDS
const _codeTtlSeconds = 10 * 60; // must match backend OTP_TTL_MINUTES

/// Master spec §3.3: shows which email the code was sent to, a resend timer,
/// an expiry countdown, and a "wrong email? go back" affordance.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _otpKey = GlobalKey<OtpCodeFieldState>();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  int _resendSecondsLeft = _resendCooldownSeconds;
  int _expirySecondsLeft = _codeTtlSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicking();
  }

  void _startTicking() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_resendSecondsLeft > 0) _resendSecondsLeft--;
        if (_expirySecondsLeft > 0) _expirySecondsLeft--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatMmSs(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _onCodeCompleted(String code) async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final user = await ref
          .read(authRepositoryProvider)
          .verifyEmail(email: widget.email, code: code);
      ref.read(authControllerProvider.notifier).setAuthenticated(user);
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
      _otpKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authRepositoryProvider).resendOtp(email: widget.email);
      setState(() {
        _resendSecondsLeft = _resendCooldownSeconds;
        _expirySecondsLeft = _codeTtlSeconds;
        _errorMessage = null;
      });
      if (mounted) {
        showAppToast(context, 'New code sent.');
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expirySecondsLeft == 0;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check your email', style: AppTextStyles.display),
              const SizedBox(height: AppSpacing.sm),
              RichText(
                text: TextSpan(
                  style: AppTextStyles.body.copyWith(color: context.secondaryText),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to '),
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
              if (expired)
                ErrorBanner(
                  message: 'This code has expired. Request a new one below.',
                )
              else
                Center(
                  child: Text(
                    'Code expires in ${_formatMmSs(_expirySecondsLeft)}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.slate400,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              OtpCodeField(
                key: _otpKey,
                length: 6,
                enabled: !_isVerifying,
                onCompleted: _onCodeCompleted,
              ),
              if (_isVerifying) ...[
                const SizedBox(height: AppSpacing.lg),
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: _resendSecondsLeft > 0
                    ? Text(
                        'Resend code in ${_resendSecondsLeft}s',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.slate400,
                        ),
                      )
                    : TextButton(
                        onPressed: _isResending ? null : _resend,
                        child: Text(
                          _isResending ? 'Sending...' : 'Resend code',
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Wrong email? Go back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
