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
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _diseasesFuture = ref
        .read(systemsApiProvider)
        .listDiseases(widget.systemId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

          // Client feedback, 2026-08-17: live keyword filter, updates the
          // list below as the user types — no submit button needed.
          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? diseases
              : diseases.where((d) => d.name.toLowerCase().contains(query)).toList();

          final byCategory = <String, List<DiseaseSummary>>{};
          for (final disease in filtered) {
            byCategory.putIfAbsent(disease.category, () => []).add(disease);
          }
          final categories = byCategory.keys.toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search conditions in ${widget.systemName ?? "this system"}',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                    filled: true,
                  ),
                ),
              ),
              Expanded(
                child: categories.isEmpty
                    ? Center(
                        child: Text(
                          'No conditions match "$query".',
                          style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final items = byCategory[category]!;
                          return _CategoryGroup(category: category, diseases: items);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Each category rendered as a light, rounded card — owner feedback,
/// 2026-08-17: the flat plain-text grouping should have "a light boxes
/// feel" instead.
class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({required this.category, required this.diseases});

  final String category;
  final List<DiseaseSummary> diseases;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : AppColors.slate50,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        border: Border.all(color: isDark ? AppColors.slate700 : AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
            child: Text(
              category,
              style: AppTextStyles.micro.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700),
            ),
          ),
          for (final disease in diseases)
            ListTile(
              title: Text(disease.name, style: AppTextStyles.body),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
              onTap: () => context.push('/diseases/${disease.id}', extra: disease.name),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
