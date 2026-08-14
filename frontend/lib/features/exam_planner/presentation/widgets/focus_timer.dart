import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

const _durationPresets = [
  Duration(minutes: 25),
  Duration(minutes: 50),
];

/// Self-contained focus/Pomodoro countdown with selectable durations.
/// Purely client-side — nothing to persist or sync.
///
/// Mirrors osce_timer.dart's wall-clock-based approach rather than a naive
/// decrementing counter: `_startedAt` is the real timestamp the countdown
/// last (re)started, and `_pausedRemaining` is the duration to count down
/// from that point. Remaining time is always derived as
/// `_pausedRemaining - (now - _startedAt)`, so the timer stays accurate
/// even if the periodic ticker misses ticks while the app is backgrounded.
class FocusTimer extends StatefulWidget {
  const FocusTimer({super.key});

  @override
  State<FocusTimer> createState() => _FocusTimerState();
}

class _FocusTimerState extends State<FocusTimer> {
  Duration _selectedDuration = _durationPresets.first;
  late Duration _pausedRemaining = _selectedDuration;
  late Duration _remaining = _selectedDuration;
  DateTime? _startedAt;
  bool _isRunning = false;
  bool _isDone = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncRemaining() {
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    final remaining = _pausedRemaining - elapsed;
    setState(() {
      if (remaining <= Duration.zero) {
        _remaining = Duration.zero;
        _isRunning = false;
        _isDone = true;
        _ticker?.cancel();
      } else {
        _remaining = remaining;
      }
    });
  }

  void _selectDuration(Duration duration) {
    if (_isRunning) return;
    _ticker?.cancel();
    setState(() {
      _selectedDuration = duration;
      _pausedRemaining = duration;
      _remaining = duration;
      _startedAt = null;
      _isDone = false;
    });
  }

  void _start() {
    _startedAt = DateTime.now();
    _pausedRemaining = _remaining;
    setState(() {
      _isRunning = true;
      _isDone = false;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncRemaining());
  }

  void _pause() {
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    var remaining = _pausedRemaining - elapsed;
    if (remaining.isNegative) remaining = Duration.zero;
    _pausedRemaining = remaining;
    _startedAt = null;
    _ticker?.cancel();
    setState(() {
      _remaining = remaining;
      _isRunning = false;
    });
  }

  void _reset() {
    _ticker?.cancel();
    _startedAt = null;
    _pausedRemaining = _selectedDuration;
    setState(() {
      _isRunning = false;
      _isDone = false;
      _remaining = _selectedDuration;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _selectedDuration.inSeconds;
    final progress = totalSeconds == 0 ? 0.0 : _remaining.inSeconds / totalSeconds;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _isDone
            ? AppColors.success.withValues(alpha: 0.08)
            : (isDark ? AppColors.slate800 : Colors.white),
        border: Border.all(
          color: _isDone
              ? AppColors.success.withValues(alpha: 0.4)
              : (isDark ? AppColors.slate700 : AppColors.slate200),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isDone
                      ? AppColors.success
                      : (_isRunning
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (isDark
                                  ? AppColors.slate700
                                  : AppColors.slate100)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.self_improvement_rounded,
                  color: _isDone
                      ? Colors.white
                      : (isDark ? AppColors.slate200 : AppColors.slate700),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FOCUS TIMER', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
                    Text(
                      _fmt(_remaining),
                      style: AppTextStyles.headline.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Duration', style: AppTextStyles.micro.copyWith(color: context.secondaryText)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final duration in _durationPresets)
                ChoiceChip(
                  label: Text('${duration.inMinutes} min'),
                  selected: _selectedDuration == duration,
                  onSelected: _isRunning ? null : (_) => _selectDuration(duration),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isRunning ? _pause : _start,
              style: FilledButton.styleFrom(backgroundColor: _isRunning ? AppColors.warning : AppColors.success),
              icon: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(_isRunning ? 'Pause' : (_remaining < _selectedDuration ? 'Resume' : 'Start Focus Session')),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.slate100,
              valueColor: AlwaysStoppedAnimation(_isDone ? AppColors.success : AppColors.primary),
            ),
          ),
          if (_isDone) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Focus session complete! Take a short break.',
                      style: AppTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
