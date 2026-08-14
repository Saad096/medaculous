import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/osce.dart';
import '../providers/osce_providers.dart';
import '../widgets/osce_timer.dart';

class OsceStationScreen extends ConsumerStatefulWidget {
  const OsceStationScreen({super.key, required this.station});

  final OsceStation station;

  @override
  ConsumerState<OsceStationScreen> createState() => _OsceStationScreenState();
}

class _OsceStationScreenState extends ConsumerState<OsceStationScreen> {
  late OsceStation _station = widget.station;

  Future<void> _toggleFavorite() async {
    final api = ref.read(osceApiProvider);
    final next = !_station.isFavorite;
    setState(() => _station = _station.copyWith(isFavorite: next));
    try {
      if (next) {
        await api.addFavorite(_station.id);
      } else {
        await api.removeFavorite(_station.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _station = _station.copyWith(isFavorite: !next));
      }
    }
  }

  Future<void> _toggleStep(OsceStep step) async {
    final api = ref.read(osceApiProvider);
    final next = !step.checked;
    setState(() {
      final sections = _station.sections
          .map(
            (sec) => sec.copyWith(
              steps: sec.steps
                  .map((s) => s.id == step.id ? s.copyWith(checked: next) : s)
                  .toList(),
            ),
          )
          .toList();
      final completed = sections.fold<int>(
        0,
        (sum, sec) => sum + sec.steps.where((s) => s.checked).length,
      );
      _station = _station.copyWith(
        sections: sections,
        completedSteps: completed,
      );
    });
    try {
      await api.setStepProgress(step.id, next);
    } catch (_) {
      if (mounted) {
        setState(() {
          final sections = _station.sections
              .map(
                (sec) => sec.copyWith(
                  steps: sec.steps
                      .map(
                        (s) => s.id == step.id ? s.copyWith(checked: !next) : s,
                      )
                      .toList(),
                ),
              )
              .toList();
          final completed = sections.fold<int>(
            0,
            (sum, sec) => sum + sec.steps.where((s) => s.checked).length,
          );
          _station = _station.copyWith(
            sections: sections,
            completedSteps: completed,
          );
        });
      }
    }
  }

  Future<void> _resetChecklist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset checklist?'),
        content: const Text('This clears all checked items for this station.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final api = ref.read(osceApiProvider);
    setState(() {
      final sections = _station.sections
          .map(
            (sec) => sec.copyWith(
              steps: sec.steps.map((s) => s.copyWith(checked: false)).toList(),
            ),
          )
          .toList();
      _station = _station.copyWith(sections: sections, completedSteps: 0);
    });
    await api.resetStationProgress(_station.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_station.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(
              _station.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: _station.isFavorite ? AppColors.warning : null,
            ),
            onPressed: _toggleFavorite,
            tooltip: _station.isFavorite
                ? 'Remove from favorites'
                : 'Mark as favorite',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const OsceTimer(),
          const SizedBox(height: AppSpacing.md),
          _buildHeaderCard(),
          const SizedBox(height: AppSpacing.md),
          for (final section in _station.sections) _buildSection(section),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = _station.progressPercent;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        border: Border.all(
          color: isDark ? AppColors.slate700 : AppColors.slate200,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(
                        _station.category,
                        style: AppTextStyles.micro.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        '⏱ ${_station.estimatedTime}',
                        style: AppTextStyles.micro,
                      ),
                    ),
                    if (percent == 100)
                      Chip(
                        avatar: const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.success,
                        ),
                        label: Text(
                          'Completed',
                          style: AppTextStyles.micro.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _station.completedSteps == 0
                    ? null
                    : _resetChecklist,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _station.summary,
            style: AppTextStyles.body.copyWith(color: context.secondaryText),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                'Checklist Progress: ${_station.completedSteps} of ${_station.totalSteps}',
                style: AppTextStyles.caption.copyWith(
                  color: context.secondaryText,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: isDark ? AppColors.slate700 : AppColors.slate100,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(OsceSection section) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checkedCount = section.steps.where((s) => s.checked).length;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        border: Border.all(
          color: isDark ? AppColors.slate700 : AppColors.slate200,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.slate900 : AppColors.slate50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '$checkedCount / ${section.steps.length}',
                  style: AppTextStyles.caption.copyWith(
                    color: context.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          for (final step in section.steps) _buildStep(step),
        ],
      ),
    );
  }

  Widget _buildStep(OsceStep step) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _toggleStep(step),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.slate700 : AppColors.slate100,
            ),
          ),
          color: step.checked
              ? (isDark ? AppColors.slate900 : AppColors.slate50)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: step.checked, onChanged: (_) => _toggleStep(step)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      Text(
                        step.text,
                        style: AppTextStyles.body.copyWith(
                          decoration: step.checked
                              ? TextDecoration.lineThrough
                              : null,
                          color: step.checked
                              ? AppColors.slate400
                              : (isDark ? Colors.white : AppColors.slate900),
                        ),
                      ),
                      if (step.isKeyStep)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'CRITICAL STEP',
                            style: AppTextStyles.micro.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (step.hint != null && step.hint!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.help_outline_rounded,
                          size: 14,
                          color: AppColors.slate400,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            step.hint!,
                            style: AppTextStyles.caption.copyWith(
                              color: context.secondaryText,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
