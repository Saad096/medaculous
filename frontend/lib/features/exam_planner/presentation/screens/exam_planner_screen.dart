import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/exam_planner.dart';
import '../providers/exam_planner_providers.dart';
import '../widgets/focus_timer.dart';

const _prepLevels = ['beginner', 'intermediate', 'advanced'];
const _studyPreferences = ['one_specialty_per_day', 'mixed_specialties', 'randomized'];
const _goals = ['pass_comfortably', 'high_score', 'intensive_revision', 'last_minute'];
const _studyModes = ['standard', 'intensive', 'weekend', 'last_minute', 'flexible'];
const _weekdayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String _labelize(String snake) => snake.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

/// DISCOVERY_REPORT.md §10: personalized study-schedule generator. Matches
/// the feature PDF's tab set: Today (study plan), Weekly and Monthly
/// timetables, Progress (analytics and readiness), Notes (per-topic notes,
/// checklists, and bookmarks), Syllabus (editable blueprint: add specialties
/// and topics, regenerate the schedule), and Settings — plus the focus/
/// Pomodoro timer in the app bar.
class ExamPlannerScreen extends ConsumerStatefulWidget {
  const ExamPlannerScreen({super.key});

  @override
  ConsumerState<ExamPlannerScreen> createState() => _ExamPlannerScreenState();
}

class _ExamPlannerScreenState extends ConsumerState<ExamPlannerScreen> {
  ExamSetup? _setup;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final setup = await ref.read(examPlannerApiProvider).getSetup();
    if (!mounted) return;
    setState(() {
      _setup = setup;
      _isInitialLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_setup == null) {
      return _ExamPickerScreen(onSetupCreated: _load);
    }
    return _PlannerTabs(setup: _setup!, onSetupChanged: _load);
  }
}

class _ExamPickerScreen extends ConsumerStatefulWidget {
  const _ExamPickerScreen({required this.onSetupCreated});

  final Future<void> Function() onSetupCreated;

  @override
  ConsumerState<_ExamPickerScreen> createState() => _ExamPickerScreenState();
}

