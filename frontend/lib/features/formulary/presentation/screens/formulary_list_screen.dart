import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../domain/formulary.dart';
import '../providers/formulary_providers.dart';

/// DISCOVERY_REPORT.md §4: ~100 curated drugs, System -> Class -> Drug, with
/// AI-generated monograph creation for unknown searches (cached permanently,
/// shared by every user) — a straight port of Formulary.tsx's UX intent.
class FormularyListScreen extends ConsumerStatefulWidget {
  const FormularyListScreen({super.key});

  @override
  ConsumerState<FormularyListScreen> createState() =>
      _FormularyListScreenState();
}

class _FormularyListScreenState extends ConsumerState<FormularyListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  FormularyTree _tree = {};
  bool _isLoading = true;
  String? _error;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final tree = await ref.read(formularyApiProvider).getTree();
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  FormularyTree get _filteredTree {
    if (_query.trim().isEmpty) return _tree;
    final q = _query.toLowerCase();
    final result = <String, Map<String, List<DrugSummary>>>{};
    for (final systemEntry in _tree.entries) {
      final classes = <String, List<DrugSummary>>{};
      for (final classEntry in systemEntry.value.entries) {
        final drugs = classEntry.value.where((d) {
          return d.genericName.toLowerCase().contains(q) ||
              d.brandNames.toLowerCase().contains(q) ||
              d.drugClass.toLowerCase().contains(q) ||
              d.therapeuticArea.toLowerCase().contains(q);
        }).toList();
        if (drugs.isNotEmpty) classes[classEntry.key] = drugs;
      }
      if (classes.isNotEmpty) result[systemEntry.key] = classes;
    }
    return result;
  }

  bool get _hasExactMatch {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final classes in _tree.values) {
      for (final drugs in classes.values) {
        for (final d in drugs) {
          if (d.genericName.toLowerCase() == q ||
              d.brandNames
                  .toLowerCase()
                  .split(',')
                  .map((b) => b.trim())
                  .contains(q)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  Future<void> _createProfile() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isCreating = true);
    try {
      final result = await ref.read(formularyApiProvider).searchOrCreate(query);
      if (!mounted) return;
      if (!result.isValidDrug || result.profile == null) {
        showAppToast(context, result.message, kind: AppToastKind.info);
        return;
      }
      await _load();
      if (!mounted) return;
      context.push(
        '/formulary/drugs/${result.profile!.id}',
        extra: result.profile!.genericName,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTree;
    return NavShell(
      current: AppNavTab.formulary,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Formulary'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search drugs, classes, or systems…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _query = '';
                        }),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  borderSide: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.slate700
                        : AppColors.slate200,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    children: [
                      for (final systemEntry in filtered.entries)
                        _SystemTile(
                          system: systemEntry.key,
                          classes: systemEntry.value,
                        ),
                      if (!_hasExactMatch && _query.trim().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.aiPurple.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.aiPurple.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: AppColors.aiPurple,
                                size: 32,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Create New Profile',
                                style: AppTextStyles.title.copyWith(
                                  color: AppColors.aiPurple,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Generate a clinical profile for "$_query" using AI.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.caption.copyWith(
                                  color: context.secondaryText,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton(
                                onPressed: _isCreating ? null : _createProfile,
                                child: _isCreating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Generate Profile'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SystemTile extends StatefulWidget {
  const _SystemTile({required this.system, required this.classes});

  final String system;
  final Map<String, List<DrugSummary>> classes;

  @override
  State<_SystemTile> createState() => _SystemTileState();
}

class _SystemTileState extends State<_SystemTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            tileColor: AppColors.primary.withValues(alpha: 0.06),
            leading: const Icon(
              Icons.category_outlined,
              color: AppColors.primary,
            ),
            title: Text(widget.system, style: AppTextStyles.bodyStrong),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            for (final classEntry in widget.classes.entries)
              _ClassTile(className: classEntry.key, drugs: classEntry.value),
        ],
      ),
    );
  }
}

class _ClassTile extends StatefulWidget {
  const _ClassTile({required this.className, required this.drugs});

  final String className;
  final List<DrugSummary> drugs;

  @override
  State<_ClassTile> createState() => _ClassTileState();
}

class _ClassTileState extends State<_ClassTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.md,
          ),
          title: Text(
            widget.className,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final drug in widget.drugs)
            ListTile(
              contentPadding: const EdgeInsets.only(
                left: AppSpacing.xxl,
                right: AppSpacing.md,
              ),
              leading: const Icon(
                Icons.medication_outlined,
                size: 18,
                color: AppColors.warning,
              ),
              title: Text(
                drug.genericName,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: drug.brandNames.isNotEmpty
                  ? Text(
                      drug.brandNames,
                      style: AppTextStyles.micro.copyWith(
                        color: AppColors.slate400,
                      ),
                    )
                  : null,
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
    );
  }
}
