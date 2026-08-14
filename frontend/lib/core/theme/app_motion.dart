import 'package:flutter/material.dart';

/// Motion language extracted from the legacy app (DISCOVERY_REPORT.md §3):
/// short, spring-based scale+fade for direct manipulation (buttons, page
/// transitions) — never slide-based. Global button press: ~200ms, scale to
/// 0.95. Page transitions: ~300ms scale (0.95->1) + fade.
class AppMotion {
  AppMotion._();

  static const Duration tap = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration page = Duration(milliseconds: 300);

  static const Curve tapCurve = Curves.easeOut;
  static const Curve pageCurve = Curves.easeOutCubic;

  static const double tapScale = 0.95;
}

/// Wraps any tappable child with the app-wide press-scale feedback so every
/// button in the app feels consistent (mirrors the legacy app's blanket
/// button codemod — see apply-animations.cjs in the discovery report).
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, required this.onTap, this.enabled = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
      onTapCancel: widget.enabled ? () => _setPressed(false) : null,
      onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.tapScale : 1.0,
        duration: AppMotion.tap,
        curve: AppMotion.tapCurve,
        child: widget.child,
      ),
    );
  }
}

/// A page route with the app's scale+fade transition instead of the platform
/// default slide — matches the legacy app's PageTransition motion idiom.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget page})
      : super(
          transitionDuration: AppMotion.page,
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: AppMotion.pageCurve);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
