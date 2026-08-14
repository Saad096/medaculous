import 'package:dio/dio.dart';

/// Normalizes Dio errors (FastAPI's {"detail": "..."}, a {"detail": {"code",
/// "message"}} structured error, or a 422 validation error list) and
/// connection failures into one human-readable message every screen can show
/// directly, instead of each screen parsing Dio internals.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable error code for cases a screen needs to branch on (e.g.
  /// "email_not_verified" routing straight to OTP verify) rather than just
  /// display the message. Null for plain string-detail errors.
  final String? code;

  factory ApiException.fromDioException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return ApiException('Could not reach the server. Check your connection and try again.');
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) {
        return ApiException(detail, statusCode: error.response?.statusCode);
      }
      if (detail is Map && detail['message'] is String) {
        return ApiException(
          detail['message'] as String,
          statusCode: error.response?.statusCode,
          code: detail['code'] as String?,
        );
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return ApiException(first['msg'] as String, statusCode: error.response?.statusCode);
        }
      }
    }
    return ApiException('Something went wrong. Please try again.', statusCode: error.response?.statusCode);
  }

  @override
  String toString() => message;
}