class _ExamPickerScreenState extends ConsumerState<_ExamPickerScreen> {
  List<ExamInfo> _exams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    ref.read(examPlannerApiProvider).listExams().then((exams) {
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Planner')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text('Choose your exam', style: AppTextStyles.headline),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Get a personalized study schedule with spaced-repetition revisions.',
                  style: AppTextStyles.body.copyWith(color: context.secondaryText),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final exam in _exams)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      title: Text(exam.name, style: AppTextStyles.bodyStrong),
                      subtitle: Text(exam.region, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _SetupWizardScreen(exam: exam, onSetupCreated: widget.onSetupCreated),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

const _prepLevelInfo = {
  'beginner': ('Beginner', 'New to this exam — start from the fundamentals.'),
  'intermediate': ('Intermediate', 'Comfortable with the basics, building toward exam readiness.'),
  'advanced': ('Advanced', 'Strong foundation — focused on refinement and high-yield gaps.'),
};

const _studyPreferenceInfo = {
  'one_specialty_per_day': ('One Specialty Per Day', 'Deep-focus on a single specialty each study day.'),
  'mixed_specialties': ('Mixed Specialties', 'Rotate across specialties within the same day.'),
  'randomized': ('Randomized', 'Shuffle topics for interleaved, exam-like recall practice.'),
};

const _goalInfo = {
  'pass_comfortably': ('Pass Comfortably', 'A balanced pace with buffer before the exam.'),
  'high_score': ('High Score', 'A more thorough pace aimed at a top result.'),
  'intensive_revision': ('Intensive Revision', 'Heavier daily load to cover more ground quickly.'),
  'last_minute': ('Last-Minute', 'Compressed, high-yield-first plan for a near exam date.'),
};

const _studyModeInfo = {
  'standard': ('Standard', 'Even pacing across all available study days.'),
  'intensive': ('Intensive', 'Longer daily sessions, faster syllabus coverage.'),
  'weekend': ('Weekend-Heavy', 'Lighter weekdays, longer weekend sessions.'),
  'last_minute': ('Last-Minute', 'Cram-style scheduling prioritising high-yield topics.'),
  'flexible': ('Flexible', 'Adapts day-to-day based on completed sessions.'),
};

const _dailyMinutePresets = [30, 60, 90, 120, 180];

class _SetupWizardScreen extends ConsumerStatefulWidget {
  const _SetupWizardScreen({required this.exam, required this.onSetupCreated});

  final ExamInfo exam;
  final Future<void> Function() onSetupCreated;

  @override
  ConsumerState<_SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<_SetupWizardScreen> {
  final _pageController = PageController();
  int _step = 0;
  static const _totalSteps = 3;

  final DateTime _startDate = DateTime.now();
  late DateTime _targetDate = DateTime.now().add(Duration(days: widget.exam.defaultPrepWeeks * 7));
  String _prepLevel = 'intermediate';
  int _dailyMinutes = 60;
  final Set<int> _availableDays = {1, 2, 3, 4, 5};
  String _studyPreference = 'one_specialty_per_day';
  String _goal = 'pass_comfortably';
  String _studyMode = 'standard';
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() => _targetDate = picked);
  }

  void _goNext() {
    if (_step == 1 && _availableDays.isEmpty) {
      setState(() => _error = 'Select at least one available study day.');
      return;
    }
    setState(() => _error = null);
    if (_step < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _submit();
    }
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(examPlannerApiProvider).createSetup(
            examId: widget.exam.id,
            targetExamDate: _targetDate,
            startDate: _startDate,
            prepLevel: _prepLevel,
            dailyStudyMinutes: _dailyMinutes,
            availableDaysPerWeek: _availableDays.toList()..sort(),
            studyPreference: _studyPreference,
            goal: _goal,
            studyMode: _studyMode,
          );
      await widget.onSetupCreated();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _stepTitles = ['Exam Date & Preparation', 'Daily Study Time & Days', 'Study Preference & Planning Mode'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _goBack),
        title: Text(widget.exam.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${_step + 1} of $_totalSteps',
                      style: AppTextStyles.micro.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700),
                    ),
                    Text(_stepTitles[_step], style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _totalSteps,
                    minHeight: 6,
                    backgroundColor: isDark ? AppColors.slate800 : AppColors.slate200,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                _buildDateAndPrepStep(),
                _buildTimeAndDaysStep(),
                _buildPreferenceStep(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                if (_error != null) ...[
                  Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
                  const SizedBox(height: AppSpacing.md),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _goNext,
                    child: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_step == _totalSteps - 1 ? 'Generate My Schedule' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndPrepStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Text('When is your exam?', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your study plan is paced backwards from this date.',
          style: AppTextStyles.body.copyWith(color: context.secondaryText),
        ),
        const SizedBox(height: AppSpacing.lg),
        InkWell(
          onTap: _pickTargetDate,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: _StepCard(
            child: Row(
              children: [
                const Icon(Icons.event_rounded, color: AppColors.examPlannerIcon, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target Exam Date', style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                      Text(_fmt(_targetDate), style: AppTextStyles.title),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Preparation Level', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        for (final level in _prepLevels)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SelectableCard(
              title: _prepLevelInfo[level]!.$1,
              description: _prepLevelInfo[level]!.$2,
              selected: _prepLevel == level,
              onTap: () => setState(() => _prepLevel = level),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeAndDaysStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Text('How much time can you study?', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'We\'ll fit your syllabus into the days and minutes you set.',
          style: AppTextStyles.body.copyWith(color: context.secondaryText),
        ),
        const SizedBox(height: AppSpacing.lg),
        _StepCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Daily Study Time', style: AppTextStyles.bodyStrong),
                  Text('$_dailyMinutes min', style: AppTextStyles.title.copyWith(color: AppColors.examPlannerIcon)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final preset in _dailyMinutePresets)
                    ChoiceChip(
                      label: Text('$preset min'),
                      selected: _dailyMinutes == preset,
                      onSelected: (_) => setState(() => _dailyMinutes = preset),
                    ),
                ],
              ),
              Slider(
                value: _dailyMinutes.toDouble(),
                min: 15,
                max: 300,
                divisions: 19,
                label: '$_dailyMinutes min',
                onChanged: (v) => setState(() => _dailyMinutes = v.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Available Days', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var day = 0; day < 7; day++)
              _DayToggle(
                label: _weekdayLabels[day],
                selected: _availableDays.contains(day),
                onTap: () => setState(() {
                  if (_availableDays.contains(day)) {
                    _availableDays.remove(day);
                  } else {
                    _availableDays.add(day);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreferenceStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Text('How do you want to study?', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.lg),
        Text('Study Preference', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        for (final pref in _studyPreferences)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SelectableCard(
              title: _studyPreferenceInfo[pref]!.$1,
              description: _studyPreferenceInfo[pref]!.$2,
              selected: _studyPreference == pref,
              onTap: () => setState(() => _studyPreference = pref),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text('Goal', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        for (final goal in _goals)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SelectableCard(
              title: _goalInfo[goal]!.$1,
              description: _goalInfo[goal]!.$2,
              selected: _goal == goal,
              onTap: () => setState(() => _goal = goal),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text('Planning Mode', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        for (final mode in _studyModes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SelectableCard(
              title: _studyModeInfo[mode]!.$1,
              description: _studyModeInfo[mode]!.$2,
              selected: _studyMode == mode,
              onTap: () => setState(() => _studyMode = mode),
            ),
          ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.examPlannerIcon.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark ? AppColors.slate800 : Colors.white),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: selected ? AppColors.examPlannerIcon : (isDark ? AppColors.slate700 : AppColors.slate200),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyStrong),
                  const SizedBox(height: 2),
                  Text(description, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.examPlannerIcon : context.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.examPlannerIcon : (isDark ? AppColors.slate800 : AppColors.slate100),
          border: selected ? null : Border.all(color: isDark ? AppColors.slate700 : AppColors.slate200),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? Colors.white : context.secondaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlannerTabs extends StatelessWidget {
  const _PlannerTabs({required this.setup, required this.onSetupChanged});

  final ExamSetup setup;
  final Future<void> Function() onSetupChanged;

  void _openFocusTimer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: const FocusTimer(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exam Planner'),
          actions: [
            IconButton(
              icon: const Icon(Icons.timer_outlined),
              tooltip: 'Focus Timer',
              onPressed: () => _openFocusTimer(context),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'Weekly'),
              Tab(text: 'Monthly'),
              Tab(text: 'Progress'),
              Tab(text: 'Notes'),
              Tab(text: 'Syllabus'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _DailyTab(),
            const _WeeklyTab(),
            _MonthlyTab(setup: setup),
            const _ProgressTab(),
            const _NotesTab(),
            const _SyllabusTab(),
            _SettingsTab(setup: setup, onSetupChanged: onSetupChanged),
          ],
        ),
      ),
    );
  }
}

class _DailyTab extends ConsumerStatefulWidget {
  const _DailyTab();

  @override
  ConsumerState<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends ConsumerState<_DailyTab> {
  List<ExamSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await ref.read(examPlannerApiProvider).getTodaySchedule();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _showConfidenceDialog(ExamSession session) async {
    var confidence = 3;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('How confident do you feel?'),
          content: Slider(
            value: confidence.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$confidence',
            onChanged: (v) => setDialogState(() => confidence = v.round()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Skip')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Mark Complete')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(examPlannerApiProvider).updateSession(
          session.id,
          status: 'completed',
          actualMinutesSpent: session.estimatedMinutes,
          confidenceRating: confidence,
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_sessions.isEmpty) {
      return Center(child: Text('No sessions scheduled for today.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final s = _sessions[index];
          final isDone = s.status == 'completed';
          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Icon(
                s.type == 'revision' ? Icons.refresh_rounded : Icons.menu_book_rounded,
                color: s.type == 'revision' ? AppColors.aiPurple : AppColors.primary,
              ),
              title: Text(
                s.topicTitle,
                style: AppTextStyles.bodyStrong.copyWith(decoration: isDone ? TextDecoration.lineThrough : null),
              ),
              subtitle: Text(
                '${s.specialtyTitle} · ${s.estimatedMinutes} min${s.type == "revision" ? " · Revision #${s.revisionIteration}" : ""}',
                style: AppTextStyles.caption.copyWith(color: context.secondaryText),
              ),
              trailing: isDone
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                  : IconButton(
                      icon: const Icon(Icons.radio_button_unchecked_rounded),
                      onPressed: () => _showConfidenceDialog(s),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Weekly timetable (feature PDF: "Weekly and Monthly timetables are
/// shown") — 7 day cards for the selected week with per-day sessions,
/// completion counters, and total study minutes.
class _WeeklyTab extends ConsumerStatefulWidget {
  const _WeeklyTab();

  @override
  ConsumerState<_WeeklyTab> createState() => _WeeklyTabState();
}

class _WeeklyTabState extends ConsumerState<_WeeklyTab> {
  int _weekOffset = 0;
  List<ExamSession> _sessions = [];
  bool _isLoading = true;

  DateTime get _weekStart {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: _weekOffset * 7));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final start = _weekStart;
    final sessions = await ref
        .read(examPlannerApiProvider)
        .getSchedule(start: start, end: start.add(const Duration(days: 6)));
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  void _changeWeek(int delta) {
    setState(() => _weekOffset += delta);
    _load();
  }

  Future<void> _completeSession(ExamSession session) async {
    var confidence = 3;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('How confident do you feel?'),
          content: Slider(
            value: confidence.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$confidence',
            onChanged: (v) => setDialogState(() => confidence = v.round()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Mark Complete')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(examPlannerApiProvider).updateSession(
          session.id,
          status: 'completed',
          actualMinutesSpent: session.estimatedMinutes,
          confidenceRating: confidence,
        );
    await _load();
  }

  String _fmtShort(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final start = _weekStart;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _changeWeek(-1),
              ),
              FilledButton.tonal(
                onPressed: _weekOffset == 0
                    ? null
                    : () {
                        setState(() => _weekOffset = 0);
                        _load();
                      },
                child: Text(
                  _weekOffset == 0
                      ? 'This Week'
                      : 'Week of ${_fmtShort(start)} to ${_fmtShort(start.add(const Duration(days: 6)))}',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _changeWeek(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final day = start.add(Duration(days: index));
                      final isToday = day == todayDate;
                      final daySessions = _sessions
                          .where((s) =>
                              s.date.year == day.year &&
                              s.date.month == day.month &&
                              s.date.day == day.day)
                          .toList();
                      final done = daySessions.where((s) => s.status == 'completed').length;
                      final totalMinutes =
                          daySessions.fold<int>(0, (sum, s) => sum + s.estimatedMinutes);
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        shape: isToday
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: AppColors.primary, width: 1.5),
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${dayNames[index]} ${day.day}',
                                    style: AppTextStyles.bodyStrong.copyWith(
                                      color: isToday ? AppColors.primary : null,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isToday)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        'TODAY',
                                        style: AppTextStyles.micro.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  if (daySessions.isNotEmpty) ...[
                                    const SizedBox(width: AppSpacing.sm),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: done == daySessions.length
                                            ? AppColors.success.withValues(alpha: 0.15)
                                            : AppColors.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '$done/${daySessions.length}',
                                        style: AppTextStyles.micro.copyWith(
                                          color: done == daySessions.length
                                              ? AppColors.success
                                              : AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (daySessions.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                                  child: Text(
                                    'Rest day',
                                    style: AppTextStyles.caption.copyWith(color: AppColors.slate400),
                                  ),
                                )
                              else ...[
                                const SizedBox(height: AppSpacing.sm),
                                for (final s in daySessions)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: s.status == 'completed' ? null : () => _completeSession(s),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                          vertical: AppSpacing.xs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.slate800
                                              : AppColors.slate50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isDark ? AppColors.slate700 : AppColors.slate200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              s.status == 'completed'
                                                  ? Icons.check_circle_rounded
                                                  : (s.type == 'revision'
                                                      ? Icons.refresh_rounded
                                                      : Icons.menu_book_rounded),
                                              size: 16,
                                              color: s.status == 'completed'
                                                  ? AppColors.success
                                                  : (s.type == 'revision'
                                                      ? AppColors.aiPurple
                                                      : AppColors.primary),
                                            ),
                                            const SizedBox(width: AppSpacing.sm),
                                            Expanded(
                                              child: Text(
                                                s.topicTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTextStyles.caption.copyWith(
                                                  decoration: s.status == 'completed'
                                                      ? TextDecoration.lineThrough
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${s.estimatedMinutes}m',
                                              style: AppTextStyles.micro.copyWith(
                                                color: context.secondaryText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                Text(
                                  '$totalMinutes mins total',
                                  style: AppTextStyles.micro.copyWith(color: context.secondaryText),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Monthly calendar timetable with per-day topic counts and a day detail
/// sheet. Shows the target exam date alongside month navigation.
class _MonthlyTab extends ConsumerStatefulWidget {
  const _MonthlyTab({required this.setup});

  final ExamSetup setup;

  @override
  ConsumerState<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends ConsumerState<_MonthlyTab> {
  int _monthOffset = 0;
  List<ExamSession> _sessions = [];
  bool _isLoading = true;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  DateTime get _monthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final start = _monthStart;
    final end = DateTime(start.year, start.month + 1, 0);
    final sessions = await ref.read(examPlannerApiProvider).getSchedule(start: start, end: end);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() => _monthOffset += delta);
    _load();
  }

  void _showDay(DateTime day, List<ExamSession> daySessions) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            Text(
              '${day.day} ${_monthNames[day.month - 1]} ${day.year}',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final s in daySessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s.status == 'completed'
                      ? Icons.check_circle_rounded
                      : (s.type == 'revision' ? Icons.refresh_rounded : Icons.menu_book_rounded),
                  color: s.status == 'completed'
                      ? AppColors.success
                      : (s.type == 'revision' ? AppColors.aiPurple : AppColors.primary),
                ),
                title: Text(s.topicTitle, style: AppTextStyles.body),
                subtitle: Text(
                  '${s.specialtyTitle} · ${s.estimatedMinutes} min',
                  style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final start = _monthStart;
    final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
    final leadingBlanks = start.weekday - 1; // Monday-first grid
    final today = DateTime.now();
    final target = widget.setup.targetExamDate;

    final sessionsByDay = <int, List<ExamSession>>{};
    for (final s in _sessions) {
      sessionsByDay.putIfAbsent(s.date.day, () => []).add(s);
    }

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      Text(
                        '${_monthNames[start.month - 1]} ${start.year}',
                        style: AppTextStyles.headline,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target exam date: ${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}',
                        style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: () => _changeMonth(-1),
                          ),
                          FilledButton.tonal(
                            onPressed: _monthOffset == 0
                                ? null
                                : () {
                                    setState(() => _monthOffset = 0);
                                    _load();
                                  },
                            child: const Text('Current Month'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            onPressed: () => _changeMonth(1),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final label in const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])
                            Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  style: AppTextStyles.micro.copyWith(color: context.secondaryText),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: leadingBlanks + daysInMonth,
                        itemBuilder: (context, index) {
                          if (index < leadingBlanks) return const SizedBox.shrink();
                          final dayNum = index - leadingBlanks + 1;
                          final day = DateTime(start.year, start.month, dayNum);
                          final daySessions = sessionsByDay[dayNum] ?? const <ExamSession>[];
                          final isToday = day.year == today.year &&
                              day.month == today.month &&
                              day.day == today.day;
                          final isExamDay = day.year == target.year &&
                              day.month == target.month &&
                              day.day == target.day;
                          final allDone = daySessions.isNotEmpty &&
                              daySessions.every((s) => s.status == 'completed');
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: daySessions.isEmpty ? null : () => _showDay(day, daySessions),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: isExamDay
                                    ? AppColors.danger.withValues(alpha: 0.1)
                                    : daySessions.isNotEmpty
                                        ? (allDone
                                            ? AppColors.success.withValues(alpha: 0.1)
                                            : AppColors.primary.withValues(alpha: 0.08))
                                        : null,
                                border: Border.all(
                                  color: isToday
                                      ? AppColors.primary
                                      : isExamDay
                                          ? AppColors.danger
                                          : (isDark ? AppColors.slate700 : AppColors.slate200),
                                  width: isToday || isExamDay ? 1.5 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: AppTextStyles.caption.copyWith(
                                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                                      color: isToday ? AppColors.primary : null,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isExamDay)
                                    Text(
                                      'EXAM',
                                      style: AppTextStyles.micro.copyWith(
                                        fontSize: 8,
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  else if (daySessions.isNotEmpty) ...[
                                    Text(
                                      '${daySessions.length}',
                                      style: AppTextStyles.micro.copyWith(
                                        color: allDone ? AppColors.success : AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      daySessions.length == 1 ? 'topic' : 'topics',
                                      style: AppTextStyles.micro.copyWith(
                                        fontSize: 8,
                                        color: allDone ? AppColors.success : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
  }
}

class _SyllabusTab extends ConsumerStatefulWidget {
  const _SyllabusTab();

  @override
  ConsumerState<_SyllabusTab> createState() => _SyllabusTabState();
}

class _SyllabusTabState extends ConsumerState<_SyllabusTab> {
  List<Specialty> _specialties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final specialties = await ref.read(examPlannerApiProvider).getSpecialties();
    if (!mounted) return;
    setState(() {
      _specialties = specialties;
      _isLoading = false;
    });
  }

  Future<void> _openTopic(Topic topic) async {
    final updated = await showModalBottomSheet<Topic>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TopicNotesSheet(topic: topic),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _specialties = [
        for (final sp in _specialties)
          Specialty(
            id: sp.id,
            key: sp.key,
            title: sp.title,
            description: sp.description,
            icon: sp.icon,
            topics: [for (final t in sp.topics) t.id == updated.id ? updated : t],
          ),
      ];
    });
  }

  Future<void> _addSpecialty() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add specialty'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Clinical Pharmacology',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(examPlannerApiProvider).createSpecialty(title);
    await _load();
  }

  Future<void> _addTopic(Specialty specialty) async {
    final titleController = TextEditingController();
    var minutes = 45;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add topic to ${specialty.title}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Topic title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text('Duration: $minutes min', style: AppTextStyles.body),
                  Expanded(
                    child: Slider(
                      value: minutes.toDouble(),
                      min: 15,
                      max: 180,
                      divisions: 11,
                      onChanged: (v) => setDialogState(() => minutes = v.round()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add Topic')),
          ],
        ),
      ),
    );
    final title = titleController.text.trim();
    if (confirmed != true || title.isEmpty) return;
    await ref.read(examPlannerApiProvider).createTopic(
          specialty.id,
          title: title,
          estimatedMinutes: minutes,
        );
    await _load();
    if (!mounted) return;
    showAppToast(
      context,
      'Topic added. Use "Regenerate Schedule" to plan study days for it.',
    );
  }

  Future<void> _deleteTopic(Topic topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete topic'),
        content: Text(
          'Remove "${topic.title}" and its scheduled sessions from the plan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(examPlannerApiProvider).deleteTopic(topic.id);
    await _load();
  }

  Future<void> _regenerateSchedule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate schedule'),
        content: const Text(
          'Rebuilds all pending study days from today for every topic not yet completed. Completed sessions and progress are kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Regenerate')),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await ref.read(examPlannerApiProvider).regenerateSchedule();
    if (!mounted) return;
    showAppToast(context, 'Schedule regenerated: $count sessions planned.');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addSpecialty,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Specialty'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _regenerateSchedule,
                  icon: const Icon(Icons.event_repeat_rounded, size: 18),
                  label: const Text('Regenerate'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_specialties.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: Center(
                child: Text('No syllabus yet.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)),
              ),
            ),
          for (final sp in _specialties)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ExpansionTile(
                title: Text(sp.title, style: AppTextStyles.bodyStrong),
                subtitle: Text(
                  '${sp.topics.where((t) => t.isCompleted).length} of ${sp.topics.length} topics completed',
                  style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                ),
                children: [
                  for (final topic in sp.topics)
                    ListTile(
                      leading: Icon(
                        topic.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: topic.isCompleted ? AppColors.success : AppColors.slate400,
                      ),
                      title: Text(topic.title, style: AppTextStyles.body),
                      subtitle: Text(
                        '${topic.estimatedMinutes} min · ${_labelize(topic.difficulty)}'
                        '${topic.notes.isNotEmpty ? " · has notes" : ""}',
                        style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        color: AppColors.slate400,
                        tooltip: 'Delete topic',
                        onPressed: () => _deleteTopic(topic),
                      ),
                      onTap: () => _openTopic(topic),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add_rounded, color: AppColors.primary),
                    title: Text(
                      'Add topic',
                      style: AppTextStyles.body.copyWith(color: AppColors.primary),
                    ),
                    onTap: () => _addTopic(sp),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Lightweight per-topic detail surface — the app has no dedicated topic
/// detail screen yet, so notes are edited from a bottom sheet opened from
/// the syllabus list rather than a full-screen redesign.
class _TopicNotesSheet extends ConsumerStatefulWidget {
  const _TopicNotesSheet({required this.topic});

  final Topic topic;

  @override
  ConsumerState<_TopicNotesSheet> createState() => _TopicNotesSheetState();
}

class _TopicNotesSheetState extends ConsumerState<_TopicNotesSheet> {
  late final TextEditingController _notesController;
  late final TextEditingController _checklistController;
  late Topic _topic;
  Timer? _debounce;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _topic = widget.topic;
    _notesController = TextEditingController(text: _topic.notes);
    _checklistController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _notesController.dispose();
    _checklistController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final updated = await ref.read(examPlannerApiProvider).updateTopicNotes(_topic.id, _notesController.text);
    if (!mounted) return;
    setState(() {
      _topic = updated;
      _isSaving = false;
    });
  }

  Future<void> _saveChecklists(List<ChecklistItem> items) async {
    setState(() => _isSaving = true);
    final updated = await ref
        .read(examPlannerApiProvider)
        .updateTopicMeta(_topic.id, checklists: items);
    if (!mounted) return;
    setState(() {
      _topic = updated;
      _isSaving = false;
    });
  }

  void _addChecklistItem() {
    final text = _checklistController.text.trim();
    if (text.isEmpty) return;
    _checklistController.clear();
    _saveChecklists([
      ..._topic.checklists,
      ChecklistItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        done: false,
      ),
    ]);
  }

  Future<void> _handleClose() async {
    _debounce?.cancel();
    await _save();
    if (mounted) Navigator.of(context).pop(_topic);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose();
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_topic.title, style: AppTextStyles.title)),
                  if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.only(right: AppSpacing.sm),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: _handleClose),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Notes', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _notesController,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add your personal notes for this topic…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _scheduleSave(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Checklist', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
              for (final item in _topic.checklists)
                Row(
                  children: [
                    Checkbox(
                      value: item.done,
                      onChanged: (v) => _saveChecklists([
                        for (final c in _topic.checklists)
                          c.id == item.id ? c.copyWith(done: v ?? false) : c,
                      ]),
                    ),
                    Expanded(
                      child: Text(
                        item.text,
                        style: AppTextStyles.body.copyWith(
                          decoration: item.done ? TextDecoration.lineThrough : null,
                          color: item.done ? AppColors.slate400 : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.slate400,
                      onPressed: () => _saveChecklists([
                        for (final c in _topic.checklists)
                          if (c.id != item.id) c,
                      ]),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checklistController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add checklist item…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addChecklistItem(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonal(
                    onPressed: _addChecklistItem,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Study analytics and readiness (feature PDF: "Study Progress") —
/// readiness score, streaks, per-specialty syllabus progress bars, and a
/// topic difficulty distribution.
class _ProgressTab extends ConsumerStatefulWidget {
  const _ProgressTab();

  @override
  ConsumerState<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends ConsumerState<_ProgressTab> {
  PlannerStats? _stats;
  PlannerStreak? _streak;
  List<Specialty> _specialties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(examPlannerApiProvider);
    final results = await Future.wait([api.getStats(), api.getStreak(), api.getSpecialties()]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as PlannerStats?;
      _streak = results[1] as PlannerStreak?;
      _specialties = results[2] as List<Specialty>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final stats = _stats;
    if (stats == null) {
      return Center(child: Text('No stats yet.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)));
    }

    final allTopics = [for (final sp in _specialties) ...sp.topics];
    final easy = allTopics.where((t) => t.difficulty == 'easy').length;
    final moderate = allTopics.where((t) => t.difficulty == 'moderate').length;
    final difficult = allTopics.where((t) => t.difficulty == 'difficult' || t.difficulty == 'hard').length;
    final mastered = allTopics.where((t) => t.isCompleted && t.confidenceRating >= 4).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            color: AppColors.primary,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Text('Estimated Exam Readiness', style: AppTextStyles.micro.copyWith(color: Colors.white70)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${stats.readinessScore}%', style: AppTextStyles.display.copyWith(color: Colors.white)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Based on syllabus coverage, revisions, and study consistency.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Streak', value: '${_streak?.currentStreak ?? 0} days', icon: Icons.local_fire_department_rounded)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _StatCard(label: 'Longest', value: '${_streak?.longestStreak ?? 0} days', icon: Icons.emoji_events_rounded)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Syllabus', value: '${stats.syllabusProgressPct}%', icon: Icons.checklist_rounded)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _StatCard(label: 'Schedule', value: '${stats.scheduleProgressPct}%', icon: Icons.calendar_month_rounded)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatCard(
            label: 'Topics Completed',
            value: '${stats.completedTopicsCount} / ${stats.totalTopics}',
            icon: Icons.menu_book_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatCard(
            label: 'Sessions Completed',
            value: '${stats.completedSessions} / ${stats.totalSessions}',
            icon: Icons.event_available_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Syllabus Progress by Specialty', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  for (final sp in _specialties) ...[
                    _SpecialtyProgressRow(specialty: sp),
                    if (sp != _specialties.last) const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Topic Difficulty Distribution', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _DifficultyCard(label: 'Easy', count: easy, color: AppColors.success)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _DifficultyCard(label: 'Moderate', count: moderate, color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _DifficultyCard(label: 'Difficult', count: difficult, color: AppColors.danger)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _DifficultyCard(label: 'Mastered', count: mastered, color: AppColors.aiPurple)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpecialtyProgressRow extends StatelessWidget {
  const _SpecialtyProgressRow({required this.specialty});

  final Specialty specialty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = specialty.topics.length;
    final done = specialty.topics.where((t) => t.isCompleted).length;
    final pct = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(specialty.title, style: AppTextStyles.bodyStrong)),
            Text(
              '$done / $total topics (${(pct * 100).round()}%)',
              style: AppTextStyles.caption.copyWith(color: context.secondaryText),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: isDark ? AppColors.slate700 : AppColors.slate200,
            valueColor: AlwaysStoppedAnimation(
              pct >= 1 ? AppColors.success : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Text('$count', style: AppTextStyles.headline.copyWith(color: color)),
            Text('topics', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
          ],
        ),
      ),
    );
  }
}

/// Personal notes and bookmarks (feature PDF: "In the notes tab, notes can
/// be added to each topic with a checklist") — searchable topic cards with
/// notes, checklists, and a bookmarked-only filter.
class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab();

  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  List<Specialty> _specialties = [];
  bool _isLoading = true;
  String _query = '';
  bool _bookmarkedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final specialties = await ref.read(examPlannerApiProvider).getSpecialties();
    if (!mounted) return;
    setState(() {
      _specialties = specialties;
      _isLoading = false;
    });
  }

  void _replaceTopic(Topic updated) {
    setState(() {
      _specialties = [
        for (final sp in _specialties)
          Specialty(
            id: sp.id,
            key: sp.key,
            title: sp.title,
            description: sp.description,
            icon: sp.icon,
            topics: [for (final t in sp.topics) t.id == updated.id ? updated : t],
          ),
      ];
    });
  }

  Future<void> _toggleBookmark(Topic topic) async {
    final updated = await ref
        .read(examPlannerApiProvider)
        .updateTopicMeta(topic.id, isBookmarked: !topic.isBookmarked);
    if (mounted) _replaceTopic(updated);
  }

  Future<void> _openEditor(Topic topic) async {
    final updated = await showModalBottomSheet<Topic>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TopicNotesSheet(topic: topic),
    );
    if (updated != null && mounted) _replaceTopic(updated);
  }

  Future<void> _updateChecklists(Topic topic, List<ChecklistItem> items) async {
    final updated = await ref
        .read(examPlannerApiProvider)
        .updateTopicMeta(topic.id, checklists: items);
    if (mounted) _replaceTopic(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final query = _query.trim().toLowerCase();
    final entries = <(Specialty, Topic)>[];
    for (final sp in _specialties) {
      for (final t in sp.topics) {
        if (_bookmarkedOnly && !t.isBookmarked) continue;
        if (query.isNotEmpty &&
            !t.title.toLowerCase().contains(query) &&
            !sp.title.toLowerCase().contains(query) &&
            !t.notes.toLowerCase().contains(query)) {
          continue;
        }
        entries.add((sp, t));
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search topics, specialties, notes…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.slate700
                          : AppColors.slate200,
                    ),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  avatar: Icon(
                    _bookmarkedOnly ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 16,
                  ),
                  label: const Text('Bookmarked only'),
                  selected: _bookmarkedOnly,
                  onSelected: (v) => setState(() => _bookmarkedOnly = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _bookmarkedOnly ? 'No bookmarked topics yet.' : 'No topics match your search.',
                    style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final (sp, topic) = entries[index];
                      return _TopicNotesCard(
                        specialty: sp,
                        topic: topic,
                        onToggleBookmark: () => _toggleBookmark(topic),
                        onEdit: () => _openEditor(topic),
                        onChecklistsChanged: (items) => _updateChecklists(topic, items),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _TopicNotesCard extends StatefulWidget {
  const _TopicNotesCard({
    required this.specialty,
    required this.topic,
    required this.onToggleBookmark,
    required this.onEdit,
    required this.onChecklistsChanged,
  });

  final Specialty specialty;
  final Topic topic;
  final VoidCallback onToggleBookmark;
  final VoidCallback onEdit;
  final ValueChanged<List<ChecklistItem>> onChecklistsChanged;

  @override
  State<_TopicNotesCard> createState() => _TopicNotesCardState();
}

class _TopicNotesCardState extends State<_TopicNotesCard> {
  final _itemController = TextEditingController();

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _itemController.text.trim();
    if (text.isEmpty) return;
    _itemController.clear();
    widget.onChecklistsChanged([
      ...widget.topic.checklists,
      ChecklistItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        done: false,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.specialty.title,
                style: AppTextStyles.micro.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: Text(topic.title, style: AppTextStyles.bodyStrong)),
                IconButton(
                  icon: Icon(
                    topic.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: topic.isBookmarked ? AppColors.warning : AppColors.slate400,
                  ),
                  tooltip: topic.isBookmarked ? 'Remove bookmark' : 'Bookmark topic',
                  onPressed: widget.onToggleBookmark,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppColors.slate400,
                  tooltip: 'Edit notes',
                  onPressed: widget.onEdit,
                ),
              ],
            ),
            if (topic.notes.isNotEmpty) ...[
              Text(
                topic.notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(color: context.secondaryText),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (final item in topic.checklists)
              Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                      value: item.done,
                      onChanged: (v) => widget.onChecklistsChanged([
                        for (final c in topic.checklists)
                          c.id == item.id ? c.copyWith(done: v ?? false) : c,
                      ]),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.text,
                      style: AppTextStyles.body.copyWith(
                        decoration: item.done ? TextDecoration.lineThrough : null,
                        color: item.done ? AppColors.slate400 : null,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: AppColors.slate400,
                    onPressed: () => widget.onChecklistsChanged([
                      for (final c in topic.checklists)
                        if (c.id != item.id) c,
                    ]),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTextStyles.caption,
                    decoration: const InputDecoration(
                      hintText: 'Add checklist item…',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonal(
                  onPressed: _addItem,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: AppTextStyles.title),
            Text(label, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.setup, required this.onSetupChanged});

  final ExamSetup setup;
  final Future<void> Function() onSetupChanged;

  Future<void> _resetPlanner(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Planner'),
        content: const Text('This permanently deletes your current plan, schedule, progress, and streak. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(examPlannerApiProvider).deleteSetup();
    await onSetupChanged();
  }

  Future<void> _runCatchup(BuildContext context, WidgetRef ref) async {
    final count = await ref.read(examPlannerApiProvider).runCatchup();
    if (!context.mounted) return;
    showAppToast(
      context,
      count == 0
          ? 'No missed sessions to redistribute.'
          : 'Redistributed $count missed session(s).',
      kind: count == 0 ? AppToastKind.info : AppToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Plan', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
                const SizedBox(height: AppSpacing.xs),
                Text(setup.examId.toUpperCase(), style: AppTextStyles.bodyStrong),
                Text(
                  'Target: ${setup.targetExamDate.year}-${setup.targetExamDate.month.toString().padLeft(2, '0')}-${setup.targetExamDate.day.toString().padLeft(2, '0')}',
                  style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _runCatchup(context, ref),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Redistribute Missed Sessions'),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => _resetPlanner(context, ref),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Reset Planner'),
        ),
      ],
    );
  }
}
