import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Copy-to-clipboard controls that confirm inline: the control itself flips
/// to a green "Copied" state for a moment instead of popping a snackbar,
/// which keeps the confirmation exactly where the user is looking.
class CopyIconButton extends StatefulWidget {
  const CopyIconButton({required this.text, this.tooltip = 'Copy', super.key});

  final String text;
  final String tooltip;

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _copied ? 'Copied' : widget.tooltip,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 20,
        color: _copied ? AppColors.success : null,
      ),
      // Stays tappable while showing "copied" — a disabled button would gray
      // out the success check instead of showing it green.
      onPressed: _copy,
    );
  }
}

/// Labeled variant for full-width layouts (e.g. the ward handover sheet).
class CopyTextButton extends StatefulWidget {
  const CopyTextButton({required this.getText, this.label = 'Copy', super.key});

  /// Lazily resolved so callers can copy freshly formatted content.
  final String Function() getText;
  final String label;

  @override
  State<CopyTextButton> createState() => _CopyTextButtonState();
}

class _CopyTextButtonState extends State<CopyTextButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.getText()));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _copy,
      style: _copied
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColors.success,
              side: const BorderSide(color: AppColors.success),
            )
          : null,
      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
      label: Text(_copied ? 'Copied' : widget.label),
    );
  }
}
