import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

/// Follows the sheet's own light/dark text color (unlike chat_screen.dart's
/// AI-bubble stylesheet, which is pinned to a fixed light card) since this
/// content sits directly on the app's themed bottom sheet background.
MarkdownStyleSheet _sectionMarkdownStyleSheet(bool isDark) {
  final bodyColor = isDark ? AppColors.slate200 : AppColors.slate700;
  return MarkdownStyleSheet(
    p: AppTextStyles.body.copyWith(color: bodyColor),
    pPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
    strong: AppTextStyles.bodyStrong.copyWith(color: bodyColor),
    em: AppTextStyles.body.copyWith(color: bodyColor, fontStyle: FontStyle.italic),
    listBullet: AppTextStyles.body.copyWith(color: bodyColor),
  );
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
  bool _isEnhancing = false;

  @override
  void initState() {
    super.initState();
    _drugFuture = ref.read(formularyApiProvider).getDrug(widget.drugId);
  }

  Future<void> _enhanceProfile() async {
    setState(() => _isEnhancing = true);
    try {
      final updated = await ref.read(formularyApiProvider).enhanceProfile(widget.drugId);
      if (!mounted) return;
      setState(() => _drugFuture = Future.value(updated));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isEnhancing = false);
    }
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
              child: section.value.isEmpty
                  ? SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                      child: Text(
                        'No information available.',
                        style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                      ),
                    )
                  // AI-generated content now comes back as markdown (bold
                  // **Heading:** lines plus blank-line-separated paragraphs,
                  // see formulary.py's _GENERATE_SYSTEM_PROMPT) instead of one
                  // dense unbroken block — owner feedback, 2026-09-13: "DOSE
                  // displays information without using paragraphs". Rendered
                  // via MarkdownBody so those headings/paragraphs actually
                  // show, not as literal '**' characters.
                  //
                  // Justify (equal left/right edges) was tried per owner
                  // request, 2026-09-11, but Flutter stretches inter-word
                  // spacing to force each line flush, and on a normal
                  // paragraph width that reads as uneven, hard-to-read gaps
                  // more often than it reads as "clean" — reverted in favor
                  // of readability, per the very next round of feedback.
                  : Markdown(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                      data: section.value,
                      styleSheet: _sectionMarkdownStyleSheet(isDark),
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
                    const SizedBox(height: AppSpacing.sm),
                    _EnhanceProfileButton(isLoading: _isEnhancing, onTap: _enhanceProfile),
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
                  style: AppTextStyles.micro.copyWith(
                    color: AppColors.slate400,
                    fontStyle: FontStyle.italic,
                  ),
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
            // A one-word title (e.g. "Pharmacokinetics", "Contraindications")
            // has no space to wrap at, so a plain 2-line wrap could leave a
            // single orphan character on its own line (e.g. "Pharmacokinetic"
            // / "s") — FittedBox shrinking the whole word onto one line
            // instead fixes that (owner feedback, 2026-09-11).
            //
            // But forcing that same single-line-then-shrink treatment onto a
            // multi-word title (e.g. "Pregnancy & Lactation") shrinks it far
            // more than it needs — a plain 2-line wrap already breaks
            // cleanly at the word boundary, so it renders noticeably smaller
            // than shorter one-word titles like "Dosage" for no reason
            // (owner feedback, 2026-09-13: "this box text size is smaller
            // than others"). Only reach for the shrink-to-fit treatment when
            // there's no space to wrap at in the first place.
            section.title.contains(' ')
                ? Text(
                    section.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.cardTitleText,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      section.title,
                      textAlign: TextAlign.center,
                      softWrap: false,
                      style: AppTextStyles.micro.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.cardTitleText,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Owner-supplied reference design, 2026-09-11: a small lavender pill with a
/// sparkle icon, sitting right below the drug class badge. Re-runs the AI
/// generation for every content field on this drug (see
/// backend POST /formulary/drugs/{id}/enhance) — the curated drugs seeded on
/// first startup only ever had two fields lazily backfilled, so most of
/// their profile otherwise stays sparse forever.
class _EnhanceProfileButton extends StatelessWidget {
  const _EnhanceProfileButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.notesCardBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.notesIcon),
              )
            else
              const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.notesIcon),
            const SizedBox(width: AppSpacing.xs),
            Text(
              isLoading ? 'Enhancing…' : 'Enhance Profile with AI',
              style: AppTextStyles.caption.copyWith(color: AppColors.notesIcon, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
