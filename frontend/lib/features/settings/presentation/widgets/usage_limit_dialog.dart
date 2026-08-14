import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../screens/paywall_screen.dart';

/// Shown wherever an AI-backed call 429s with the usage-limit-reached error
/// from api.deps.enforce_ai_usage_limit — owner request, 2026-08-14: "user
/// must get an upgrade account to continue... it will automatically routed
/// then according pay checkout screens."
Future<void> showUsageLimitDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.warning, size: 32),
      title: const Text("You've reached your AI limit"),
      content: const Text(
        "You've used all of your AI messages for this period. Upgrade to Medaculous Pro "
        'for a higher monthly limit.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Not now')),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            if (context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
            }
          },
          child: const Text('Upgrade'),
        ),
      ],
    ),
  );
}
