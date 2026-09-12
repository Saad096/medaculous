import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/formulary.dart';

/// Thin wrapper over backend/app/api/v1/formulary.py.
class FormularyApi {
  FormularyApi(this._dio);

  final Dio _dio;

  Future<FormularyTree> getTree() async {
    try {
      final response = await _dio.get('/formulary/tree');
      return parseFormularyTree(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<DrugProfile> getDrug(String id) async {
    try {
      final response = await _dio.get(
        '/formulary/drugs/$id',
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      return DrugProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
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
