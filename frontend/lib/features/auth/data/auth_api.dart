import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_exception.dart';

/// Dio's MultipartFile defaults to application/octet-stream when no
/// contentType is given, which fails the backend's `image/*` content-type
/// gate outright — the upload silently 400s and nothing ever reaches disk.
MediaType _imageMediaType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => MediaType('image', 'png'),
    'heic' => MediaType('image', 'heic'),
    'webp' => MediaType('image', 'webp'),
    _ => MediaType('image', 'jpeg'),
  };
}

/// Thin wrapper over the raw HTTP calls to backend/app/api/v1/auth.py.
/// No token/state handling here — that's AuthRepository's job.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(
    Future<Response> Function() request,
    T Function(Map<String, dynamic>) onOk,
  ) async {
    try {
      final response = await request();
      return onOk(
        response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _call(
      () => _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
        },
      ),
      (data) => data,
    );
  }

  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) {
    return _call(
      () =>
          _dio.post('/auth/verify-email', data: {'email': email, 'code': code}),
      (data) => data,
    );
  }

  Future<void> resendOtp({required String email}) {
    return _call(
      () => _dio.post('/auth/resend-otp', data: {'email': email}),
      (_) {},
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) {
    return _call(
      () => _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      ),
      (data) => data,
    );
  }

  Future<void> logout({required String refreshToken}) {
    return _call(
      () => _dio.post('/auth/logout', data: {'refresh_token': refreshToken}),
      (_) {},
    );
  }

  Future<void> forgotPassword({required String email}) {
    return _call(
      () => _dio.post('/auth/forgot-password', data: {'email': email}),
      (_) {},
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _call(
      () => _dio.post(
        '/auth/reset-password',
        data: {'email': email, 'code': code, 'new_password': newPassword},
      ),
      (_) {},
    );
  }

  Future<Map<String, dynamic>> me() {
    return _call(() => _dio.get('/auth/me'), (data) => data);
  }

  Future<Map<String, dynamic>> googleSignIn({required String idToken}) {
    return _call(
      () => _dio.post('/auth/google', data: {'id_token': idToken}),
      (data) => data,
    );
  }

  Future<Map<String, dynamic>> appleSignIn({
    required String identityToken,
    String? fullName,
  }) {
    return _call(
      () => _dio.post(
        '/auth/apple',
        data: {
          'identity_token': identityToken,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        },
      ),
      (data) => data,
    );
  }

  Future<Map<String, dynamic>> uploadAvatar(Uint8List bytes, String filename) {
    return _call(
      () => _dio.put(
        '/auth/me/avatar',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: _imageMediaType(filename),
          ),
        }),
      ),
      (data) => data,
    );
  }

  /// Returns null on a 404 (no avatar uploaded yet) rather than throwing —
  /// callers just fall back to initials in that case.
  Future<Uint8List?> getAvatarBytes() async {
    try {
      final response = await _dio.get<List<int>>(
        '/auth/me/avatar',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> deleteAvatar() {
    return _call(() => _dio.delete('/auth/me/avatar'), (data) => data);
  }
}
