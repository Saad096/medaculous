import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/ai_analyzing_progress_bar.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../../settings/presentation/widgets/usage_limit_dialog.dart';
import '../../domain/symptom_check.dart';
import '../providers/symptoms_providers.dart';

const _quickSymptoms = [
  'Fever',
  'Headache',
  'Chest pain',
  'Shortness of breath',
  'Nausea',
  'Vomiting',
  'Fatigue',
  'Cough',
  'Abdominal pain',
  'Dizziness',
  'Palpitations',
  'Swelling',
  'Weight loss',
  'Night sweats',
  'Rash',
];

/// DISCOVERY_REPORT.md §2: preserve the legacy prompt/schema as-is — this is
/// a straight port of SymptomsDiagnoser.tsx's UX, backed by the FastAPI
/// /symptoms/check endpoint instead of a client-side Gemini call.
class SymptomCheckerScreen extends ConsumerStatefulWidget {
  const SymptomCheckerScreen({super.key});

  @override
  ConsumerState<SymptomCheckerScreen> createState() =>
      _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends ConsumerState<SymptomCheckerScreen>
    with SingleTickerProviderStateMixin {
  final _symptomController = TextEditingController();
  final _ageController = TextEditingController();
  final _durationController = TextEditingController();
  final _symptoms = <String>[];
  String? _sex;

  bool _isLoading = false;
  String? _error;
  SymptomCheckResult? _result;

  // Same fix as Drug Recommendations (owner feedback, 2026-09-11 there,
  // 2026-09-13 here): there's no real server-reported progress for a single
  // blocking AI call, so the bar fills against a time estimate but is
  // hard-capped below 100% until the real response is actually in hand —
  // never just because the estimated duration elapsed.
  static const _estimatedDuration = Duration(minutes: 10);
  static const _loadingCap = 0.92;
  bool _snapToComplete = false;
  late final AnimationController _progressController = AnimationController(
    vsync: this,
    duration: _estimatedDuration,
  );
  late final Animation<double> _rawProgress = CurvedAnimation(
    parent: _progressController,
    curve: Curves.easeOutQuart,
  );
  double get _cappedProgress =>
      _snapToComplete ? _rawProgress.value : _rawProgress.value.clamp(0.0, _loadingCap);

  // Same scroll UX as Drug Recommendations: jump to where the response
  // starts once it lands, and offer a floating "scroll to bottom" button.
  final _scrollController = ScrollController();
  final _resultsStartKey = GlobalKey();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollToBottomVisibility);
  }

  void _updateScrollToBottomVisibility() {
    if (!_scrollController.hasClients || _result == null) return;
    final position = _scrollController.position;
    final nearBottom = position.pixels >= position.maxScrollExtent - 24;
    if (nearBottom == _showScrollToBottom) {
      setState(() => _showScrollToBottom = !nearBottom);
    }
  }

  Future<void> _scrollToResultsStart() async {
    final resultsContext = _resultsStartKey.currentContext;
    if (resultsContext == null) return;
    await Scrollable.ensureVisible(
      resultsContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      alignment: 0,
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _symptomController.dispose();
    _ageController.dispose();
    _durationController.dispose();
    _progressController.dispose();
    _scrollController.dispose();
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

  void _removeSymptom(String symptom) =>
      setState(() => _symptoms.remove(symptom));

  Future<void> _analyze() async {
    if (_symptomController.text.trim().isNotEmpty) _addSymptom();
    if (_symptoms.isEmpty) {
      setState(() => _error = 'Please enter at least one symptom.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _snapToComplete = false;
      _showScrollToBottom = false;
    });
    _progressController.forward(from: 0);
    try {
      final result = await ref
          .read(symptomsApiProvider)
          .check(
            symptoms: _symptoms,
            age: _ageController.text.trim(),
            sex: _sex,
            duration: _durationController.text.trim(),
          );
      if (!mounted) return;
      // Only past this point is the bar allowed to actually show 100% —
      // it's known the real answer is in hand, not just that time passed.
      _snapToComplete = true;
      await _progressController.animateTo(1, duration: const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _result = result;
        _showScrollToBottom = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToResultsStart());
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        showUsageLimitDialog(context);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      _progressController.stop();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _symptoms.clear();
      _symptomController.clear();
      _ageController.clear();
      _durationController.clear();
      _sex = null;
      _error = null;
      _showScrollToBottom = false;
    });
  }

  Color _likelihoodColor(String likelihood) {
    switch (likelihood.toLowerCase()) {
      case 'high':
        return AppColors.danger;
      case 'moderate':
      case 'medium':
        return AppColors.warning;
      case 'low':
        return AppColors.success;
      default:
        return AppColors.slate500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavShell(
      current: AppNavTab.symptoms,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('AI Symptom Checker'),
        actions: [
          if (_result != null)
            TextButton(onPressed: _reset, child: const Text('New Check')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildForm(context),
                  if (_showScrollToBottom)
                    Positioned(
                      bottom: AppSpacing.md,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: FloatingActionButton.small(
                          heroTag: 'symptomCheckerScrollDown',
                          onPressed: _scrollToBottom,
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildAnalyzeFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'What symptoms are you experiencing?',
          style: AppTextStyles.title,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Add one or more symptoms below.',
          style: AppTextStyles.caption.copyWith(color: context.secondaryText),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _symptomController,
                onSubmitted: (_) => _addSymptom(),
                decoration: const InputDecoration(
                  hintText: 'e.g. chest pain, shortness of breath',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: () => _addSymptom(),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (_symptoms.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final symptom in _symptoms)
                Chip(
                  label: Text(symptom),
                  onDeleted: () => _removeSymptom(symptom),
                  shape: const StadiumBorder(),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'QUICK ADD',
          style: AppTextStyles.micro.copyWith(color: context.secondaryText),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final symptom in _quickSymptoms)
              ActionChip(
                label: Text(symptom),
                onPressed: () => _addSymptom(symptom),
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.slate800 : AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.slate700 : AppColors.slate200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PATIENT INFO (OPTIONAL)',
                style: AppTextStyles.micro.copyWith(
                  color: context.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      decoration: const InputDecoration(
                        labelText: 'Sex',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'Female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(
                          value: 'Other',
                          child: Text('Other'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _sex = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Duration (e.g. 3 days, 2 weeks)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: AppTextStyles.body.copyWith(color: AppColors.danger),
          ),
        ],
        if (_result != null) _buildResults(context, _result!),
      ],
    );
  }

  Widget _buildAnalyzeFooter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.slate700 : AppColors.slate200)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: _isLoading
              ? AiAnalyzingProgressBar(
                  animation: _progressController,
                  progressValue: () => _cappedProgress,
                  label: 'Analyzing symptoms…',
                )
              : FilledButton(
                  onPressed: _analyze,
                  child: const Text('Analyze Symptoms'),
                ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, SymptomCheckResult result) {
    // This tinted container sits directly on the (theme-following) page
    // background, not a fixed light card, so its text must flip with
    // brightness — `slate900` alone is invisible against the near-black
    // tinted background in dark mode.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(key: _resultsStartKey, height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.aiIndigo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white : AppColors.slate900,
              ),
              children: [
                const TextSpan(
                  text: 'Clinical Summary: ',
                  style: AppTextStyles.bodyStrong,
                ),
                TextSpan(text: result.clinicalSummary),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'DIFFERENTIAL DIAGNOSES (${result.diagnoses.length})',
          style: AppTextStyles.micro.copyWith(color: context.secondaryText),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < result.diagnoses.length; i++)
          _buildDiagnosisCard(i, result.diagnoses[i]),
      ],
    );
  }

  Widget _buildDiagnosisCard(int index, Diagnosis diagnosis) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text('${index + 1}', style: AppTextStyles.caption),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              diagnosis.condition,
                              style: AppTextStyles.bodyStrong,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _likelihoodColor(
                                diagnosis.likelihood,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              diagnosis.likelihood,
                              style: AppTextStyles.micro.copyWith(
                                color: _likelihoodColor(diagnosis.likelihood),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        diagnosis.explanation,
                        style: AppTextStyles.body.copyWith(
                          color: isDark ? AppColors.slate200 : AppColors.slate700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            _buildDetailRow(
              Icons.flag_rounded,
              AppColors.danger,
              'Red flags',
              diagnosis.redFlags,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildDetailRow(
              Icons.info_outline_rounded,
              AppColors.slate500,
              'Common causes',
              diagnosis.commonCauses,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildDetailRow(
              Icons.science_outlined,
              AppColors.primary,
              'Next steps',
              diagnosis.nextSteps,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    Color color,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.caption.copyWith(color: context.secondaryText),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
