import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import 'ai_fab.dart';
import 'app_bottom_nav.dart';

/// Shared scaffold for the 5 top-level tab screens. Owns two pieces of
/// modern reading-mode UX (owner request, 2026-08-13):
///
/// 1. The bottom nav bar and the AI FAB hide automatically while the user
///    scrolls down (reading mode) and reappear on scroll-up or on a tap
///    anywhere on the screen.
/// 2. The Medaculous AI FAB lives bottom-right on every tab (instead of the
///    earlier app-bar corner icon the owner found awkward). Screens with
///    their own FAB (Notes) get the AI button stacked above it as a mini.
class NavShell extends StatefulWidget {
  const NavShell({
    required this.current,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.showAiFab = true,
    super.key,
  });

  final AppNavTab current;
  final Widget body;
  final PreferredSizeWidget? appBar;

  /// Screen-specific FAB (e.g. Notes "add"). The AI FAB stacks above it.
  final Widget? floatingActionButton;
  final bool showAiFab;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  bool _chromeVisible = true;

  void _setVisible(bool visible) {
    if (_chromeVisible != visible) {
      setState(() => _chromeVisible = visible);
    }
  }

  bool _onScroll(UserScrollNotification notification) {
    // Only react to vertical scrolls of the outermost scrollable; horizontal
    // chip rows etc. shouldn't toggle the chrome.
    if (notification.metrics.axis != Axis.vertical) return false;
    switch (notification.direction) {
      case ScrollDirection.reverse:
        _setVisible(false);
      case ScrollDirection.forward:
        _setVisible(true);
      case ScrollDirection.idle:
        // Always restore when the user is back at (or near) the top.
        if (notification.metrics.pixels <= 8) _setVisible(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fabs = <Widget>[
      if (widget.showAiFab) AiFab(mini: widget.floatingActionButton != null),
      if (widget.floatingActionButton != null) ...[
        const SizedBox(height: 12),
        widget.floatingActionButton!,
      ],
    ];

    // Bottom-nav taps use context.go(), which replaces the whole navigation
    // stack for the destination tab rather than pushing on top of Home — so
    // there is nothing left to pop back to. Without this, the system/gesture
    // back button on any non-Home tab does nothing (or exits the app
    // outright), which reads as "stuck, no way back" — most confusing right
    // after landing on a tab by mistake. Route back to Home explicitly
    // instead; Home keeps its own separate double-back-to-exit PopScope.
    final isHome = widget.current == AppNavTab.home;
    return PopScope(
      canPop: isHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isHome) context.go('/home');
      },
      child: Scaffold(
        appBar: widget.appBar,
        body: NotificationListener<UserScrollNotification>(
          onNotification: _onScroll,
          // A completed tap anywhere (that no button claims) brings the
          // chrome back — "tap to reveal" reading-mode behaviour.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _setVisible(true),
            child: widget.body,
          ),
        ),
        floatingActionButton: fabs.isEmpty
            ? null
            : AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                offset: _chromeVisible ? Offset.zero : const Offset(0, 2.2),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _chromeVisible ? 1 : 0,
                  child: Column(mainAxisSize: MainAxisSize.min, children: fabs),
                ),
              ),
        bottomNavigationBar: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _chromeVisible
              ? AppBottomNav(current: widget.current)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ),
    );
  }
}
