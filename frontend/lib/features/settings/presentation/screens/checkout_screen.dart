import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'paywall_screen.dart';

/// Full checkout UI (card details, order summary) so the upgrade path looks
/// and feels like a real purchase flow — owner feedback, 2026-08-14: "it must
/// be put like card numbers etc" rather than a bare "coming soon" toast. Only
/// the final Pay action shows the coming-soon message, since no payment
/// processor is configured yet (see backend STRIPE_SECRET_KEY placeholder) —
/// card details entered here are validated client-side only and are never
/// sent anywhere.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.plan});

  final PricingPlan plan;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cardController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvcController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cardController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    // Deliberate UX pause so this doesn't feel like a no-op tap — no network
    // call happens here; nothing entered above is ever transmitted.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.rocket_launch_rounded, color: AppColors.primary, size: 32),
        title: const Text('Secure checkout is almost ready'),
        content: const Text(
          "We're putting the finishing touches on payment processing so you can subscribe safely. "
          "This will be live very soon. Thanks for your patience. Your trial and current access "
          'continue to work exactly as they do today.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _OrderSummaryCard(plan: plan),
            const SizedBox(height: AppSpacing.xl),
            Text('Card details', style: AppTextStyles.bodyStrong),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name on card', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _cardController,
              keyboardType: TextInputType.number,
              maxLength: 19,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, _CardNumberFormatter()],
              decoration: const InputDecoration(
                labelText: 'Card number',
                hintText: '1234 5678 9012 3456',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.credit_card_rounded),
                counterText: '',
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(' ', '');
                if (digits.length < 15) return 'Enter a valid card number';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _expiryController,
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ExpiryFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'MM/YY',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (v) {
                      if (v == null || !RegExp(r'^\d{2}/\d{2}$').hasMatch(v)) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _cvcController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'CVC',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (v) => (v == null || v.length < 3) ? 'Invalid' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _pay,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_rounded, size: 18),
                label: Text(_isSubmitting ? 'Processing...' : 'Pay ${plan.priceLabel}'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: context.secondaryText),
                const SizedBox(width: 4),
                Text(
                  'Payments are never processed without your confirmation.',
                  style: AppTextStyles.micro.copyWith(color: context.secondaryText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.plan});

  final PricingPlan plan;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        border: Border.all(color: isDark ? AppColors.slate700 : AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Medaculous Pro · ${plan.title}', style: AppTextStyles.bodyStrong),
              const Spacer(),
              Text(plan.priceLabel, style: AppTextStyles.bodyStrong),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan.billingNote, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
        ],
      ),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return TextEditingValue(text: buffer.toString(), selection: TextSelection.collapsed(offset: buffer.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    if (digits.length <= 2) return TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
    final formatted = '${digits.substring(0, 2)}/${digits.substring(2, digits.length > 4 ? 4 : digits.length)}';
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}
