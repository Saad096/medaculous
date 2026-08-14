import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              DiseaseNotesSection(folderName: systemName),
              if (sectionKeys.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: Text(
                      'No content available for this condition yet.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.slate400,
                      ),
                    ),
                  ),
                )
              else
                for (final (index, key) in sectionKeys.indexed)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ExpansionTile(
                      title: Text(key, style: AppTextStyles.bodyStrong),
                      initiallyExpanded: index == 0,
                      childrenPadding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: disease.sections[key]!,
                          // This Card follows the ambient theme (dark card in
                          // dark mode, white in light mode), so — unlike the
                          // AI chat bubble, which is always light — colors
                          // here must flip with brightness, not be hardcoded
                          // dark (that made body text invisible on the dark
                          // card in dark mode).
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(
                                Theme.of(context),
                              ).copyWith(
                                p: AppTextStyles.body.copyWith(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.slate900,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
