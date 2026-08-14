import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/app_colors.dart';

/// DISCOVERY_REPORT.md's "Calculator" feature — an in-app browser over
/// MDCalc, exactly as the feature PDF specifies ("This is an in-app web
/// browser and navigates to MDCALC website"). The owner reconfirmed MDCalc
/// on 2026-08-13, superseding the earlier ClinCalc swap.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  static const _homeUrl = 'https://www.mdcalc.com/';

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _canGoBack = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) async {
            final canGoBack = await _controller.canGoBack();
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _canGoBack = canGoBack;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = 'Could not load page: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(CalculatorScreen._homeUrl));
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculator'),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_rounded),
              tooltip: 'MDCalc home',
              onPressed: () =>
                  _controller.loadRequest(Uri.parse(CalculatorScreen._homeUrl)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
              onPressed: () => _controller.reload(),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 48,
                        color: AppColors.slate400,
                      ),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _controller.reload();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              WebViewWidget(controller: _controller),
            if (_isLoading && _error == null)
              const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }
}
