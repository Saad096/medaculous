import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/copy_button.dart';
import '../../domain/ward.dart';
import '../providers/ward_providers.dart';

const _shiftTypes = ['Morning', 'Evening', 'Night', 'Weekend', 'On-call'];
const _priorities = ['Low', 'Medium', 'High'];

/// Plain-text handover formatted for messaging apps. WhatsApp renders
/// *text* as bold, so headings use asterisks — they degrade gracefully to
/// visible-but-harmless markers anywhere else.
String _formatHandover(Shift? shift, List<Patient> patients, List<WardTask> tasks) {
  if (patients.isEmpty) return 'No patient data available.';

  final now = DateTime.now();
  final date = (shift?.startedAt ?? now).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final totalOutstanding = tasks.where((t) => !t.completed).length;
  final highPriority = tasks.where((t) => !t.completed && t.priority.toLowerCase() == 'high').length;

  final buffer = StringBuffer()
    ..writeln('*WARD HANDOVER*')
    ..writeln('----------------------------------------');
  if (shift != null && shift.hospital.isNotEmpty) {
    buffer.writeln('Hospital: ${shift.hospital}');
  }
  buffer
    ..writeln('Ward: ${shift?.ward ?? "General"}  |  Specialty: ${shift?.specialty ?? "Unspecified"}')
    ..writeln('Shift: ${shift?.shiftType ?? "Unspecified"}')
    ..writeln('Date: ${two(date.day)}-${two(date.month)}-${date.year}  |  Prepared at ${two(now.hour)}:${two(now.minute)}')
    ..writeln('Patients: ${patients.length}  |  Outstanding tasks: $totalOutstanding${highPriority > 0 ? " ($highPriority high priority)" : ""}')
    ..writeln('----------------------------------------');

  for (var i = 0; i < patients.length; i++) {
    final p = patients[i];
    final outstanding = tasks.where((t) => t.patientId == p.id && !t.completed).toList()
      ..sort((a, b) => _priorityRank(a.priority).compareTo(_priorityRank(b.priority)));
    buffer
      ..writeln()
      ..writeln('*PATIENT ${i + 1} of ${patients.length}: ${p.initials}*')
      ..writeln('Age/Sex: ${p.age} years, ${p.sex}')
      ..writeln('Location: Room ${p.roomNumber}, Bed ${p.bedNumber}')
      ..writeln('Diagnosis: ${p.diagnosis.isEmpty ? "Not specified" : p.diagnosis}');
    if (p.coMorbids.isNotEmpty) buffer.writeln('Co-morbidities: ${p.coMorbids}');
    buffer.writeln('Resus status: ${p.dnar ? "DNAR (Do Not Attempt Resuscitation)" : "For CPR (full code)"}');
    if (outstanding.isEmpty) {
      buffer.writeln('Outstanding tasks: none');
    } else {
      buffer.writeln('Outstanding tasks (${outstanding.length}):');
      for (var j = 0; j < outstanding.length; j++) {
        final t = outstanding[j];
        buffer.writeln('  ${j + 1}. [${t.priority.toUpperCase()}] ${t.title}${t.note.isNotEmpty ? " (${t.note})" : ""}');
      }
    }
    if (p.notes.isNotEmpty) {
      buffer
        ..writeln('Clinical notes:')
        ..writeln('  ${p.notes.replaceAll('\n', '\n  ')}');
    }
    buffer.writeln('----------------------------------------');
  }

  buffer
    ..writeln()
    ..writeln('End of handover. Verify all details against the clinical record before acting.');
  return buffer.toString();
}

int _priorityRank(String priority) {
  switch (priority.toLowerCase()) {
    case 'high':
      return 0;
    case 'medium':
      return 1;
    default:
      return 2;
  }
}

/// DISCOVERY_REPORT.md §9: ward-round workspace, direct 1:1 port of
/// Shift/Patient/Task. Simplification vs. legacy: this screen gates on an
/// active shift existing before showing the tabs (legacy showed all 4 tabs
/// unconditionally even with no shift started) — a cleaner onboarding flow
/// for the same underlying data model.
class WardCompanionScreen extends ConsumerStatefulWidget {
  const WardCompanionScreen({super.key});

  @override
  ConsumerState<WardCompanionScreen> createState() => _WardCompanionScreenState();
}

