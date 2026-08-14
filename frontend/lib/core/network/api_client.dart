import 'package:dio/dio.dart';

import '../config/env.dart';
import '../storage/token_storage.dart';

/// Auth endpoints that don't require (and can't meaningfully act on) a bearer
/// token — a 401 from one of these means bad credentials or an invalid
/// refresh token, never "your access token expired," so silent-refresh must
/// never trigger for them. Deliberately a path allowlist rather than "starts
/// with /auth/", since /auth/me *is* bearer-protected and must still trigger
/// silent refresh on expiry.
const _unauthenticatedAuthPaths = {
  '/auth/register',
  '/auth/login',
  '/auth/verify-email',
  '/auth/resend-otp',
  '/auth/refresh',
  '/auth/logout',
  '/auth/forgot-password',
  '/auth/reset-password',
  '/auth/google',
  '/auth/apple',
};

/// Single Dio instance for the whole app. Attaches the access token to every
/// request and transparently refreshes it on a 401 (silent refresh + retry
/// once), so a mid-request token expiry never surfaces as a hard error to
/// the UI — see master spec §5 "Access-token expiry mid-request handled
/// gracefully."
class ApiClient {
  ApiClient({required TokenStorage tokenStorage})
      : _tokenStorage = tokenStorage,
        dio = Dio(BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )) {
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isUnauthenticatedEndpoint = _unauthenticatedAuthPaths.contains(error.requestOptions.path);
          final is401 = error.response?.statusCode == 401;
          // Guards against an infinite loop if the retried request 401s again
          // (e.g. the refreshed token is itself rejected) — refresh at most once per request.
          final alreadyRetriedAfterRefresh = error.requestOptions.extra['refreshRetried'] == true;

          if (is401 && !isUnauthenticatedEndpoint && !alreadyRetriedAfterRefresh) {
            final refreshed = await _tryRefresh();
            if (!refreshed) {
              onSessionExpired?.call();
              return handler.next(error);
            }
            try {
              final retried = await dio.fetch(error.requestOptions..extra['refreshRetried'] = true);
              return handler.resolve(retried);
            } on DioException catch (retryError) {
              return handler.next(retryError);
            }
          }

          // Retry-with-backoff for transient network blips — GET only, since
          // retrying a POST/PUT/DELETE that already reached the server risks
          // duplicating a non-idempotent side effect (e.g. double-registering).
          final isTransient = error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError ||
              (error.response?.statusCode ?? 0) >= 500;
          final isGet = error.requestOptions.method.toUpperCase() == 'GET';
          final attempt = (error.requestOptions.extra['retryAttempt'] as int?) ?? 0;

          if (isTransient && isGet && attempt < 2) {
            await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1) * (attempt + 1)));
            try {
              final retried = await dio.fetch(
                error.requestOptions..extra['retryAttempt'] = attempt + 1,
              );
              return handler.resolve(retried);
            } on DioException catch (retryError) {
              return handler.next(retryError);
            }
          }

          return handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _tokenStorage;

  /// Set from outside after construction (see auth_providers.dart) rather
  /// than passed into the constructor — that would create a cyclic
  /// dependency between apiClientProvider and authControllerProvider, which
  /// the Dart analyzer rejects outright (`top_level_cycle`) even though the
  /// callback only fires long after both providers exist.
  void Function()? onSessionExpired;

  Future<bool> _tryRefresh() async {
    final refreshToken = await _tokenStorage.refreshToken;
    if (refreshToken == null) return false;

    try {
      // Bare Dio (no interceptors) — avoids recursing into this same 401 handler.
      final response = await Dio(BaseOptions(baseUrl: Env.apiBaseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      await _tokenStorage.save(
        accessToken: response.data['access_token'] as String,
        refreshToken: response.data['refresh_token'] as String,
      );
      return true;
    } on DioException {
      await _tokenStorage.clear();
      return false;
    }
  }
}
