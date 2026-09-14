import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_exception.dart';

/// Read-only offline cache for GET responses — owner feedback, 2026-09-14:
/// "when offline, [these features] should be available for offline use."
/// Scoped deliberately to reads only: stores the last-known raw JSON for a
/// given endpoint (before it's parsed into typed model objects) so a screen
/// can keep showing that instead of an error when the device has no
/// connectivity. Writes (create/edit/delete) still require being online and
/// fail normally — a full offline write queue with sync/conflict handling is
/// a much larger effort than "make the reference content available offline."
class OfflineCache {
  OfflineCache._();

  static const _prefix = 'offline_cache_';

  static Future<void> put(String key, Object? data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(data));
  }

  static Future<Object?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Called on logout — a shared device signing into a different account
  /// should never see the previous account's cached reference data.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
  }
}

bool _isConnectivityFailure(DioException e) =>
    e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    e.type == DioExceptionType.connectionError;

/// A GET call that transparently falls back to the last cached response when
/// the device can't reach the server at all (not for a real error response
/// from a server that *was* reached — a 404/500 should never be masked by
/// stale cached data). [cacheKey] must be unique per distinct query (e.g.
/// include a folder id if the endpoint is filtered by one).
Future<T> cachedApiGet<T>(
  Dio dio,
  String path,
  String cacheKey,
  T Function(dynamic) onOk, {
  Map<String, dynamic>? queryParameters,
  Options? options,
}) async {
  try {
    final response = await dio.get(path, queryParameters: queryParameters, options: options);
    unawaited(OfflineCache.put(cacheKey, response.data));
    return onOk(response.data);
  } on DioException catch (e) {
    if (_isConnectivityFailure(e)) {
      final cached = await OfflineCache.get(cacheKey);
      if (cached != null) return onOk(cached);
    }
    throw ApiException.fromDioException(e);
  }
}
