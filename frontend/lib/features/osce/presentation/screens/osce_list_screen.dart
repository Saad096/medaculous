import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/osce.dart';
import '../providers/osce_providers.dart';
import 'osce_station_screen.dart';

/// DISCOVERY_REPORT.md's "OSCE Preparation" — 29 curated clinical
/// examination stations, evidence-based checklists + a 10-minute station
/// timer. No AI involved: pure reference data + per-user favorites/progress.
class OsceListScreen extends ConsumerStatefulWidget {
  const OsceListScreen({super.key});

  @override
  ConsumerState<OsceListScreen> createState() => _OsceListScreenState();
}

class _OsceListScreenState extends ConsumerState<OsceListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';
  List<OsceStation> _stations = [];
  bool _isInitialLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_stations.isEmpty) setState(() => _error = null);
    try {
      final stations = await ref.read(osceApiProvider).listStations();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _isInitialLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isInitialLoading = false;
      });
    }
  }

  List<OsceStation> get _filtered {
    return _stations.where((s) {
      if (_category == 'Favourites' && !s.isFavorite) return false;
      if (_category != 'All' && _category != 'Favourites' && s.category != _category) return false;
      if (_query.trim().isNotEmpty) {
        final q = _query.toLowerCase();
        final matchesSteps = s.sections.any((sec) => sec.steps.any((step) => step.text.toLowerCase().contains(q)));
        if (!s.title.toLowerCase().contains(q) &&
            !s.system.toLowerCase().contains(q) &&
            !s.summary.toLowerCase().contains(q) &&
            !s.category.toLowerCase().contains(q) &&
            !matchesSteps) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _openStation(OsceStation station) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => OsceStationScreen(station: station)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(title: const Text('OSCE Preparation')),
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search stations (e.g. Cardiovascular, Knee)...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            borderSide: BorderSide(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.slate700
                                  : AppColors.slate200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: oscCategories.length,
                          separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.xs),
                          itemBuilder: (context, index) {
                            final cat = oscCategories[index];
                            final selected = _category == cat;
                            return ChoiceChip(
                              label: Text(cat),
                              selected: selected,
                              onSelected: (_) => setState(() => _category = cat),
                              selectedColor: AppColors.primary,
                              labelStyle: AppTextStyles.caption.copyWith(
                                color: selected
                                    ? Colors.white
                                    : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppColors.slate200
                                          : AppColors.slate700),
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: Center(
                            child: Text('No stations found', style: AppTextStyles.body.copyWith(color: context.secondaryText)),
                          ),
                        )
                      else
                        for (final station in filtered) _buildStationCard(station),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStationCard(OsceStation station) {
    final percent = station.progressPercent;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: () => _openStation(station),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                      child: Text(station.system,
                          style: AppTextStyles.micro.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  IconButton(
                    icon: Icon(station.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: station.isFavorite ? AppColors.warning : AppColors.slate400),
                    onPressed: () async {
                      final api = ref.read(osceApiProvider);
                      final next = !station.isFavorite;
                      setState(() {
                        _stations = _stations.map((s) => s.id == station.id ? s.copyWith(isFavorite: next) : s).toList();
                      });
                      if (next) {
                        await api.addFavorite(station.id);
                      } else {
                        await api.removeFavorite(station.id);
                      }
                    },
                  ),
                ],
              ),
              Text(station.title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(station.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: AppColors.slate400),
                  const SizedBox(width: 4),
                  Text(station.estimatedTime, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                  const Spacer(),
                  if (percent > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (percent == 100 ? AppColors.success : AppColors.primary).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${station.completedSteps}/${station.totalSteps} ($percent%)',
                          style: AppTextStyles.micro.copyWith(color: percent == 100 ? AppColors.success : AppColors.primary, fontWeight: FontWeight.bold)),
                    )
                  else
                    Text('Not started', style: AppTextStyles.micro.copyWith(color: AppColors.slate400)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
