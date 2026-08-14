import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/pharmacy.dart';

Color _tierColor(String tier) {
  switch (tier) {
    case 'First-line treatment':
      return AppColors.success;
    case 'Second-line treatment':
      return AppColors.warning;
    default:
      return AppColors.aiPurple;
  }
}

class MedicationCard extends StatefulWidget {
  const MedicationCard({
    required this.medication,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.initiallyExpanded = false,
    super.key,
  });

  final Medication medication;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool initiallyExpanded;

  @override
  State<MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends State<MedicationCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          Text(med.genericName, style: AppTextStyles.bodyStrong),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _tierColor(med.tier).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(med.tier, style: AppTextStyles.micro.copyWith(color: _tierColor(med.tier))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Class: ${med.drugClass}', style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onToggleFavorite,
                  icon: Icon(
                    widget.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: widget.isFavorite ? AppColors.danger : AppColors.slate400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _quickFact('Adult dose', med.adultDose),
                _quickFact('Route / Freq', '${med.route} (${med.frequency})'),
                if (med.brandNames.isNotEmpty) _quickFact('Brands', med.brandNames.take(2).join(', ')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Hide Details' : 'View Full Details'),
              ),
            ),
            if (_expanded) ...[
              const Divider(),
              _sectionTitle('Recommendation Rationale'),
              Text(
                med.rankingRationale,
                style: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate200 : AppColors.slate700),
              ),
              const SizedBox(height: AppSpacing.md),
              _sectionTitle('Dosing & Administration'),
              _bullet('Pediatric dose', med.pediatricDose, isDark),
              _bullet('Max daily dose', med.maxDailyDose, isDark),
              _bullet('Typical duration', med.typicalDuration, isDark),
              const SizedBox(height: AppSpacing.md),
              _sectionTitle('Safety & Patient Factors'),
              _bullet('Pregnancy safety', med.pregnancySafety, isDark),
              _bullet('Breastfeeding safety', med.breastfeedingSafety, isDark),
              _bullet('Renal adjustment', med.renalAdjustment, isDark),
              _bullet('Hepatic adjustment', med.hepaticAdjustment, isDark),
              _bullet('Monitoring', med.monitoringRequirements, isDark),
              const SizedBox(height: AppSpacing.md),
              _sectionTitle('Pharmacokinetics & Warnings'),
              _bullet('Mechanism', med.mechanismOfAction, isDark),
              _bullet('Side effects', med.sideEffects.join(', '), isDark),
              _bullet('Contraindications', med.contraindications.join(', '), isDark),
              _bullet('Interactions', med.interactions.join(', '), isDark),
              if (med.clinicalReferences.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _sectionTitle('Evidence-Based Clinical Guidelines'),
                for (final ref in med.clinicalReferences)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.slate900 : AppColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? AppColors.slate700 : AppColors.slate200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${ref.guideline} (${ref.year})', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                            Text('Evidence: ${ref.evidenceLevel}', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(ref.details, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickFact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.micro.copyWith(color: AppColors.slate400)),
        Text(value, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(title, style: AppTextStyles.bodyStrong.copyWith(fontSize: 13)),
    );
  }

  Widget _bullet(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.caption.copyWith(color: isDark ? AppColors.slate200 : AppColors.slate700),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
