import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/disease.dart';
import '../providers/systems_providers.dart';

class DiseaseSearchScreen extends ConsumerStatefulWidget {
  const DiseaseSearchScreen({super.key});

  @override
  ConsumerState<DiseaseSearchScreen> createState() =>
      _DiseaseSearchScreenState();
}

class _DiseaseSearchScreenState extends ConsumerState<DiseaseSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<DiseaseSummary> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isSearching = true);
      final results = await ref
          .read(systemsApiProvider)
          .searchDiseases(query.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search diseases…',
            border: InputBorder.none,
          ),
          style: AppTextStyles.body,
        ),
      ),
      body: _isSearching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
              child: Text(
                _controller.text.trim().length < 2
                    ? 'Type at least 2 characters to search.'
                    : 'No matches.',
                style: AppTextStyles.body.copyWith(color: AppColors.slate400),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final disease = _results[index];
                return ListTile(
                  title: Text(disease.name, style: AppTextStyles.body),
                  subtitle: Text(
                    disease.category,
                    style: AppTextStyles.caption.copyWith(
                      color: context.secondaryText,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.slate400,
                  ),
                  onTap: () => context.push(
                    '/diseases/${disease.id}',
                    extra: disease.name,
                  ),
                );
              },
            ),
    );
  }
}
