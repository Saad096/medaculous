import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/admin_user.dart';
import '../providers/admin_providers.dart';

/// Owner-only usage dashboard (owner request, 2026-08-14: "Admin dashboards
/// too like general like to see the AI usage total active user"). Gated at
/// the route level (see app_router.dart) by AppUser.isAdmin, and every call
/// still 403s server-side for a non-admin token regardless of client state.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminStatsProvider);
          ref.invalidate(adminUserPageProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            statsAsync.when(
              data: (stats) => _StatsSection(stats: stats),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorCard(message: e is ApiException ? e.message : 'Failed to load stats.'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Users', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            const _UserSearchField(),
            const SizedBox(height: AppSpacing.md),
            const _UserList(),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Text(message, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.6,
          children: [
            _StatCard(label: 'Total Users', value: '${stats.totalUsers}', icon: Icons.people_alt_rounded, color: AppColors.primary),
            _StatCard(label: 'Verified', value: '${stats.verifiedUsers}', icon: Icons.verified_rounded, color: AppColors.success),
            _StatCard(label: 'Active Trials', value: '${stats.activeTrialUsers}', icon: Icons.hourglass_top_rounded, color: AppColors.warning),
            _StatCard(label: 'AI Messages Used', value: '${stats.totalAiMessagesUsed}', icon: Icons.psychology_alt_rounded, color: AppColors.aiPurple),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Signups, last 14 days', style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.md),
        _SignupsChart(data: stats.signupsLast14Days),
        if (stats.topAiUsers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('Top AI Usage', style: AppTextStyles.bodyStrong),
          const SizedBox(height: AppSpacing.md),
          ...stats.topAiUsers.map((u) => _TopUserTile(user: u)),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Text(value, style: AppTextStyles.title),
          Text(label, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
        ],
      ),
    );
  }
}

/// Plain-Flutter bar chart (no charting package dependency) — 14 bars scaled
/// against the day with the most signups.
class _SignupsChart extends StatelessWidget {
  const _SignupsChart({required this.data});

  final List<DailyCount> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Text('No signups in the last 14 days.', style: AppTextStyles.body.copyWith(color: context.secondaryText));
    }
    final maxCount = data.map((d) => d.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 120,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '${d.date}: ${d.count}',
                  child: FractionallySizedBox(
                    heightFactor: (d.count / maxCount).clamp(0.04, 1.0),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: d.count > 0 ? AppColors.primary : AppColors.slate300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopUserTile extends StatelessWidget {
  const _TopUserTile({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              user.displayName?.isNotEmpty ?? false ? user.displayName! : user.email,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body,
            ),
          ),
          Text('${user.aiMessagesUsed} / ${user.aiUsageLimit}', style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
        ],
      ),
    );
  }
}

class _UserSearchField extends ConsumerWidget {
  const _UserSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Search by email or name',
        prefixIcon: Icon(Icons.search_rounded),
        border: OutlineInputBorder(),
      ),
      onChanged: (value) => ref.read(adminUserSearchProvider.notifier).state = value,
    );
  }
}

class _UserList extends ConsumerWidget {
  const _UserList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(adminUserPageProvider);
    return pageAsync.when(
      data: (page) {
        if (page.users.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text('No users found.', style: AppTextStyles.body.copyWith(color: context.secondaryText)),
          );
        }
        return Column(children: page.users.map((u) => _UserRow(user: u)).toList());
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _ErrorCard(message: e is ApiException ? e.message : 'Failed to load users.'),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user});

  final AdminUser user;

  Future<void> _editLimit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: user.aiMonthlyLimit?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set AI message limit'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Messages per 30 days',
            hintText: 'Leave blank to use the plan default',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(adminApiProvider).setUsageLimit(user.id, result.isEmpty ? null : int.tryParse(result));
      ref.invalidate(adminUserPageProvider);
      if (context.mounted) showAppToast(context, 'Limit updated for ${user.email}');
    } on ApiException catch (e) {
      if (context.mounted) showAppToast(context, e.message, kind: AppToastKind.error);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          'This permanently deletes ${user.email} and all their notes, conversations, and app data. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(adminApiProvider).deleteUser(user.id);
      ref.invalidate(adminUserPageProvider);
      ref.invalidate(adminStatsProvider);
      if (context.mounted) showAppToast(context, 'Account deleted');
    } on ApiException catch (e) {
      if (context.mounted) showAppToast(context, e.message, kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.displayName?.isNotEmpty ?? false ? user.displayName! : user.email,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyStrong,
                      ),
                    ),
                    if (user.isAdmin) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.shield_rounded, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                Text(user.email, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
                const SizedBox(height: 4),
                Text(
                  'AI usage: ${user.aiMessagesUsed} / ${user.aiUsageLimit} · ${user.subscriptionTier}',
                  style: AppTextStyles.micro.copyWith(color: context.secondaryText),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Set AI limit',
            onPressed: () => _editLimit(context, ref),
          ),
          if (!user.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              tooltip: 'Delete account',
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
    );
  }
}
