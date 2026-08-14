import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../settings/presentation/widgets/usage_limit_dialog.dart';
import '../../domain/pharmacy.dart';
import '../providers/pharmacy_providers.dart';
import '../widgets/medication_card.dart';

const _countries = ['Pakistan', 'UK', 'USA', 'UAE', 'India', 'EU'];

const _quickExamples = [
  'Acute Fever', 'Sore Throat & Cough', 'Mild Nausea & Vomiting', 'Dry Spasmodic Cough',
  'Nasal Congestion', 'Acute Muscle Pain', 'Watery Diarrhea', 'Gastric Acid Reflux',
];

/// DISCOVERY_REPORT.md §3: AI clinical pharmacist — straight port of
/// SymptomBasedRecommendations.tsx / server.ts's three canonical endpoints,
/// with favorites moved server-side (favorite_drugs table) for cross-device
/// sync instead of the legacy localStorage-only list.
class DrugRecommendationsScreen extends ConsumerStatefulWidget {
  const DrugRecommendationsScreen({super.key});

  @override
  ConsumerState<DrugRecommendationsScreen> createState() => _DrugRecommendationsScreenState();
}

class _DrugRecommendationsScreenState extends ConsumerState<DrugRecommendationsScreen> {
  List<FavoriteDrug> _favorites = [];
  bool _favoritesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _favoritesLoading = true);
    try {
      final favorites = await ref.read(pharmacyApiProvider).listFavorites();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _favoritesLoading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _favoritesLoading = false);
    }
  }

  bool _isFavorite(Medication med) => _favorites.any((f) => f.medication.genericName.toLowerCase() == med.genericName.toLowerCase());

  Future<void> _toggleFavorite(Medication med) async {
    final api = ref.read(pharmacyApiProvider);
    final existing = _favorites.where((f) => f.medication.genericName.toLowerCase() == med.genericName.toLowerCase()).firstOrNull;
    if (existing != null) {
      setState(() => _favorites.removeWhere((f) => f.id == existing.id));
      try {
        await api.removeFavorite(existing.id);
      } on ApiException {
        if (mounted) setState(() => _favorites.add(existing));
      }
    } else {
      try {
        final added = await api.addFavorite(med);
        if (mounted) setState(() => _favorites.add(added));
      } on ApiException {
        // Leave state unchanged — the card's heart simply doesn't fill.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Drug Recommendations'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pharmacist'),
              Tab(text: 'Interactions'),
              Tab(text: 'Substitution'),
              Tab(text: 'Favorites'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PharmacistTab(isFavorite: _isFavorite, onToggleFavorite: _toggleFavorite),
            const _InteractionsTab(),
            const _SubstitutionTab(),
            _FavoritesTab(
              favorites: _favorites,
              isLoading: _favoritesLoading,
              onToggleFavorite: _toggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}

class _PharmacistTab extends ConsumerStatefulWidget {
  const _PharmacistTab({required this.isFavorite, required this.onToggleFavorite});

  final bool Function(Medication) isFavorite;
  final void Function(Medication) onToggleFavorite;

  @override
  ConsumerState<_PharmacistTab> createState() => _PharmacistTabState();
}

class _PharmacistTabState extends ConsumerState<_PharmacistTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _symptomController = TextEditingController();
  final _symptoms = <String>[];
  bool _showFilters = false;
  String _country = 'Pakistan';
  final _ageController = TextEditingController();
  String? _sex;
  final _weightController = TextEditingController();
  String _pregnancy = 'No';
  String _breastfeeding = 'No';
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();
  String _renalImpairment = 'None';
  String _hepaticImpairment = 'None';

  bool _isLoading = false;
  String? _error;
  RecommendationResult? _result;

  @override
  void dispose() {
    _symptomController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _allergiesController.dispose();
    _chronicController.dispose();
    super.dispose();
  }

  void _addSymptom([String? value]) {
    final text = (value ?? _symptomController.text).trim();
    if (text.isEmpty || _symptoms.contains(text)) return;
    setState(() {
      _symptoms.add(text);
      if (value == null) _symptomController.clear();
    });
  }

  Future<void> _review() async {
    if (_symptomController.text.trim().isNotEmpty) _addSymptom();
    if (_symptoms.isEmpty) {
      setState(() => _error = 'Please enter at least one symptom or clinical complaint.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(pharmacyApiProvider).getRecommendations(
            symptoms: _symptoms.join(', '),
            age: _ageController.text.trim(),
            sex: _sex,
            weight: _weightController.text.trim(),
            pregnancy: _pregnancy,
            breastfeeding: _breastfeeding,
            allergies: _allergiesController.text.trim(),
            chronicDiseases: _chronicController.text.trim(),
            renalImpairment: _renalImpairment,
            hepaticImpairment: _hepaticImpairment,
            country: _country,
          );
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        showUsageLimitDialog(context);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Text(
            'Disclaimer: This tool is intended for use by licensed healthcare professionals. '
            'Recommendations support clinical decision-making and do not replace professional judgment.',
            style: AppTextStyles.caption.copyWith(color: AppColors.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Symptom / Clinical Complaint', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _symptomController,
                onSubmitted: (_) => _addSymptom(),
                decoration: const InputDecoration(hintText: 'e.g. fever, sore throat, nausea', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(onPressed: () => _addSymptom(), icon: const Icon(Icons.add)),
          ],
        ),
        if (_symptoms.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final s in _symptoms) Chip(label: Text(s), onDeleted: () => setState(() => _symptoms.remove(s)))],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('QUICK EXAMPLES', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final ex in _quickExamples) ActionChip(label: Text(ex), onPressed: () => _addSymptom(ex))],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _showFilters = !_showFilters),
              icon: Icon(_showFilters ? Icons.expand_less : Icons.expand_more),
              label: const Text('Patient Risk Filters'),
            ),
            DropdownButton<String>(
              value: _country,
              items: [for (final c in _countries) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _country = v!),
            ),
          ],
        ),
        if (_showFilters)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.slate800
                  : AppColors.slate50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.slate700
                    : AppColors.slate200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ageController,
                        decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sex,
                        decoration: const InputDecoration(labelText: 'Sex', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _sex = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _weightController,
                  decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _pregnancy,
                  decoration: const InputDecoration(labelText: 'Pregnancy Status', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'No', child: Text('No')),
                    DropdownMenuItem(value: 'Yes (First Trimester)', child: Text('Yes (First Trimester)')),
                    DropdownMenuItem(value: 'Yes (Second Trimester)', child: Text('Yes (Second Trimester)')),
                    DropdownMenuItem(value: 'Yes (Third Trimester)', child: Text('Yes (Third Trimester)')),
                  ],
                  onChanged: (v) => setState(() => _pregnancy = v!),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _breastfeeding,
                  decoration: const InputDecoration(labelText: 'Lactation / Breastfeeding', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'No', child: Text('No')),
                    DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                  ],
                  onChanged: (v) => setState(() => _breastfeeding = v!),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _renalImpairment,
                  decoration: const InputDecoration(labelText: 'Renal Impairment', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'None', child: Text('None')),
                    DropdownMenuItem(value: 'Mild (CrCl 60-89 ml/min)', child: Text('Mild')),
                    DropdownMenuItem(value: 'Moderate (CrCl 30-59 ml/min)', child: Text('Moderate')),
                    DropdownMenuItem(value: 'Severe (CrCl < 30 ml/min)', child: Text('Severe')),
                  ],
                  onChanged: (v) => setState(() => _renalImpairment = v!),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _hepaticImpairment,
                  decoration: const InputDecoration(labelText: 'Hepatic Impairment', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'None', child: Text('None')),
                    DropdownMenuItem(value: 'Mild (Child-Pugh A)', child: Text('Mild')),
                    DropdownMenuItem(value: 'Moderate (Child-Pugh B)', child: Text('Moderate')),
                    DropdownMenuItem(value: 'Severe (Child-Pugh C)', child: Text('Severe')),
                  ],
                  onChanged: (v) => setState(() => _hepaticImpairment = v!),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _allergiesController,
                  decoration: const InputDecoration(labelText: 'Known Drug Allergies', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _chronicController,
                  decoration: const InputDecoration(labelText: 'Chronic Diseases / Active Regimens', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _review,
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_isLoading ? 'Pharmacist is reviewing…' : 'Review Pharmacotherapy Suggestion'),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: AppSpacing.lg),
          if (_result!.urgentAssessmentRequired)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_rounded, color: Colors.white),
                      SizedBox(width: AppSpacing.sm),
                      Text('Urgent Medical Assessment Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_result!.urgentAssessmentRationale, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          if (_result!.warningBanner.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _result!.warningBanner,
                      style: AppTextStyles.body.copyWith(color: isDark ? Colors.white : AppColors.slate900),
                    ),
                  ),
                ],
              ),
            ),
          Text('SUGGESTIONS (${_result!.recommendations.length})', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < _result!.recommendations.length; i++)
            MedicationCard(
              medication: _result!.recommendations[i],
              isFavorite: widget.isFavorite(_result!.recommendations[i]),
              onToggleFavorite: () => setState(() => widget.onToggleFavorite(_result!.recommendations[i])),
              initiallyExpanded: i == 0,
            ),
        ],
      ],
    );
  }
}

