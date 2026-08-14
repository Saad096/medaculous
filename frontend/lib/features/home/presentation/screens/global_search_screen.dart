import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../formulary/domain/formulary.dart';
import '../../../formulary/presentation/providers/formulary_providers.dart';
import '../../../systems/domain/disease.dart';
import '../../../systems/presentation/providers/systems_providers.dart';

/// Home screen's global search ("Search conditions, medications" per the
/// client scope doc) — searches Systems' disease index server-side and
/// filters the (small, curated) Formulary tree client-side, since there's no
/// dedicated drug-search endpoint that doesn't also trigger AI generation
/// on a miss (search-or-create is only appropriate for an explicit submit,
/// not every keystroke).
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<DiseaseSummary> _diseaseResults = [];
  List<DrugSummary> _drugResults = [];
  bool _isSearching = false;
  FormularyTree? _tree;

  @override
  void initState() {
    super.initState();
    ref.read(formularyApiProvider).getTree().then((tree) {
      if (mounted) setState(() => _tree = tree);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _diseaseResults = [];
        _drugResults = [];
      });
      return;
    }
    setState(() => _drugResults = _filterDrugs(trimmed));
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isSearching = true);
      final results = await ref
          .read(systemsApiProvider)
          .searchDiseases(trimmed);
      if (!mounted) return;
      setState(() {
        _diseaseResults = results;
        _isSearching = false;
      });
    });
  }

  List<DrugSummary> _filterDrugs(String query) {
    final tree = _tree;
    if (tree == null) return [];
    final lower = query.toLowerCase();
    final matches = <DrugSummary>[];
    for (final classes in tree.values) {
      for (final drugs in classes.values) {
        for (final drug in drugs) {
          if (drug.genericName.toLowerCase().contains(lower) ||
              drug.brandNames.toLowerCase().contains(lower)) {
            matches.add(drug);
          }
        }
      }
    }
    return matches.take(20).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().length >= 2;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search conditions, medications',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
          style: AppTextStyles.body,
        ),
      ),
      body: !hasQuery
          ? Center(
              child: Text(
                'Type at least 2 characters to search.',
                style: AppTextStyles.body.copyWith(color: AppColors.slate400),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                if (_drugResults.isNotEmpty) ...[
                  _SectionHeader('Medications'),
                  for (final drug in _drugResults)
                    ListTile(
                      leading: const Icon(
                        Icons.medication_outlined,
                        color: AppColors.formularyIcon,
                      ),
                      title: Text(drug.genericName, style: AppTextStyles.body),
                      subtitle: Text(
                        drug.drugClass,
                        style: AppTextStyles.caption.copyWith(
                          color: context.secondaryText,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.slate400,
                      ),
                      onTap: () => context.push(
                        '/formulary/drugs/${drug.id}',
                        extra: drug.genericName,
                      ),
                    ),
                ],
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_diseaseResults.isNotEmpty) ...[
                  _SectionHeader('Conditions'),
                  for (final disease in _diseaseResults)
                    ListTile(
                      leading: const Icon(
                        Icons.biotech_outlined,
                        color: AppColors.systemsIcon,
                      ),
                      title: Text(disease.name, style: AppTextStyles.body),
                      subtitle: Text(
                        disease.category,
                        style: AppTextStyles.caption.copyWith(
                          color: context.secondaryText,
                        ),
                      ),
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
                if (!_isSearching &&
                    _diseaseResults.isEmpty &&
                    _drugResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No matches.',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.slate400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: AppTextStyles.micro.copyWith(
          color: context.secondaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
