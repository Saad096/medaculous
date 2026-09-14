import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';

/// Thin wrapper over backend/app/api/v1/legal.py — both routes are
/// unauthenticated, so this works even before the user has an account (the
/// registration screen's acceptance checkbox links to these).
class LegalApi {
  LegalApi(this._dio);

  final Dio _dio;

  Future<Uint8List> _downloadPdf(String path) async {
    try {
      final response = await _dio.get(
        path,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30)),
      );
      return Uint8List.fromList(response.data as List<int>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Uint8List> downloadTermsOfService() => _downloadPdf('/legal/terms');

  Future<Uint8List> downloadPrivacyPolicy() => _downloadPdf('/legal/privacy');
}
