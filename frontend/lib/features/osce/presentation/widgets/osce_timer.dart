import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Pure client-side 10-minute station countdown, ported from the legacy
/// OsceTimer.tsx. No backend involvement — nothing to persist or sync.
///
/// Time-tracking is wall-clock based rather than a naive decrementing
/// counter: `_startedAt` records the real timestamp the countdown last
/// (re)started, and `_pausedRemaining` is the duration to count down from
/// that point. Remaining time is always derived as
/// `_pausedRemaining - (now - _startedAt)`. This makes the timer
/// self-correcting if the periodic ticker misses ticks — e.g. because
/// Android suspended the app's Dart isolate while backgrounded/locked — the
/// very next tick that does fire recomputes from real elapsed time instead
/// of having lost it.
class OsceTimer extends StatefulWidget {
  const OsceTimer({super.key, this.initialSeconds = 600});

  final int initialSeconds;

  @override
  State<OsceTimer> createState() => _OsceTimerState();
}

class _OsceTimerState extends State<OsceTimer> {
  late int _timeLeft = widget.initialSeconds;
  late Duration _pausedRemaining = Duration(seconds: widget.initialSeconds);
  DateTime? _startedAt;
  bool _isRunning = false;
  bool _isTimeUp = false;
  Timer? _timer;
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Recomputes `_timeLeft` from the wall-clock start time rather than
  /// decrementing — safe to call from a ticker that may have missed ticks.
  void _syncTimeLeft() {
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    final remaining = _pausedRemaining - elapsed;
    setState(() {
      if (remaining <= Duration.zero) {
        _timeLeft = 0;
        _isRunning = false;
        if (!_isTimeUp) {
          _isTimeUp = true;
          // SystemSound.play(SystemSoundType.alert) is silent on most
          // Android devices (no built-in "alert" tone there), so a bundled
          // beep asset is played directly instead (owner feedback,
          // 2026-09-12: "beep sound is not enabled").
          _player.play(AssetSource('sounds/timer_beep.wav'));
        }
        _timer?.cancel();
      } else {
        _timeLeft = remaining.inSeconds;
      }
    });
  }

  void _start() {
    _startedAt = DateTime.now();
    _pausedRemaining = Duration(seconds: _timeLeft);
    setState(() {
      _isTimeUp = false;
      _isRunning = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _syncTimeLeft());
  }

  void _pause() {
    // Freeze the current wall-clock-derived remaining duration so resuming
    // (via _start) continues counting down from the right place.
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    _pausedRemaining = _pausedRemaining - elapsed;
    if (_pausedRemaining.isNegative) _pausedRemaining = Duration.zero;
    _startedAt = null;
    _timer?.cancel();
    setState(() {
      _timeLeft = _pausedRemaining.inSeconds;
      _isRunning = false;
    });
  }

  void _reset() {
    _timer?.cancel();
    _startedAt = null;
    _pausedRemaining = Duration(seconds: widget.initialSeconds);
    setState(() {
      _isRunning = false;
      _isTimeUp = false;
      _timeLeft = widget.initialSeconds;
    });
  }

  void _addSeconds(int delta) {
    final updated = (_timeLeft + delta).clamp(0, 1 << 30);
    // Keep the wall-clock baseline in sync so a running timer doesn't jump
    // back to the pre-adjustment value on the next tick.
    _pausedRemaining = Duration(seconds: updated);
    _startedAt = _isRunning ? DateTime.now() : null;
    setState(() => _timeLeft = updated);
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = widget.initialSeconds == 0
        ? 0.0
        : _timeLeft / widget.initialSeconds;
    final barColor = _timeLeft < 120
        ? AppColors.danger
        : (_timeLeft < 300 ? AppColors.warning : AppColors.success);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _isTimeUp
            ? AppColors.danger.withValues(alpha: 0.08)
            : (isDark ? AppColors.slate800 : Colors.white),
        border: Border.all(
          color: _isTimeUp
              ? AppColors.danger.withValues(alpha: 0.4)
              : (isDark ? AppColors.slate700 : AppColors.slate200),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isTimeUp
                      ? AppColors.danger
                      : (_isRunning
                            ? AppColors.success.withValues(alpha: 0.15)
                            : (isDark
                                  ? AppColors.slate700
                                  : AppColors.slate100)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.timer_outlined,
                  color: _isTimeUp
                      ? Colors.white
                      : (isDark ? AppColors.slate200 : AppColors.slate700),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10-MINUTE OSCE STATION TIMER',
                      style: AppTextStyles.micro.copyWith(
                        color: context.secondaryText,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _fmt(_timeLeft),
                          style: AppTextStyles.headline.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '/ 10:00',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isRunning ? _pause : _start,
              style: FilledButton.styleFrom(
                backgroundColor: _isRunning
                    ? AppColors.warning
                    : AppColors.success,
              ),
              icon: Icon(
                _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                _isRunning
                    ? 'Pause'
                    : (_timeLeft < widget.initialSeconds
                          ? 'Resume'
                          : 'Start Station'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Reset'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  onPressed: _timeLeft > 0 ? () => _addSeconds(-60) : null,
                  child: const Text('-1m'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _addSeconds(60),
                  child: const Text('+1m'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? AppColors.slate700 : AppColors.slate100,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          if (_isTimeUp) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Time's Up! (10 Minutes Reached)",
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Wrap up your summary and thank the patient.',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
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