class _WardCompanionScreenState extends ConsumerState<WardCompanionScreen> {
  Shift? _shift;
  List<Patient> _patients = [];
  List<WardTask> _tasks = [];
  // Only gates the very first fetch. Reloading after a CRUD action must NOT
  // flip this back to true — doing so swaps out the DefaultTabController
  // subtree entirely (this widget returns a bare spinner Scaffold while
  // true), which resets the selected tab back to Patients on every single
  // add/edit/delete anywhere in the screen.
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(wardApiProvider);
    final results = await Future.wait([api.getShift(), api.listPatients(), api.listTasks()]);
    if (!mounted) return;
    setState(() {
      _shift = results[0] as Shift?;
      _patients = results[1] as List<Patient>;
      _tasks = results[2] as List<WardTask>;
      _isInitialLoading = false;
    });
  }

  Future<void> _startShift({required String hospital, required String ward, required String specialty, required String shiftType}) async {
    await ref.read(wardApiProvider).startShift(hospital: hospital, ward: ward, specialty: specialty, shiftType: shiftType);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_shift == null) {
      return _StartShiftForm(onStart: _startShift);
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ward Companion'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Patients'), Tab(text: 'Tasks'), Tab(text: 'Handover'), Tab(text: 'Settings')],
          ),
        ),
        body: TabBarView(
          children: [
            _PatientsTab(patients: _patients, onReload: _load),
            _TasksTab(patients: _patients, tasks: _tasks, onReload: _load),
            _HandoverTab(shift: _shift, patients: _patients, tasks: _tasks),
            _SettingsTab(shift: _shift!, onReload: _load),
          ],
        ),
      ),
    );
  }
}

class _StartShiftForm extends StatefulWidget {
  const _StartShiftForm({required this.onStart});

  final Future<void> Function({required String hospital, required String ward, required String specialty, required String shiftType}) onStart;

  @override
  State<_StartShiftForm> createState() => _StartShiftFormState();
}

class _StartShiftFormState extends State<_StartShiftForm> {
  final _hospitalController = TextEditingController();
  final _wardController = TextEditingController();
  final _specialtyController = TextEditingController();
  String _shiftType = 'Morning';
  bool _isStarting = false;
  String? _error;

  @override
  void dispose() {
    _hospitalController.dispose();
    _wardController.dispose();
    _specialtyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_wardController.text.trim().isEmpty || _specialtyController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter both Ward and Specialty.');
      return;
    }
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      await widget.onStart(
        hospital: _hospitalController.text.trim(),
        ward: _wardController.text.trim(),
        specialty: _specialtyController.text.trim(),
        shiftType: _shiftType,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ward Companion')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Icon(Icons.local_hospital_outlined, size: 48, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text('Start a new shift', style: AppTextStyles.headline, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Track patients, tasks, and generate a handover summary for this ward round.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: context.secondaryText),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(controller: _hospitalController, decoration: const InputDecoration(labelText: 'Hospital (optional)', border: OutlineInputBorder())),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _wardController, decoration: const InputDecoration(labelText: 'Ward', border: OutlineInputBorder())),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _specialtyController, decoration: const InputDecoration(labelText: 'Specialty', border: OutlineInputBorder())),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _shiftType,
            decoration: const InputDecoration(labelText: 'Shift Type', border: OutlineInputBorder()),
            items: [for (final s in _shiftTypes) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _shiftType = v!),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _isStarting ? null : _submit,
            child: _isStarting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Start Shift'),
          ),
        ],
      ),
    );
  }
}

class _PatientsTab extends ConsumerWidget {
  const _PatientsTab({required this.patients, required this.onReload});

  final List<Patient> patients;
  final Future<void> Function() onReload;

