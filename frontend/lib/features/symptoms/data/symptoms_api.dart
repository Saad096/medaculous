import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/symptom_check.dart';

/// Thin wrapper over backend/app/api/v1/symptoms.py.
class SymptomsApi {
  SymptomsApi(this._dio);

  final Dio _dio;

  /// The backend's generate_json() helper can retry once on a malformed LLM
  /// response, so a single check can take well past the app's default 20s
  /// receive timeout — this call gets its own longer budget. Verified
  /// on-device: one full check with a JSON retry took ~85s, so the budget
  /// must cover two sequential LLM calls, not one.
  Future<SymptomCheckResult> check({
    required List<String> symptoms,
    String? age,
    String? sex,
    String? duration,
  }) async {
    try {
      final response = await _dio.post(
        '/symptoms/check',
        data: {
          'symptoms': symptoms,
          if (age != null && age.isNotEmpty) 'age': age,
          if (sex != null && sex.isNotEmpty) 'sex': sex,
          if (duration != null && duration.isNotEmpty) 'duration': duration,
        },
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      return SymptomCheckResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
