import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'checkout_screen.dart';

class PricingPlan {
  const PricingPlan({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.billingNote,
    required this.badge,
  });

  final String id;
  final String title;
  final String priceLabel;
  final String billingNote;
  final String? badge;
}

// Pricing set from a quick competitive scan of comparable clinical
// reference / exam-prep apps (Epocrates Plus ~$175/yr, AMBOSS ~$99-149/yr,
// UpToDate individual tiers $200-500+/yr) — Medaculous bundles AI chat,
// reference content, and exam prep in one app, so it's priced in the middle
// of that range rather than at the premium end. Treat as an adjustable
// starting point, not a final locked-in decision (owner request, 2026-08-14:
// "you must have to do competitive analysis and set pricing for now").
const _plans = [
  PricingPlan(
    id: 'annual',
    title: 'Annual',
    priceLabel: '\$89.99/year',
    billingNote: 'Billed once a year · equivalent to \$7.50/month',
    badge: 'Save 42%',
  ),
  PricingPlan(
    id: 'monthly',
    title: 'Monthly',
    priceLabel: '\$12.99/month',
    billingNote: 'Billed every month · cancel anytime',
    badge: null,
  ),
];

/// Plan-selection screen — CTA continues into CheckoutScreen for a full card
/// form. No payment is ever processed here or in checkout; see
/// CheckoutScreen's doc comment for exactly where and why "coming soon"
/// still applies (owner feedback, 2026-08-14).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  String _selectedPlanId = 'annual';

  static const _features = [
    ('Medaculous AI', 'A higher monthly AI message limit across all chat modes'),
    ('Full Knowledge Hub', 'Unlimited PDF storage, nested folders, and content search'),
    ('Exam Planner', 'Adaptive study schedules for every supported exam'),
    ('All 11 features', 'Systems, Formulary, Notes, Ward Companion, OSCE and more'),
  ];

  void _continue() {
    final plan = _plans.firstWhere((p) => p.id == _selectedPlanId);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutScreen(plan: plan)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.headerLogoBg,
                borderRadius: BorderRadius.circular(AppSpacing.lg),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: AppColors.headerLogoGlyph, size: 32),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Medaculous Pro', style: AppTextStyles.headline, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Everything in your trial, with no time limit.',
            style: AppTextStyles.body.copyWith(color: context.secondaryText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final feature in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(feature.$1, style: AppTextStyles.bodyStrong),
                        Text(feature.$2, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          for (final plan in _plans) ...[
            _PlanCard(
              plan: plan,
              selected: _selectedPlanId == plan.id,
              onTap: () => setState(() => _selectedPlanId = plan.id),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _continue,
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            "You'll review your order and enter payment details on the next screen — nothing is charged until checkout is confirmed.",
            style: AppTextStyles.micro.copyWith(color: context.secondaryText),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  final PricingPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark ? AppColors.slate800 : Colors.white),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: selected ? AppColors.primary : (isDark ? AppColors.slate700 : AppColors.slate200),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(plan.title, style: AppTextStyles.bodyStrong),
                      const SizedBox(width: AppSpacing.sm),
                      Text(plan.priceLabel, style: AppTextStyles.bodyStrong.copyWith(color: AppColors.primary)),
                      if (plan.badge != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            plan.badge!,
                            style: AppTextStyles.micro.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(plan.billingNote, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : context.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}