  Future<void> _openPatientForm(BuildContext context, WidgetRef ref, [Patient? existing]) async {
    final initialsController = TextEditingController(text: existing?.initials ?? '');
    final ageController = TextEditingController(text: existing?.age ?? '');
    final roomController = TextEditingController(text: existing?.roomNumber ?? '');
    final bedController = TextEditingController(text: existing?.bedNumber ?? '');
    final diagnosisController = TextEditingController(text: existing?.diagnosis ?? '');
    final coMorbidsController = TextEditingController(text: existing?.coMorbids ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var sex = existing?.sex ?? 'Male';
    var dnar = existing?.dnar ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Patient' : 'Edit Patient'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: initialsController, decoration: const InputDecoration(labelText: 'Initials')),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: TextField(controller: ageController, decoration: const InputDecoration(labelText: 'Age'))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: sex,
                        decoration: const InputDecoration(labelText: 'Sex'),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) => setDialogState(() => sex = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: TextField(controller: roomController, decoration: const InputDecoration(labelText: 'Room'))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: TextField(controller: bedController, decoration: const InputDecoration(labelText: 'Bed'))),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: diagnosisController, decoration: const InputDecoration(labelText: 'Diagnosis')),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: coMorbidsController, decoration: const InputDecoration(labelText: 'Co-morbidities')),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: notesController, maxLines: 3, decoration: const InputDecoration(labelText: 'Clinical notes')),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('DNAR'),
                  value: dnar,
                  onChanged: (v) => setDialogState(() => dnar = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || initialsController.text.trim().isEmpty) return;

    final api = ref.read(wardApiProvider);
    if (existing == null) {
      await api.createPatient(
        initials: initialsController.text.trim(),
        age: ageController.text.trim(),
        sex: sex,
        roomNumber: roomController.text.trim(),
        bedNumber: bedController.text.trim(),
        diagnosis: diagnosisController.text.trim(),
        coMorbids: coMorbidsController.text.trim(),
        dnar: dnar,
        notes: notesController.text.trim(),
      );
    } else {
      await api.updatePatient(existing.id, {
        'initials': initialsController.text.trim(),
        'age': ageController.text.trim(),
        'sex': sex,
        'room_number': roomController.text.trim(),
        'bed_number': bedController.text.trim(),
        'diagnosis': diagnosisController.text.trim(),
        'co_morbids': coMorbidsController.text.trim(),
        'dnar': dnar,
        'notes': notesController.text.trim(),
      });
    }
    await onReload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openPatientForm(context, ref),
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: patients.isEmpty
          ? Center(child: Text('No patients yet — tap + to add one.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final p = patients[index];
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    color: AppColors.danger,
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await ref.read(wardApiProvider).deletePatient(p.id);
                    onReload();
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      onTap: () => _openPatientForm(context, ref, p),
                      leading: CircleAvatar(
                        backgroundColor: p.reviewed ? AppColors.success.withValues(alpha: 0.15) : AppColors.slate200,
                        child: Icon(
                          p.reviewed ? Icons.check_rounded : Icons.person_outline_rounded,
                          color: p.reviewed ? AppColors.success : AppColors.slate500,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(p.initials, style: AppTextStyles.bodyStrong),
                          if (p.dnar) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(4)),
                              child: const Text('DNAR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        'Rm ${p.roomNumber}/${p.bedNumber} · ${p.diagnosis.isEmpty ? "No diagnosis" : p.diagnosis}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          p.reviewed ? Icons.visibility_rounded : Icons.visibility_outlined,
                          color: p.reviewed ? AppColors.success : AppColors.slate400,
                        ),
                        tooltip: 'Mark reviewed',
                        onPressed: () async {
                          await ref.read(wardApiProvider).updatePatient(p.id, {'reviewed': !p.reviewed});
                          onReload();
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.patients, required this.tasks, required this.onReload});

  final List<Patient> patients;
  final List<WardTask> tasks;
  final Future<void> Function() onReload;

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    if (patients.isEmpty) {
      showAppToast(context, 'Add a patient first.', kind: AppToastKind.info);
      return;
    }
    final titleController = TextEditingController();
    var patientId = patients.first.id;
    var priority = 'Medium';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: patientId,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: [for (final p in patients) DropdownMenuItem(value: p.id, child: Text(p.initials))],
                onChanged: (v) => setDialogState(() => patientId = v!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Task')),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: [for (final p in _priorities) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: (v) => setDialogState(() => priority = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (created != true || titleController.text.trim().isEmpty) return;
    await ref.read(wardApiProvider).createTask(patientId: patientId, title: titleController.text.trim(), priority: priority);
    await onReload();
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return AppColors.danger;
      case 'Low':
        return AppColors.success;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientNames = {for (final p in patients) p.id: p.initials};
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _addTask(context, ref), child: const Icon(Icons.add_task_rounded)),
      body: tasks.isEmpty
          ? Center(child: Text('No tasks yet — tap + to add one.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final t = tasks[index];
                return Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    color: AppColors.danger,
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await ref.read(wardApiProvider).deleteTask(t.id);
                    onReload();
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: CheckboxListTile(
                      value: t.completed,
                      onChanged: (v) async {
                        await ref.read(wardApiProvider).updateTask(t.id, {'completed': v});
                        onReload();
                      },
                      title: Text(
                        t.title,
                        style: AppTextStyles.body.copyWith(decoration: t.completed ? TextDecoration.lineThrough : null),
                      ),
                      subtitle: Text('${patientNames[t.patientId] ?? "?"} · ${t.priority}', style: AppTextStyles.caption.copyWith(color: _priorityColor(t.priority))),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HandoverTab extends StatelessWidget {
  const _HandoverTab({required this.shift, required this.patients, required this.tasks});

  final Shift? shift;
  final List<Patient> patients;
  final List<WardTask> tasks;

  @override
  Widget build(BuildContext context) {
    final text = _formatHandover(shift, patients, tasks);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(text, style: AppTextStyles.body.copyWith(fontFamily: 'monospace')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  // Confirms inline by flipping to "Copied" for a moment
                  // instead of raising a snackbar.
                  child: CopyTextButton(getText: () => text),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(ShareParams(text: text, subject: 'Ward Handover')),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
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

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.shift, required this.onReload});

  final Shift shift;
  final Future<void> Function() onReload;

  Future<void> _completeShift(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Active Shift'),
        content: const Text('This will finalize your rounding activities but preserve all patient records and checklists.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Complete Shift')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wardApiProvider).completeShift(shift.id);
    await onReload();
  }

  Future<void> _wipeData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Shift & Wipe All Data'),
        content: const Text(
          '⚠️ WARNING: This will permanently delete all active patients, clinical checkmarks, DNAR flags, and handover data from this device. This operation is IRREVERSIBLE.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Erase All Data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wardApiProvider).wipeShiftData();
    await onReload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Shift', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${shift.ward} — ${shift.specialty}', style: AppTextStyles.bodyStrong),
                  Text('${shift.shiftType}${shift.active ? "" : " (completed)"}', style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (shift.active)
            OutlinedButton.icon(
              onPressed: () => _completeShift(context, ref),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Complete Shift'),
            ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => _wipeData(context, ref),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('End Shift & Wipe All Data'),
          ),
        ],
      ),
    );
  }
}
