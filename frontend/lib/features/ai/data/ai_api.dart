import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/conversation.dart';

/// Thin wrapper over backend/app/api/v1/ai.py.
class AiApi {
  AiApi(this._dio);

  final Dio _dio;

  /// The response body is raw chunked text, not JSON — the first line is
  /// `__conversation_id__:<id>` (see backend's `event_stream()`), everything
  /// after is assistant text as it's generated. Buffers only until that
  /// first newline is found, since a byte chunk boundary isn't guaranteed to
  /// land on a line boundary.
  Stream<ChatStreamEvent> streamChat({
    required String message,
    required ChatMode mode,
    String? conversationId,
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/ai/chat',
        data: {
          'message': message,
          'mode': mode.apiValue,
          'conversation_id': ?conversationId,
        },
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }

    var buffer = '';
    var headerConsumed = false;
    await for (final bytes in response.data!.stream) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (headerConsumed) {
        yield ChatStreamDelta(text);
        continue;
      }
      buffer += text;
      final newlineIndex = buffer.indexOf('\n');
      if (newlineIndex == -1) continue;
      headerConsumed = true;
      final id = buffer
          .substring(0, newlineIndex)
          .replaceFirst('__conversation_id__:', '');
      yield ChatStreamStarted(id);
      final rest = buffer.substring(newlineIndex + 1);
      if (rest.isNotEmpty) yield ChatStreamDelta(rest);
    }
  }

  Future<List<ConversationSummary>> listConversations() async {
    try {
      final response = await _dio.get<List<dynamic>>('/ai/conversations');
      return response.data!
          .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<ConversationDetail> getConversation(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/ai/conversations/$id',
      );
      return ConversationDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> renameConversation(String id, String title) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/ai/conversations/$id',
        data: {'title': title},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<bool> toggleSave(String id) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/ai/conversations/$id/save',
      );
      return response.data!['is_saved'] as bool;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteConversation(String id) async {
    try {
      await _dio.delete<void>('/ai/conversations/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
