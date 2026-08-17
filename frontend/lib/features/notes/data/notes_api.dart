import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/note.dart';

/// Thin wrapper over backend/app/api/v1/notes.py.
class NotesApi {
  NotesApi(this._dio);

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

  Future<List<Folder>> listFolders() {
    return _call(
      () => _dio.get('/notes/folders'),
      (data) => (data as List<dynamic>)
          .map((e) => Folder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Folder> createFolder({required String name, String? parentId}) {
    return _call(
      () => _dio.post(
        '/notes/folders',
        data: {'name': name, if (parentId != null) 'parent_id': parentId},
      ),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Folder> updateFolder(String id, {String? name, String? parentId}) {
    return _call(
      () => _dio.patch(
        '/notes/folders/$id',
        data: {
          if (name != null) 'name': name,
          if (parentId != null) 'parent_id': parentId,
        },
      ),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteFolder(String id) {
    return _call(() => _dio.delete('/notes/folders/$id'), (_) {});
  }

  Future<List<Note>> listNotes({String? folderId}) {
    return _call(
      () => _dio.get(
        '/notes',
        queryParameters: folderId != null ? {'folder_id': folderId} : null,
      ),
      (data) => (data as List<dynamic>)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Note>> listTrash() {
    return _call(
      () => _dio.get('/notes/trash'),
      (data) => (data as List<dynamic>)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> emptyTrash() {
    return _call(() => _dio.delete('/notes/trash'), (_) {});
  }

  Future<Note> createNote({
    String title = '',
    String contentHtml = '',
    String? folderId,
  }) {
    return _call(
      () => _dio.post(
        '/notes',
        data: {
          'title': title,
          'content_html': contentHtml,
          if (folderId != null) 'folder_id': folderId,
        },
      ),
      (data) => Note.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Note> updateNote(
    String id, {
    String? title,
    String? contentHtml,
    String? folderId,
    bool? isPinned,
  }) {
    return _call(
      () => _dio.patch(
        '/notes/$id',
        data: {
          if (title != null) 'title': title,
          if (contentHtml != null) 'content_html': contentHtml,
          if (folderId != null) 'folder_id': folderId,
          if (isPinned != null) 'is_pinned': isPinned,
        },
      ),
      (data) => Note.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteNote(String id) {
    return _call(() => _dio.delete('/notes/$id'), (_) {});
  }

  Future<Note> restoreNote(String id) {
    return _call(
      () => _dio.post('/notes/$id/restore'),
      (data) => Note.fromJson(data as Map<String, dynamic>),
    );
  }
}
