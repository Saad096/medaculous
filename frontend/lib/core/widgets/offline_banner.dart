import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// Global "you're offline" banner — wraps the whole app (master spec §3.2:
/// "Global: network-offline banner"). Never silently fails a request without
/// telling the user why.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
    });
    Connectivity().checkConnectivity().then((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: AppMotion.fast,
          child: _offline
              ? Container(
                  width: double.infinity,
                  color: AppColors.warning,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SafeArea(
                    bottom: false,
                    child: Text(
                      "You're offline — some features may not work",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
