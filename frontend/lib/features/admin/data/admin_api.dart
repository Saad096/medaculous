import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/admin_user.dart';

/// Thin wrapper over backend/app/api/v1/admin.py — every call here 403s
/// server-side for a non-admin token regardless of what the client shows.
class AdminApi {
  AdminApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic) onOk) async {
    try {
      final response = await request();
      return onOk(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AdminUserPage> listUsers({String? search, int page = 1, int pageSize = 50}) {
    return _call(
      () => _dio.get(
        '/admin/users',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'page_size': pageSize,
        },
      ),
      (data) => AdminUserPage.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<AdminUser> setUsageLimit(String userId, int? monthlyLimit) {
    return _call(
      () => _dio.patch('/admin/users/$userId/limit', data: {'ai_monthly_limit': monthlyLimit}),
      (data) => AdminUser.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteUser(String userId) {
    return _call(() => _dio.delete('/admin/users/$userId'), (_) {});
  }

  Future<AdminStats> getStats() {
    return _call(() => _dio.get('/admin/stats'), (data) => AdminStats.fromJson(data as Map<String, dynamic>));
  }
}
