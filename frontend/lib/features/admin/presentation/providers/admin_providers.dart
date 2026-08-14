import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/admin_api.dart';
import '../../domain/admin_user.dart';

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.read(apiClientProvider).dio));

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.read(adminApiProvider).getStats();
});

final adminUserSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final adminUserPageProvider = FutureProvider.autoDispose<AdminUserPage>((ref) {
  final search = ref.watch(adminUserSearchProvider);
  return ref.read(adminApiProvider).listUsers(search: search.isEmpty ? null : search);
});
