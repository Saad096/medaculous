import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/offline_cache.dart';
import '../domain/osce.dart';

/// Thin wrapper over backend/app/api/v1/osce.py.
class OsceApi {
  OsceApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic) onOk) async {
    try {
      final response = await request();
      return onOk(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // Read-only reference content — available offline via the last-loaded
  // copy (owner feedback, 2026-09-14). See core/network/offline_cache.dart.
  Future<List<OsceStation>> listStations() {
    return cachedApiGet(
      _dio,
      '/osce/stations',
      'osce_stations',
      (data) => (data as List<dynamic>).map((e) => OsceStation.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> addFavorite(String stationId) {
    return _call(() => _dio.post('/osce/favorites/$stationId'), (_) {});
  }

  Future<void> removeFavorite(String stationId) {
    return _call(() => _dio.delete('/osce/favorites/$stationId'), (_) {});
  }

  Future<void> setStepProgress(String stepId, bool checked) {
    return _call(() => _dio.patch('/osce/steps/$stepId/progress', data: {'checked': checked}), (_) {});
  }

  Future<void> resetStationProgress(String stationId) {
    return _call(() => _dio.delete('/osce/stations/$stationId/progress'), (_) {});
  }
}
