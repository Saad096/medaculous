import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/knowledge_hub.dart';

/// Thin wrapper over backend/app/api/v1/knowledge_hub.py.
class KnowledgeHubApi {
  KnowledgeHubApi(this._dio);

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

  Future<List<PdfFolder>> listFolders() {
    return _call(
      () => _dio.get('/knowledge-hub/folders'),
      (data) => (data as List<dynamic>)
          .map((e) => PdfFolder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<PdfFolder> createFolder({required String name, String? parentId}) {
    return _call(
      () => _dio.post(
        '/knowledge-hub/folders',
        data: {'name': name, if (parentId != null) 'parent_id': parentId},
      ),
      (data) => PdfFolder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteFolder(String id) {
    return _call(() => _dio.delete('/knowledge-hub/folders/$id'), (_) {});
  }

  Future<List<PdfDocument>> listPdfs({String? folderId, String? q}) {
    return _call(
      () => _dio.get(
        '/knowledge-hub/pdfs',
        queryParameters: {
          if (folderId != null) 'folder_id': folderId,
          if (q != null && q.isNotEmpty) 'q': q,
        },
      ),
      (data) => (data as List<dynamic>)
          .map((e) => PdfDocument.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Full-text search *inside* PDF content — separate from listPdfs' `q`
  /// param, which only matches filenames.
  Future<List<PdfSearchHit>> searchContent(String query) {
    return _call(
      () => _dio.get('/knowledge-hub/search', queryParameters: {'q': query}),
      (data) => (data as List<dynamic>)
          .map((e) => PdfSearchHit.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<PdfDocument> uploadPdf({
    required String filePath,
    required String filename,
    String? folderId,
  }) {
    return _call(
      () => _dio.post(
        '/knowledge-hub/pdfs',
        data: FormData.fromMap({
          'file': MultipartFile.fromFileSync(
            filePath,
            filename: filename,
            contentType: DioMediaType('application', 'pdf'),
          ),
        }),
        queryParameters: {if (folderId != null) 'folder_id': folderId},
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      ),
      (data) => PdfDocument.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Uint8List> downloadPdfBytes(String pdfId) {
    return _call(
      () => _dio.get(
        '/knowledge-hub/pdfs/$pdfId/file',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      ),
      (data) => Uint8List.fromList(data as List<int>),
    );
  }

  /// Document outline (table of contents) embedded in the PDF, flattened
  /// with nesting levels. Empty when the PDF has no outline.
  Future<List<PdfOutlineEntry>> getOutline(String pdfId) {
    return _call(
      () => _dio.get('/knowledge-hub/pdfs/$pdfId/outline'),
      (data) => (data as List<dynamic>)
          .map((e) => PdfOutlineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<PdfDocument> renamePdf(String id, String filename) {
    return _call(
      () => _dio.patch('/knowledge-hub/pdfs/$id', data: {'filename': filename}),
      (data) => PdfDocument.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<PdfDocument> movePdf(String id, String? folderId) {
    return _call(
      () => _dio.patch(
        '/knowledge-hub/pdfs/$id',
        data: folderId == null
            ? {'clear_folder': true}
            : {'folder_id': folderId},
      ),
      (data) => PdfDocument.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deletePdf(String id) {
    return _call(() => _dio.delete('/knowledge-hub/pdfs/$id'), (_) {});
  }

  Future<List<PdfBookmark>> listBookmarks(String pdfId) {
    return _call(
      () => _dio.get('/knowledge-hub/pdfs/$pdfId/bookmarks'),
      (data) => (data as List<dynamic>)
          .map((e) => PdfBookmark.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<PdfBookmark> addBookmark(
    String pdfId, {
    required int pageNumber,
    String label = '',
  }) {
    return _call(
      () => _dio.post(
        '/knowledge-hub/pdfs/$pdfId/bookmarks',
        data: {'page_number': pageNumber, 'label': label},
      ),
      (data) => PdfBookmark.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteBookmark(String id) {
    return _call(() => _dio.delete('/knowledge-hub/bookmarks/$id'), (_) {});
  }

  Future<List<PdfAnnotation>> listAnnotations(String pdfId) {
    return _call(
      () => _dio.get('/knowledge-hub/pdfs/$pdfId/annotations'),
      (data) => (data as List<dynamic>)
          .map((e) => PdfAnnotation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<PdfAnnotation> addAnnotation(
    String pdfId, {
    required int pageNumber,
    required String type,
    String color = '#FFEB3B',
    List<NormalizedRect> rects = const [],
    String text = '',
    String note = '',
  }) {
    return _call(
      () => _dio.post(
        '/knowledge-hub/pdfs/$pdfId/annotations',
        data: {
          'page_number': pageNumber,
          'type': type,
          'color': color,
          'rects': rects.map((r) => r.toJson()).toList(),
          'text': text,
          'note': note,
        },
      ),
      (data) => PdfAnnotation.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteAnnotation(String id) {
    return _call(() => _dio.delete('/knowledge-hub/annotations/$id'), (_) {});
  }
}
