class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isVerified,
    required this.isActive,
    required this.isAdmin,
    required this.subscriptionTier,
    required this.aiMessagesUsed,
    required this.aiMonthlyLimit,
    required this.aiUsageLimit,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    isVerified: json['is_verified'] as bool,
    isActive: json['is_active'] as bool,
    isAdmin: json['is_admin'] as bool,
    subscriptionTier: json['subscription_tier'] as String,
    aiMessagesUsed: json['ai_messages_used'] as int,
    aiMonthlyLimit: json['ai_monthly_limit'] as int?,
    aiUsageLimit: json['ai_usage_limit'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String email;
  final String? displayName;
  final bool isVerified;
  final bool isActive;
  final bool isAdmin;
  final String subscriptionTier;
  final int aiMessagesUsed;
  final int? aiMonthlyLimit;
  final int aiUsageLimit;
  final DateTime createdAt;
}

class AdminUserPage {
  const AdminUserPage({required this.users, required this.total, required this.page, required this.pageSize});

  factory AdminUserPage.fromJson(Map<String, dynamic> json) => AdminUserPage(
    users: (json['users'] as List).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList(),
    total: json['total'] as int,
    page: json['page'] as int,
    pageSize: json['page_size'] as int,
  );

  final List<AdminUser> users;
  final int total;
  final int page;
  final int pageSize;
}

class DailyCount {
  const DailyCount({required this.date, required this.count});

  factory DailyCount.fromJson(Map<String, dynamic> json) =>
      DailyCount(date: json['date'] as String, count: json['count'] as int);

  final String date;
  final int count;
}

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.verifiedUsers,
    required this.activeTrialUsers,
    required this.adminUsers,
    required this.totalAiMessagesUsed,
    required this.signupsLast14Days,
    required this.topAiUsers,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
    totalUsers: json['total_users'] as int,
    verifiedUsers: json['verified_users'] as int,
    activeTrialUsers: json['active_trial_users'] as int,
    adminUsers: json['admin_users'] as int,
    totalAiMessagesUsed: json['total_ai_messages_used'] as int,
    signupsLast14Days: (json['signups_last_14_days'] as List)
        .map((e) => DailyCount.fromJson(e as Map<String, dynamic>))
        .toList(),
    topAiUsers: (json['top_ai_users'] as List).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList(),
  );

  final int totalUsers;
  final int verifiedUsers;
  final int activeTrialUsers;
  final int adminUsers;
  final int totalAiMessagesUsed;
  final List<DailyCount> signupsLast14Days;
  final List<AdminUser> topAiUsers;
}
