import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/offline_cache.dart';
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

  // Read-only reference content — available offline via the last-loaded
  // copy (owner feedback, 2026-09-14). See core/network/offline_cache.dart.
  Future<List<MedicalSystem>> listSystems() {
    return cachedApiGet(
      _dio,
      '/systems',
      'systems_list',
      (data) => (data as List<dynamic>)
          .map((e) => MedicalSystem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<DiseaseSummary>> listDiseases(String systemId) {
    return cachedApiGet(
      _dio,
      '/systems/$systemId/diseases',
      'systems_diseases_$systemId',
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
    return cachedApiGet(
      _dio,
      '/diseases/$diseaseId',
      'disease_detail_$diseaseId',
      (data) => DiseaseDetail.fromJson(data as Map<String, dynamic>),
    );
  }

  /// The single private note attached to this disease topic, or null if the
  /// user hasn't written one yet. Deliberately separate from the general
  /// Notes feature — see backend app.models.disease.DiseaseNote.
  Future<String?> getDiseaseNote(String diseaseId) {
    return _call(
      () => _dio.get('/diseases/$diseaseId/note'),
      (data) => data == null ? null : (data as Map<String, dynamic>)['content_html'] as String,
    );
  }

  /// Creates or replaces this disease's single note (upsert) — there is
  /// only ever one per disease per user.
  Future<void> saveDiseaseNote(String diseaseId, String contentHtml) {
    return _call(
      () => _dio.put('/diseases/$diseaseId/note', data: {'content_html': contentHtml}),
      (_) {},
    );
  }
}
