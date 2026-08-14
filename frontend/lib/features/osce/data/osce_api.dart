import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
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

  Future<List<OsceStation>> listStations() {
    return _call(
      () => _dio.get('/osce/stations'),
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