class _InteractionsTab extends ConsumerStatefulWidget {
  const _InteractionsTab();

  @override
  ConsumerState<_InteractionsTab> createState() => _InteractionsTabState();
}

class _InteractionsTabState extends ConsumerState<_InteractionsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _drugAController = TextEditingController();
  final _drugBController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  InteractionResult? _result;

  @override
  void dispose() {
    _drugAController.dispose();
    _drugBController.dispose();
    super.dispose();
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'major':
        return AppColors.danger;
      case 'moderate':
        return AppColors.warning;
      case 'minor':
        return AppColors.success;
      default:
        return AppColors.slate500;
    }
  }

  Future<void> _check() async {
    if (_drugAController.text.trim().isEmpty || _drugBController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(pharmacyApiProvider)
          .checkInteractions(drugA: _drugAController.text.trim(), drugB: _drugBController.text.trim());
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        showUsageLimitDialog(context);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Drug-Drug Interaction Checker', style: AppTextStyles.title),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _drugAController,
          decoration: const InputDecoration(labelText: 'Medication A', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _drugBController,
          decoration: const InputDecoration(labelText: 'Medication B', border: OutlineInputBorder()),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _check,
            child: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Check Interaction'),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _severityColor(_result!.severity).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_result!.severity} severity',
                      style: AppTextStyles.caption.copyWith(color: _severityColor(_result!.severity), fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Mechanism', style: AppTextStyles.bodyStrong),
                  Text(
                    _result!.mechanism,
                    style: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate200 : AppColors.slate700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Management', style: AppTextStyles.bodyStrong),
                  Text(
                    _result!.management,
                    style: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate200 : AppColors.slate700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Clinical Tip', style: AppTextStyles.bodyStrong),
                  Text(
                    _result!.clinicalTip,
                    style: AppTextStyles.body.copyWith(color: isDark ? AppColors.slate200 : AppColors.slate700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubstitutionTab extends ConsumerStatefulWidget {
  const _SubstitutionTab();

  @override
  ConsumerState<_SubstitutionTab> createState() => _SubstitutionTabState();
}

class _SubstitutionTabState extends ConsumerState<_SubstitutionTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _targetController = TextEditingController();
  String _country = 'Pakistan';
  bool _isLoading = false;
  String? _error;
  List<Substitute>? _results;

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_targetController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await ref.read(pharmacyApiProvider).findSubstitutes(targetMed: _targetController.text.trim(), country: _country);
      if (!mounted) return;
      setState(() => _results = results);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        showUsageLimitDialog(context);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Therapeutic Substitution Finder', style: AppTextStyles.title),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _targetController,
          decoration: const InputDecoration(labelText: 'Target Medication', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _country,
          decoration: const InputDecoration(labelText: 'Country / Region', border: OutlineInputBorder()),
          items: [for (final c in _countries) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _country = v!),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _find,
            child: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Find Substitutes'),
          ),
        ),
        if (_results != null) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final sub in _results!)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(sub.genericName, style: AppTextStyles.bodyStrong)),
                        Text(sub.costTier, style: AppTextStyles.bodyStrong.copyWith(color: AppColors.success)),
                      ],
                    ),
                    Text(sub.drugClass, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Indication: ${sub.clinicalIndication}', style: AppTextStyles.caption),
                    const SizedBox(height: 2),
                    Text('Advantage: ${sub.therapeuticAdvantage}', style: AppTextStyles.caption),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({required this.favorites, required this.isLoading, required this.onToggleFavorite});

  final List<FavoriteDrug> favorites;
  final bool isLoading;
  final void Function(Medication) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (favorites.isEmpty) {
      return Center(
        child: Text('No favorites yet — save a recommendation to see it here.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final fav in favorites)
          MedicationCard(
            key: ValueKey(fav.id),
            medication: fav.medication,
            isFavorite: true,
            onToggleFavorite: () => onToggleFavorite(fav.medication),
          ),
      ],
    );
  }
}
