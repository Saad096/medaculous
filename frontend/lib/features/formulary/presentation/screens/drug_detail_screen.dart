import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/formulary.dart';
import '../providers/formulary_providers.dart';

class DrugDetailScreen extends ConsumerStatefulWidget {
  const DrugDetailScreen({
    required this.drugId,
    required this.genericName,
    super.key,
  });

  final String drugId;
  final String? genericName;

  @override
  ConsumerState<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends ConsumerState<DrugDetailScreen> {
  late Future<DrugProfile> _drugFuture;

  @override
  void initState() {
    super.initState();
    _drugFuture = ref.read(formularyApiProvider).getDrug(widget.drugId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.genericName ?? 'Drug')),
      body: FutureBuilder<DrugProfile>(
        future: _drugFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacing.md),
                    Text('Loading drug profile…'),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Failed to load drug.';
            return Center(
              child: Text(
                message,
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
            );
          }
          final drug = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (drug.isAiGenerated)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.aiPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: AppColors.aiPurple,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'AI-generated profile',
                        style: AppTextStyles.micro.copyWith(
                          color: AppColors.aiPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              _sectionCard(
                'Overview',
                Icons.info_outline_rounded,
                initiallyExpanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labeledText('Generic Name', drug.genericName),
                    _labeledText('Class', drug.drugClass),
                    _labeledText('Therapeutic Area', drug.therapeuticArea),
                  ],
                ),
              ),
              _sectionCard(
                'Brands',
                Icons.sell_outlined,
                child: _plainText(drug.brandNames),
              ),
              _sectionCard(
                'Mechanism of Action',
                Icons.science_outlined,
                child: _plainText(drug.mechanismOfAction),
              ),
              _sectionCard(
                'Indications',
                Icons.check_circle_outline_rounded,
                child: _plainText(drug.indications),
              ),
              _sectionCard(
                'Dosage',
                Icons.medication_liquid_outlined,
                child: _plainText(drug.dosage),
              ),
              _sectionCard(
                'Contraindications',
                Icons.block_rounded,
                child: _plainText(drug.contraindications),
              ),
              _sectionCard(
                'Adverse Effects',
                Icons.warning_amber_rounded,
                child: _plainText(drug.adverseEffects),
              ),
              _sectionCard(
                'Drug Interactions',
                Icons.swap_horiz_rounded,
                child: _plainText(drug.drugInteractions),
              ),
              _sectionCard(
                'Pregnancy & Lactation',
                Icons.pregnant_woman_outlined,
                child: _plainText(drug.pregnancyLactation),
              ),
              _sectionCard(
                'Monitoring',
                Icons.monitor_heart_outlined,
                child: _plainText(drug.monitoringParameters),
              ),
              _sectionCard(
                'Pharmacokinetics',
                Icons.timeline_rounded,
                child: _plainText(drug.pharmacokinetics),
              ),
              _sectionCard(
                'Clinical Notes (AI)',
                Icons.auto_awesome_rounded,
                child: _plainText(drug.clinicalNotes),
              ),
            ],
          );
        },
      ),
    );
  }

  // These sit inside a themed Card (dark card in dark mode), so their text
  // color must flip with brightness — `slate700` alone reads fine on the
  // light card but is far too close to the dark card's own `slate800` in
  // dark mode (fails WCAG AA contrast).
  Widget _plainText(String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      value.isEmpty ? 'No information available.' : value,
      style: AppTextStyles.body.copyWith(
        color: value.isEmpty
            ? AppColors.slate400
            : (isDark ? AppColors.slate200 : AppColors.slate700),
      ),
    );
  }

  Widget _labeledText(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.body.copyWith(
            color: isDark ? AppColors.slate200 : AppColors.slate700,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(
    String title,
    IconData icon, {
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: AppTextStyles.bodyStrong),
        initiallyExpanded: initiallyExpanded,
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    );
  }
}
