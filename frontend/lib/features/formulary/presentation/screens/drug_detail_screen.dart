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

class _DrugSection {
  const _DrugSection(this.title, this.icon, this.bg, this.iconColor, this.value);

  final String title;
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final String value;
}

class _DrugDetailScreenState extends ConsumerState<DrugDetailScreen> {
  late Future<DrugProfile> _drugFuture;

  @override
  void initState() {
    super.initState();
    _drugFuture = ref.read(formularyApiProvider).getDrug(widget.drugId);
  }

  // 3x4 grid replacing the old vertical accordion list (client feedback,
  // 2026-08-15: scrolling a long vertical list "doesn't look good"; wants a
  // grid matching their reference's color scheme).
  List<_DrugSection> _sections(DrugProfile drug) => [
    _DrugSection(
      'Overview',
      Icons.info_outline_rounded,
      const Color(0xFFE8F2FF),
      const Color(0xFF155DFC),
      'Generic Name: ${drug.genericName}\nClass: ${drug.drugClass}\nTherapeutic Area: ${drug.therapeuticArea}',
    ),
    _DrugSection('Brands', Icons.sell_outlined, const Color(0xFFFCE7F3), const Color(0xFFDB2777), drug.brandNames),
    _DrugSection(
      'Mechanism of Action',
      Icons.science_outlined,
      const Color(0xFFF2E8FF),
      const Color(0xFF9810FA),
      drug.mechanismOfAction,
    ),
    _DrugSection(
      'Indications',
      Icons.check_circle_outline_rounded,
      const Color(0xFFE8F8EE),
      const Color(0xFF009966),
      drug.indications,
    ),
    _DrugSection(
      'Dosage',
      Icons.medication_liquid_outlined,
      const Color(0xFFECFEFF),
      const Color(0xFF0092B8),
      drug.dosage,
    ),
    _DrugSection(
      'Contraindications',
      Icons.block_rounded,
      const Color(0xFFFEE2E2),
      const Color(0xFFDC2626),
      drug.contraindications,
    ),
    _DrugSection(
      'Adverse Effects',
      Icons.warning_amber_rounded,
      const Color(0xFFFFE4E6),
      const Color(0xFFE11D48),
      drug.adverseEffects,
    ),
    _DrugSection(
      'Drug Interactions',
      Icons.swap_horiz_rounded,
      const Color(0xFFEEF2FF),
      const Color(0xFF4F39F6),
      drug.drugInteractions,
    ),
    _DrugSection(
      'Pregnancy & Lactation',
      Icons.pregnant_woman_outlined,
      const Color(0xFFF3E8FF),
      const Color(0xFF7C3AED),
      drug.pregnancyLactation,
    ),
    _DrugSection(
      'Monitoring',
      Icons.monitor_heart_outlined,
      const Color(0xFFFCE7F3),
      const Color(0xFFDB2777),
      drug.monitoringParameters,
    ),
    _DrugSection(
      'Pharmacokinetics',
      Icons.timeline_rounded,
      const Color(0xFFCCFBF1),
      const Color(0xFF0D9488),
      drug.pharmacokinetics,
    ),
    _DrugSection(
      'Clinical Notes (AI)',
      Icons.auto_awesome_rounded,
      const Color(0xFFF2E8FF),
      const Color(0xFF9810FA),
      drug.clinicalNotes,
    ),
  ];

  void _openSection(_DrugSection section) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: section.bg, borderRadius: BorderRadius.circular(AppSpacing.sm)),
                    child: Icon(section.icon, color: section.iconColor, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(section.title, style: AppTextStyles.title)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Text(
                  section.value.isEmpty ? 'No information available.' : section.value,
                  style: AppTextStyles.body.copyWith(
                    color: section.value.isEmpty
                        ? AppColors.slate400
                        : (isDark ? AppColors.slate200 : AppColors.slate700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
          final sections = _sections(drug);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                // Centered — owner feedback, 2026-08-17: title and the blue
                // class badge below it were left-aligned and looked skewed.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      drug.genericName.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        drug.drugClass,
                        style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (drug.isAiGenerated) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.aiPurple),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'AI-generated profile',
                            style: AppTextStyles.micro.copyWith(color: AppColors.aiPurple),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return _DrugSectionCell(section: section, onTap: () => _openSection(section));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'AI can make mistakes. Always double check doses and brand names.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.micro.copyWith(color: AppColors.slate400),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DrugSectionCell extends StatelessWidget {
  const _DrugSectionCell({required this.section, required this.onTap});

  final _DrugSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate800 : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.md),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: section.bg, borderRadius: BorderRadius.circular(AppSpacing.sm)),
              child: Icon(section.icon, color: section.iconColor, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              section.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.cardTitleText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
