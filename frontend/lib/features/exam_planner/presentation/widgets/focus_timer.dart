import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

const focusTimerDurationPresets = [
  Duration(minutes: 25),
  Duration(minutes: 50),
];

/// Lives in a regular (non-autoDispose) provider so the countdown survives
/// the Focus Timer bottom sheet being dismissed — previously the timer state
/// lived in FocusTimer's own State object, so tapping outside the sheet
/// (which just pops it) destroyed the running countdown entirely (owner
/// feedback, 2026-09-12). Re-opening the sheet now shows the same
/// controller, still counting down (or already finished) exactly as left.
final focusTimerControllerProvider = ChangeNotifierProvider<FocusTimerController>((ref) {
  final controller = FocusTimerController();
  ref.onDispose(controller.dispose);
  return controller;
});

class FocusTimerController extends ChangeNotifier {
  Duration selectedDuration = focusTimerDurationPresets.first;
  Duration _pausedRemaining = focusTimerDurationPresets.first;
  Duration remaining = focusTimerDurationPresets.first;
  DateTime? _startedAt;
  bool isRunning = false;
  bool isDone = false;
  Timer? _ticker;
  final AudioPlayer _player = AudioPlayer();

  void _syncRemaining() {
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    final rem = _pausedRemaining - elapsed;
    if (rem <= Duration.zero) {
      remaining = Duration.zero;
      isRunning = false;
      if (!isDone) {
        isDone = true;
        // SystemSound.play(SystemSoundType.alert) is silent on most Android
        // devices — Android has no built-in "alert" tone, unlike iOS — so a
        // bundled beep asset is played directly instead (owner feedback,
        // 2026-09-12: "beep sound is not enabled").
        _player.play(AssetSource('sounds/timer_beep.wav'));
      }
      _ticker?.cancel();
    } else {
      remaining = rem;
    }
    notifyListeners();
  }

  void selectDuration(Duration duration) {
    if (isRunning) return;
    _ticker?.cancel();
    selectedDuration = duration;
    _pausedRemaining = duration;
    remaining = duration;
    _startedAt = null;
    isDone = false;
    notifyListeners();
  }

  void start() {
    _startedAt = DateTime.now();
    _pausedRemaining = remaining;
    isRunning = true;
    isDone = false;
    notifyListeners();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncRemaining());
  }

  void pause() {
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    var rem = _pausedRemaining - elapsed;
    if (rem.isNegative) rem = Duration.zero;
    _pausedRemaining = rem;
    _startedAt = null;
    _ticker?.cancel();
    remaining = rem;
    isRunning = false;
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _startedAt = null;
    _pausedRemaining = selectedDuration;
    isRunning = false;
    isDone = false;
    remaining = selectedDuration;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player.dispose();
    super.dispose();
  }
}

/// Self-contained focus/Pomodoro countdown with selectable durations. State
/// lives in [FocusTimerController] (see above), not in this widget, so it
/// keeps running in the background even while the bottom sheet showing it is
/// closed.
class FocusTimer extends ConsumerWidget {
  const FocusTimer({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(focusTimerControllerProvider);
    final totalSeconds = controller.selectedDuration.inSeconds;
    final progress = totalSeconds == 0 ? 0.0 : controller.remaining.inSeconds / totalSeconds;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: controller.isDone
            ? AppColors.success.withValues(alpha: 0.08)
            : (isDark ? AppColors.slate800 : Colors.white),
        border: Border.all(
          color: controller.isDone
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
                  color: controller.isDone
                      ? AppColors.success
                      : (controller.isRunning
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (isDark
                                  ? AppColors.slate700
                                  : AppColors.slate100)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.self_improvement_rounded,
                  color: controller.isDone
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
                      _fmt(controller.remaining),
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
              for (final duration in focusTimerDurationPresets)
                ChoiceChip(
                  label: Text('${duration.inMinutes} min'),
                  selected: controller.selectedDuration == duration,
                  onSelected: controller.isRunning ? null : (_) => controller.selectDuration(duration),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.isRunning ? controller.pause : controller.start,
              style: FilledButton.styleFrom(backgroundColor: controller.isRunning ? AppColors.warning : AppColors.success),
              icon: Icon(controller.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(
                controller.isRunning
                    ? 'Pause'
                    : (controller.remaining < controller.selectedDuration ? 'Resume' : 'Start Focus Session'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: controller.reset,
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
              valueColor: AlwaysStoppedAnimation(controller.isDone ? AppColors.success : AppColors.primary),
            ),
          ),
          if (controller.isDone) ...[
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
