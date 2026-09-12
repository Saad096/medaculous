class Folder {
  const Folder({required this.id, required this.name, required this.parentId});

  final String id;
  final String name;
  final String? parentId;

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parent_id'] as String?,
  );
}

class Note {
  const Note({
    required this.id,
    required this.folderId,
    required this.title,
    required this.contentHtml,
    required this.isPinned,
    required this.sortOrder,
    required this.updatedAt,
  });

  final String id;
  final String? folderId;
  final String title;
  final String contentHtml;
  final bool isPinned;
  final int sortOrder;
  final DateTime updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    folderId: json['folder_id'] as String?,
    title: json['title'] as String,
    contentHtml: json['content_html'] as String,
    isPinned: json['is_pinned'] as bool,
    sortOrder: json['sort_order'] as int? ?? 0,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
