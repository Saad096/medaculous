import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/offline_cache.dart';
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

  // Available offline via the last-loaded copy — owner feedback, 2026-09-14.
  // Only reads: creating/editing a note still requires being online. See
  // core/network/offline_cache.dart.
  Future<List<Folder>> listFolders() {
    return cachedApiGet(
      _dio,
      '/notes/folders',
      'notes_folders',
      (data) => (data as List<dynamic>)
          .map((e) => Folder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Folder> createFolder({required String name, String? parentId}) {
    return _call(
      () => _dio.post(
        '/notes/folders',
        data: {'name': name, 'parent_id': ?parentId},
      ),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Folder> updateFolder(String id, {String? name, String? parentId}) {
    return _call(
      () => _dio.patch(
        '/notes/folders/$id',
        data: {
          'name': ?name,
          'parent_id': ?parentId,
        },
      ),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteFolder(String id) {
    return _call(() => _dio.delete('/notes/folders/$id'), (_) {});
  }

  /// Unlike [updateFolder] (which only ever touches parent_id when a
  /// non-null value is given, via the `?` map-entry shorthand), this always
  /// sends parent_id explicitly — including null, to move a folder back to
  /// top level — since "move" is exactly what this call means to do.
  Future<Folder> moveFolder(String id, {required String? newParentId}) {
    return _call(
      () => _dio.patch('/notes/folders/$id', data: {'parent_id': newParentId}),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<Folder>> listTrashedFolders() {
    return _call(
      () => _dio.get('/notes/folders/trash'),
      (data) => (data as List<dynamic>)
          .map((e) => Folder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Folder> restoreFolder(String id) {
    return _call(
      () => _dio.post('/notes/folders/$id/restore'),
      (data) => Folder.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<Note>> searchNotes(String query) {
    return _call(
      () => _dio.get('/notes/search', queryParameters: {'q': query}),
      (data) => (data as List<dynamic>)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Note>> listNotes({String? folderId}) {
    return cachedApiGet(
      _dio,
      '/notes',
      'notes_list_${folderId ?? 'all'}',
      (data) => (data as List<dynamic>)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList(),
      queryParameters: folderId != null ? {'folder_id': folderId} : null,
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
          'folder_id': ?folderId,
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
          'title': ?title,
          'content_html': ?contentHtml,
          'folder_id': ?folderId,
          'is_pinned': ?isPinned,
        },
      ),
      (data) => Note.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Unlike [updateNote] (which only ever touches folder_id when a non-null
  /// value is given, via the `?` map-entry shorthand), this always sends
  /// folder_id explicitly — including null, to move a note back to "All
  /// Notes" — since "move" is exactly what this call means to do.
  Future<Note> moveNote(String id, {required String? newFolderId}) {
    return _call(
      () => _dio.patch('/notes/$id', data: {'folder_id': newFolderId}),
      (data) => Note.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Persists the drag-to-reorder position for the Custom sort mode —
  /// [orderedIds] is exactly the list currently on screen (one folder, or
  /// "All Notes"), in its new order.
  Future<void> reorderNotes(List<String> orderedIds) {
    return _call(
      () => _dio.patch('/notes/reorder', data: {'note_ids': orderedIds}),
      (_) {},
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
