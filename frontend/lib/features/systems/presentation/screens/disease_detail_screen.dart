import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/disease.dart';
import '../providers/systems_providers.dart';

class DiseaseDetailScreen extends ConsumerStatefulWidget {
  const DiseaseDetailScreen({
    required this.diseaseId,
    required this.diseaseName,
    super.key,
  });

  final String diseaseId;
  final String? diseaseName;

  @override
  ConsumerState<DiseaseDetailScreen> createState() =>
      _DiseaseDetailScreenState();
}

// Custom illustrated icon per grid cell (owner-supplied art, 2026-09-11 —
// replaces the earlier placeholder Material icons entirely).
const _sectionIconAsset = <String, String>{
  'Definition': 'assets/images/sections/definition.png',
  'Classification': 'assets/images/sections/classification.png',
  'Signs/Symptoms': 'assets/images/sections/signs_symptoms.png',
  'Anatomy': 'assets/images/sections/anatomy.png',
  'Pathophysiology': 'assets/images/sections/pathophysiology.png',
  'Approach': 'assets/images/sections/approach.png',
  'Investigations': 'assets/images/sections/investigations.png',
  'Diagnosis': 'assets/images/sections/diagnosis.png',
  'Differentials': 'assets/images/sections/differentials.png',
  'Patient Advice': 'assets/images/sections/patient_advice.png',
  'Management': 'assets/images/sections/management.png',
  'Prescribing Information': 'assets/images/sections/prescribing_information.png',
  'Calculators': 'assets/images/sections/calculators.png',
  'Evidence': 'assets/images/sections/evidence.png',
  'Complications': 'assets/images/sections/complications.png',
};
const _notesIconAsset = 'assets/images/sections/notes_section.png';

class _DiseaseDetailScreenState extends ConsumerState<DiseaseDetailScreen> {
  late Future<DiseaseDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = ref.read(systemsApiProvider).getDisease(widget.diseaseId);
  }

  // Straight into the editor, ready to type or to keep editing — a disease
  // topic gets exactly one private note (app.models.disease.DiseaseNote),
  // separate from the app-wide Notes feature entirely, so there's never a
  // list to show here, just the one note (owner feedback, 2026-09-11).
  Future<void> _openNotes(BuildContext context, String diseaseName) async {
    final existingContent = await ref.read(systemsApiProvider).getDiseaseNote(widget.diseaseId);
    if (!context.mounted) return;
    await context.push(
      '/notes/editor',
      extra: {
        'diseaseId': widget.diseaseId,
        'diseaseNoteContentHtml': existingContent,
        'folderBreadcrumb': diseaseName,
        'autoFocus': existingContent == null || existingContent.isEmpty,
      },
    );
  }

  void _openSection(BuildContext context, String key, String content) {
    final iconAsset = _sectionIconAsset[key] ?? _notesIconAsset;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
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
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.slate700 : AppColors.slate100,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(iconAsset),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(key, style: AppTextStyles.title)),
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
                child: MarkdownBody(
                  data: content,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: AppTextStyles.body.copyWith(color: isDark ? Colors.white : AppColors.slate900),
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
      appBar: AppBar(title: Text(widget.diseaseName ?? 'Disease')),
      body: FutureBuilder<DiseaseDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load disease.',
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
            );
          }
          final disease = snapshot.data!;
          final sectionKeys = [
            for (final key in kDiseaseSectionOrder)
              if (disease.sections.containsKey(key)) key,
          ];
          if (sectionKeys.isEmpty) {
            return Center(
              child: Text(
                'No content available for this condition yet.',
                style: AppTextStyles.body.copyWith(color: AppColors.slate400),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.95,
            ),
            itemCount: sectionKeys.length + 1,
            itemBuilder: (context, index) {
              if (index == sectionKeys.length) {
                return _SectionCell(
                  label: 'Notes',
                  iconAsset: _notesIconAsset,
                  onTap: () => _openNotes(context, disease.name),
                );
              }
              final key = sectionKeys[index];
              return _SectionCell(
                label: key,
                iconAsset: _sectionIconAsset[key] ?? _notesIconAsset,
                onTap: () => _openSection(context, key, disease.sections[key]!),
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionCell extends StatelessWidget {
  const _SectionCell({
    required this.label,
    required this.iconAsset,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        // Plain card with a soft shadow for depth, icon keeps its own
        // accent color — owner feedback, 2026-08-22: this screen's cells
        // should not be background-tinted per category or bordered, just a
        // plain white/dark card with a "3D" raised feel.
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate800 : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.md),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconAsset, width: 32, height: 32),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
