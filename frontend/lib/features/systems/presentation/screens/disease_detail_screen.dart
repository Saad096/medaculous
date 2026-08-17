import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/presentation/providers/notes_providers.dart';
import '../../domain/disease.dart';
import '../providers/systems_providers.dart';
import '../widgets/disease_notes_section.dart';

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

// One (icon, tint) pair per grid cell — cycles through the app's existing
// feature-card palette so the grid reads as colorful and varied without
// inventing a whole new color set (client feedback, 2026-08-15: "Grid
// layout for disease topic page to allow minimum scrolling").
const _sectionStyle = <String, (IconData, Color, Color)>{
  'Definition': (Icons.description_outlined, AppColors.systemsCardBg, AppColors.systemsIcon),
  'Classification': (Icons.category_outlined, AppColors.drugRecsCardBg, AppColors.drugRecsIcon),
  'Signs/Symptoms': (Icons.sick_outlined, AppColors.symptomsCardBg, AppColors.symptomsIcon),
  'Anatomy': (Icons.accessibility_new_outlined, AppColors.knowledgeHubCardBg, AppColors.knowledgeHubIcon),
  'Pathophysiology': (Icons.biotech_outlined, AppColors.examPlannerCardBg, AppColors.examPlannerIcon),
  'Approach': (Icons.explore_outlined, AppColors.wardCardBg, AppColors.wardIcon),
  'Investigations': (Icons.search_rounded, AppColors.formularyCardBg, AppColors.formularyIcon),
  'Diagnosis': (Icons.fact_check_outlined, AppColors.notesCardBg, AppColors.notesIcon),
  'Differentials': (Icons.compare_arrows_rounded, AppColors.aiCardBg, AppColors.aiIcon),
  'Patient Advice': (Icons.chat_bubble_outline_rounded, AppColors.calculatorCardBg, AppColors.calculatorIcon),
  'Management': (Icons.healing_outlined, AppColors.osceCardBg, AppColors.osceIcon),
  'Prescribing Information': (Icons.medication_outlined, AppColors.drugRecsCardBg, AppColors.drugRecsIcon),
  'Calculators': (Icons.calculate_outlined, AppColors.calculatorCardBg, AppColors.calculatorIcon),
  'Evidence': (Icons.verified_outlined, AppColors.systemsCardBg, AppColors.systemsIcon),
  'Complications': (Icons.warning_amber_rounded, AppColors.symptomsCardBg, AppColors.danger),
};
const _notesStyle = (Icons.edit_note_rounded, AppColors.notesCardBg, AppColors.notesIcon);

class _DiseaseDetailScreenState extends ConsumerState<DiseaseDetailScreen> {
  // Bundles the disease with its resolved *system* name (e.g. "Cardiology")
  // rather than `disease.category`, which is a finer-grained sub-category
  // (e.g. "Airway Diseases" under Pulmonology) — the Notes folders in the
  // reference screenshots are named after specialties/systems, so that's
  // what DiseaseNotesSection needs to match against.
  late Future<(DiseaseDetail, String systemName)> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _load();
  }

  Future<(DiseaseDetail, String)> _load() async {
    final api = ref.read(systemsApiProvider);
    final results = await Future.wait([
      api.getDisease(widget.diseaseId),
      api.listSystems(),
    ]);
    final disease = results[0] as DiseaseDetail;
    final systems = results[1] as List<MedicalSystem>;
    final systemName = systems
        .firstWhere(
          (system) => system.id == disease.systemId,
          orElse: () => MedicalSystem(
            id: disease.systemId,
            name: disease.category,
            icon: '',
          ),
        )
        .name;
    return (disease, systemName);
  }

  // Straight into the editor, ready to type, when this topic has no notes
  // yet — owner feedback, 2026-08-17: having to tap "Add note" first before
  // being able to write felt broken. Only shows the notes-list sheet when
  // there's actually something to list.
  Future<void> _openNotes(BuildContext context, String systemName) async {
    final api = ref.read(notesApiProvider);
    final folders = await api.listFolders();
    final match = folders.where((f) => f.name.toLowerCase() == systemName.toLowerCase());
    final existing = match.isEmpty ? null : match.first;
    final notes = existing == null ? <Note>[] : await api.listNotes(folderId: existing.id);
    if (!context.mounted) return;

    if (notes.isEmpty) {
      final folderId = existing?.id ?? (await api.createFolder(name: systemName)).id;
      if (!context.mounted) return;
      await context.push(
        '/notes/editor',
        extra: {'folderId': folderId, 'folderBreadcrumb': systemName, 'autoFocus': true},
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // A modal sheet only closes by swiping down or tapping the
              // scrim by default — no visible way back once it grows tall
              // (owner feedback, 2026-08-17: "opened the whole full screen
              // ... put back navigation too").
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
              DiseaseNotesSection(folderName: systemName),
            ],
          ),
        ),
      ),
    );
  }

  void _openSection(BuildContext context, String key, String content) {
    final (icon, bg, iconColor) = _sectionStyle[key] ?? (Icons.description_outlined, AppColors.systemsCardBg, AppColors.systemsIcon);
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
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppSpacing.sm)),
                    child: Icon(icon, color: iconColor, size: 20),
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
      body: FutureBuilder<(DiseaseDetail, String)>(
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
          final (disease, systemName) = snapshot.data!;
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
                  icon: _notesStyle.$1,
                  bg: _notesStyle.$2,
                  iconColor: _notesStyle.$3,
                  onTap: () => _openNotes(context, systemName),
                );
              }
              final key = sectionKeys[index];
              final (icon, bg, iconColor) = _sectionStyle[key] ?? (Icons.description_outlined, AppColors.systemsCardBg, AppColors.systemsIcon);
              return _SectionCell(
                label: key,
                icon: icon,
                bg: bg,
                iconColor: iconColor,
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
    required this.icon,
    required this.bg,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        // Whole cell tinted, not just the icon chip — owner feedback,
        // 2026-08-17: matches the colored-card treatment on Home.
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w600, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}
