import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/offline_cache.dart';
import '../domain/formulary.dart';

/// Thin wrapper over backend/app/api/v1/formulary.py.
class FormularyApi {
  FormularyApi(this._dio);

  final Dio _dio;

  // Read-only reference content — available offline via the last-loaded
  // copy (owner feedback, 2026-09-14). See core/network/offline_cache.dart.
  Future<FormularyTree> getTree() {
    return cachedApiGet(
      _dio,
      '/formulary/tree',
      'formulary_tree',
      (data) => parseFormularyTree(data as Map<String, dynamic>),
    );
  }

  Future<DrugProfile> getDrug(String id) {
    return cachedApiGet(
      _dio,
      '/formulary/drugs/$id',
      'formulary_drug_$id',
      (data) => DrugProfile.fromJson(data as Map<String, dynamic>),
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );
  }

  /// Regenerates every content field for an already-curated drug via AI —
  /// the "Enhance Profile with AI" button on the detail screen.
  Future<DrugProfile> enhanceProfile(String id) async {
    try {
      final response = await _dio.post(
        '/formulary/drugs/$id/enhance',
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      return DrugProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<SearchOrCreateResult> searchOrCreate(String genericName) async {
    try {
      final response = await _dio.post(
        '/formulary/search-or-create',
        data: {'generic_name': genericName},
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      return SearchOrCreateResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
