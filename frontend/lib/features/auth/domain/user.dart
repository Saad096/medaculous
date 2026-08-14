class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isVerified,
    required this.isTrialActive,
    required this.trialExpiresAt,
    required this.signInMethod,
    required this.hasAvatar,
    required this.isAdmin,
    required this.subscriptionTier,
    required this.aiMessagesUsed,
    required this.aiUsageLimit,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    isVerified: json['is_verified'] as bool,
    isTrialActive: json['is_trial_active'] as bool,
    trialExpiresAt: DateTime.parse(json['trial_expires_at'] as String),
    signInMethod: json['sign_in_method'] as String? ?? 'email',
    hasAvatar: json['has_avatar'] as bool? ?? false,
    isAdmin: json['is_admin'] as bool? ?? false,
    subscriptionTier: json['subscription_tier'] as String? ?? 'trial',
    aiMessagesUsed: json['ai_messages_used'] as int? ?? 0,
    aiUsageLimit: json['ai_usage_limit'] as int? ?? 50,
  );

  final String id;
  final String email;
  final String? displayName;
  final bool isVerified;

  /// 'email', 'google', or 'apple' — which credential type this account uses.
  final String signInMethod;

  /// Whether a profile photo was uploaded — the actual image is fetched
  /// separately (authenticated) via AuthApi.avatarUrl, not embedded here.
  final bool hasAvatar;

  /// Grants access to the in-app Admin dashboard (see admin_providers.dart) —
  /// seeded server-side for talk2saadalam@gmail.com only.
  final bool isAdmin;

  /// 'trial', 'monthly', or 'annual' — cosmetic until a real payment
  /// processor is wired up (see CheckoutScreen's "coming soon" final step).
  final String subscriptionTier;

  final int aiMessagesUsed;
  final int aiUsageLimit;

  bool get isAiLimitReached => aiMessagesUsed >= aiUsageLimit;

  /// Trial-tracking scaffolding (see backend TRIAL_DURATION_DAYS /
  /// OPEN_QUESTIONS.md) — not enforced as a paywall yet, just surfaced so the
  /// UI can show status. No pricing/payment provider decided yet.
  final bool isTrialActive;
  final DateTime trialExpiresAt;

  int get trialDaysLeft {
    final diff = trialExpiresAt.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays + 1;
  }
}
