import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 6-box numeric-only OTP input with auto-advance and auto-submit on the
/// last digit (master spec §3.3: "OTP numeric-only input with auto-advance").
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.length,
    required this.onCompleted,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  State<OtpCodeField> createState() => OtpCodeFieldState();
}

class OtpCodeFieldState extends State<OtpCodeField> {
  late final List<TextEditingController> _controllers = List.generate(
    widget.length,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    widget.length,
    (_) => FocusNode(),
  );

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    // Multi-digit input means a paste or an OS one-time-code autofill landed
    // in one box: distribute the digits across the boxes from this position.
    // (Programmatic controller writes below don't re-trigger onChanged.)
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) {
        _controllers[index].clear();
        return;
      }
      var cursor = index;
      for (final digit in digits.split('')) {
        if (cursor >= widget.length) break;
        _controllers[cursor].text = digit;
        cursor++;
      }
      _focusNodes[cursor.clamp(0, widget.length - 1)].requestFocus();
    } else if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    final code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length) {
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
      widget.onCompleted(code);
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (index) {
        return SizedBox(
          width: 44,
          height: 56,
          child: KeyboardListener(
            focusNode: FocusNode(skipTraversal: true),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.backspace) {
                _onBackspace(index);
              }
            },
            child: TextField(
              key: Key('otp_digit_$index'),
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              // Room for a full pasted/autofilled code; _onChanged fans the
              // extra digits out across the remaining boxes. maxLength: 1
              // would silently truncate a paste to its first digit.
              maxLength: widget.length,
              // Lets Android/iOS offer the code from the OTP email/SMS as a
              // keyboard autofill suggestion.
              autofillHints: index == 0
                  ? const [AutofillHints.oneTimeCode]
                  : null,
              style: AppTextStyles.headline.copyWith(
                color: isDark ? Colors.white : AppColors.slate900,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                // The global inputDecorationTheme's contentPadding is sized
                // for full-width fields and clips a 22px digit inside this
                // 44x56 box, leaving only a sliver of the glyph visible.
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                filled: true,
                fillColor: isDark ? AppColors.slate800 : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.slate700 : AppColors.slate200,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (value) => _onChanged(index, value),
            ),
          ),
        );
      }),
    );
  }
}
