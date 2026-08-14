import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../domain/disease.dart';
import '../providers/systems_providers.dart';

class SystemsListScreen extends ConsumerStatefulWidget {
  const SystemsListScreen({super.key});

  @override
  ConsumerState<SystemsListScreen> createState() => _SystemsListScreenState();
}

class _SystemsListScreenState extends ConsumerState<SystemsListScreen> {
  late Future<List<MedicalSystem>> _systemsFuture;
  bool _iconView = true;

  @override
  void initState() {
    super.initState();
    _systemsFuture = ref.read(systemsApiProvider).listSystems();
  }

  @override
  Widget build(BuildContext context) {
    return NavShell(
      current: AppNavTab.systems,
      appBar: AppBar(
        // Real, visible back arrow to Home — this is a bottom-nav tab root
        // with nothing else on the stack to fall back to, and relying on
        // the hardware/gesture back button alone isn't discoverable enough.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Systems'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search diseases',
            onPressed: () => context.push('/systems/search'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: _ViewToggle(
              iconView: _iconView,
              onChanged: (value) => setState(() => _iconView = value),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MedicalSystem>>(
              future: _systemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load systems.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  );
                }
                final systems = snapshot.data!;
                return _iconView
                    ? _IconGrid(systems: systems)
                    : _ListView(systems: systems);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.iconView, required this.onChanged});

  final bool iconView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Full-width segmented control (owner request, 2026-08-13) — each half
    // takes 50% of the row instead of a small pill hugging the right corner.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : AppColors.searchBarBackground,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleButton(
              icon: Icons.grid_view_rounded,
              label: 'Icon View',
              selected: iconView,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ViewToggleButton(
              icon: Icons.view_list_rounded,
              label: 'List View',
              selected: !iconView,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : AppColors.slate500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? Colors.white : AppColors.slate500,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.systems});

  final List<MedicalSystem> systems;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.3,
      ),
      itemCount: systems.length,
      itemBuilder: (context, index) {
        final system = systems[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () =>
                context.push('/systems/${system.id}', extra: system.name),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(system.icon, style: const TextStyle(fontSize: 36)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    system.name,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.systems});

  final List<MedicalSystem> systems;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: systems.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final system = systems[index];
        return ListTile(
          leading: Text(system.icon, style: const TextStyle(fontSize: 24)),
          title: Text(system.name, style: AppTextStyles.bodyStrong),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.slate400,
          ),
          onTap: () =>
              context.push('/systems/${system.id}', extra: system.name),
        );
      },
    );
  }
}
