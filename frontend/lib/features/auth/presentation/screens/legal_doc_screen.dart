import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart' hide PdfDocument;
import 'package:pdfx/pdfx.dart' as pdfx show PdfDocument;

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/auth_providers.dart';

enum LegalDocType { terms, privacy }

/// Renders the real Terms of Service / Privacy Policy PDF the owner placed
/// on the backend (backend/app/static/legal/, served unauthenticated via
/// /api/v1/legal/terms and /legal/privacy) — replaces the placeholder
/// hardcoded text this screen used to show before those documents existed
/// (owner feedback, 2026-09-14).
class LegalDocScreen extends ConsumerStatefulWidget {
  const LegalDocScreen({super.key, required this.type});

  final LegalDocType type;

  @override
  ConsumerState<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends ConsumerState<LegalDocScreen> {
  PdfController? _controller;
  String? _error;

  bool get _isTerms => widget.type == LegalDocType.terms;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(legalApiProvider);
      final bytes = _isTerms ? await api.downloadTermsOfService() : await api.downloadPrivacyPolicy();
      if (!mounted) return;
      setState(() {
        _controller = PdfController(document: pdfx.PdfDocument.openData(bytes));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isTerms ? 'Terms of Service' : 'Privacy Policy')),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Could not load this document.\n$_error',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _error = null;
                          _load();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _controller == null
            ? const Center(child: CircularProgressIndicator())
            : PdfView(controller: _controller!),
      ),
    );
  }
}
