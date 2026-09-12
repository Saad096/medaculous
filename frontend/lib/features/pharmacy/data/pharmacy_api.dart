import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/pharmacy.dart';

/// Thin wrapper over backend/app/api/v1/pharmacy.py.
class PharmacyApi {
  PharmacyApi(this._dio);

  final Dio _dio;

  Future<RecommendationResult> getRecommendations({
    required String symptoms,
    String? age,
    String? sex,
    String? weight,
    String? pregnancy,
    String? breastfeeding,
    String? allergies,
    String? chronicDiseases,
    String? renalImpairment,
    String? hepaticImpairment,
    String country = 'Pakistan',
  }) async {
    try {
      final response = await _dio.post(
        '/pharmacy/recommendations',
        data: {
          'symptoms': symptoms,
          if (age != null && age.isNotEmpty) 'age': age,
          if (sex != null && sex.isNotEmpty) 'sex': sex,
          if (weight != null && weight.isNotEmpty) 'weight': weight,
          if (pregnancy != null && pregnancy.isNotEmpty) 'pregnancy': pregnancy,
          if (breastfeeding != null && breastfeeding.isNotEmpty) 'breastfeeding': breastfeeding,
          if (allergies != null && allergies.isNotEmpty) 'allergies': allergies,
          if (chronicDiseases != null && chronicDiseases.isNotEmpty) 'chronic_diseases': chronicDiseases,
          if (renalImpairment != null && renalImpairment.isNotEmpty) 'renal_impairment': renalImpairment,
          if (hepaticImpairment != null && hepaticImpairment.isNotEmpty) 'hepatic_impairment': hepaticImpairment,
          'country': country,
        },
        // Raised twice now: 180s, then 280s, both still hit live (2026-09-11)
        // — a query whose first attempt truncates retries with double the
        // token budget, and that retry can land as high as ~43k tokens for
        // a genuinely broad case, which itself takes minutes to generate
        // regardless of network conditions. This has to be long enough to
        // outlast the *slowest realistic* two-call sequence rather than a
        // typical one, or a perfectly healthy in-progress request keeps
        // surfacing as a false "can't reach server" error. Matches the
        // review button's own progress-bar window (_estimatedDuration in
        // drug_recommendations_screen.dart), which is built to wait this
        // long without ever falsely claiming completion.
        options: Options(receiveTimeout: const Duration(minutes: 8)),
      );
      return RecommendationResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<InteractionResult> checkInteractions({required String drugA, required String drugB}) async {
    try {
      final response = await _dio.post(
        '/pharmacy/check-interactions',
        data: {'drug_a': drugA, 'drug_b': drugB},
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      return InteractionResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Substitute>> findSubstitutes({required String targetMed, String country = 'Pakistan'}) async {
    try {
      final response = await _dio.post(
        '/pharmacy/find-substitutes',
        data: {'target_med': targetMed, 'country': country},
        options: Options(receiveTimeout: const Duration(seconds: 150)),
      );
      final data = response.data as Map<String, dynamic>;
      return (data['substitutes'] as List<dynamic>).map((e) => Substitute.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<FavoriteDrug>> listFavorites() async {
    try {
      final response = await _dio.get('/pharmacy/favorites');
      return (response.data as List<dynamic>).map((e) => FavoriteDrug.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<FavoriteDrug> addFavorite(Medication medication) async {
    try {
      final response = await _dio.post('/pharmacy/favorites', data: {'medication': medication.toJson()});
      return FavoriteDrug.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> removeFavorite(String id) async {
    try {
      await _dio.delete('/pharmacy/favorites/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
