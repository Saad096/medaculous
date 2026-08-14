import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/disease.dart';
import '../providers/systems_providers.dart';

class DiseaseListScreen extends ConsumerStatefulWidget {
  const DiseaseListScreen({
    required this.systemId,
    required this.systemName,
    super.key,
  });

  final String systemId;
  final String? systemName;

  @override
  ConsumerState<DiseaseListScreen> createState() => _DiseaseListScreenState();
}

class _DiseaseListScreenState extends ConsumerState<DiseaseListScreen> {
  late Future<List<DiseaseSummary>> _diseasesFuture;

  @override
  void initState() {
    super.initState();
    _diseasesFuture = ref
        .read(systemsApiProvider)
        .listDiseases(widget.systemId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.systemName ?? 'Diseases')),
      body: FutureBuilder<List<DiseaseSummary>>(
        future: _diseasesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load diseases.',
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
            );
          }
          final diseases = snapshot.data!;
          if (diseases.isEmpty) {
            return Center(
              child: Text(
                'No diseases in this system yet.',
                style: AppTextStyles.body.copyWith(color: AppColors.slate400),
              ),
            );
          }

          final byCategory = <String, List<DiseaseSummary>>{};
          for (final disease in diseases) {
            byCategory.putIfAbsent(disease.category, () => []).add(disease);
          }
          final categories = byCategory.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final items = byCategory[category]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      category,
                      style: AppTextStyles.caption.copyWith(
                        color: context.secondaryText,
                      ),
                    ),
                  ),
                  for (final disease in items)
                    ListTile(
                      title: Text(disease.name, style: AppTextStyles.body),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.slate400,
                      ),
                      onTap: () => context.push(
                        '/diseases/${disease.id}',
                        extra: disease.name,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
