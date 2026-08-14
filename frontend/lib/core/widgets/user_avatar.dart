import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../features/auth/domain/user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Circular profile photo, falling back to an initial-letter avatar when the
/// user hasn't uploaded one (or it hasn't finished loading yet). Used both as
/// the tappable Home-header entry point into Settings and inside Settings
/// itself.
class UserAvatar extends ConsumerStatefulWidget {
  const UserAvatar({super.key, required this.user, this.radius = 18});

  final AppUser user;
  final double radius;

  @override
  ConsumerState<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends ConsumerState<UserAvatar> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(avatarProvider.notifier)
          .ensureLoaded(hasAvatar: widget.user.hasAvatar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = ref.watch(avatarProvider);
    final initial =
        (widget.user.displayName?.isNotEmpty ?? false)
            ? widget.user.displayName![0].toUpperCase()
            : widget.user.email[0].toUpperCase();

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              initial,
              style: AppTextStyles.bodyStrong.copyWith(
                color: AppColors.primary,
                fontSize: widget.radius * 0.85,
              ),
            )
          : null,
    );
  }
}
