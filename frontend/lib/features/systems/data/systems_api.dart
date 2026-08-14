import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/disease.dart';

/// Thin wrapper over backend/app/api/v1/diseases.py.
class SystemsApi {
  SystemsApi(this._dio);

  final Dio _dio;

  Future<T> _call<T>(
    Future<Response> Function() request,
    T Function(dynamic) onOk,
  ) async {
    try {
      final response = await request();
      return onOk(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<MedicalSystem>> listSystems() {
    return _call(
      () => _dio.get('/systems'),
      (data) => (data as List<dynamic>)
          .map((e) => MedicalSystem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<DiseaseSummary>> listDiseases(String systemId) {
    return _call(
      () => _dio.get('/systems/$systemId/diseases'),
      (data) => (data as List<dynamic>)
          .map((e) => DiseaseSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<DiseaseSummary>> searchDiseases(String query) {
    return _call(
      () => _dio.get('/diseases/search', queryParameters: {'q': query}),
      (data) => (data as List<dynamic>)
          .map((e) => DiseaseSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<DiseaseDetail> getDisease(String diseaseId) {
    return _call(
      () => _dio.get('/diseases/$diseaseId'),
      (data) => DiseaseDetail.fromJson(data as Map<String, dynamic>),
    );
  }
}
