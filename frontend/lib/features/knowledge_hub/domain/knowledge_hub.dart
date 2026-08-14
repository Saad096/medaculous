class PdfFolder {
  const PdfFolder({
    required this.id,
    required this.name,
    required this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;

  factory PdfFolder.fromJson(Map<String, dynamic> json) => PdfFolder(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parent_id'] as String?,
  );
}

class PdfDocument {
  const PdfDocument({
    required this.id,
    required this.folderId,
    required this.filename,
    required this.sizeBytes,
    required this.pageCount,
    required this.updatedAt,
    required this.title,
    required this.author,
    required this.contentPreview,
  });

  final String id;
  final String? folderId;
  final String filename;
  final int sizeBytes;
  final int pageCount;
  final DateTime updatedAt;

  /// Extracted once at upload from the PDF's own embedded metadata / first
  /// page of text (see backend _extract_pdf_metadata) — null for scanned or
  /// image-only PDFs, or any PDF uploaded before this field existed.
  final String? title;
  final String? author;
  final String? contentPreview;

  /// What to actually show as the document's name — most PDFs' embedded
  /// title metadata is missing or junk (e.g. "Microsoft Word - doc1"), so
  /// only prefer it when it looks like a real title.
  String get displayTitle =>
      (title != null && title!.trim().length > 3) ? title! : filename;

  factory PdfDocument.fromJson(Map<String, dynamic> json) => PdfDocument(
    id: json['id'] as String,
    folderId: json['folder_id'] as String?,
    filename: json['filename'] as String,
    sizeBytes: json['size_bytes'] as int,
    pageCount: json['page_count'] as int,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    title: json['title'] as String?,
    author: json['author'] as String?,
    contentPreview: json['content_preview'] as String?,
  );
}

/// A full-text content match from Azure AI Search (see backend
/// app/services/search.py) — distinct from filename matches, which
/// PdfDocument's own list-with-`q` already covers.
class PdfSearchHit {
  const PdfSearchHit({
    required this.pdfId,
    required this.filename,
    required this.pageNumber,
    required this.snippet,
  });

  final String pdfId;
  final String filename;
  final int? pageNumber;
  final String snippet;

  factory PdfSearchHit.fromJson(Map<String, dynamic> json) => PdfSearchHit(
    pdfId: json['pdf_id'] as String,
    filename: json['filename'] as String,
    pageNumber: json['page_number'] as int?,
    snippet: json['snippet'] as String,
  );
}

/// One entry of the document's embedded outline (table of contents),
/// flattened by the backend with a nesting [level] for indentation.
class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.page,
    required this.level,
  });

  final String title;
  final int page;
  final int level;

  factory PdfOutlineEntry.fromJson(Map<String, dynamic> json) =>
      PdfOutlineEntry(
        title: json['title'] as String,
        page: json['page'] as int,
        level: json['level'] as int,
      );
}

class PdfBookmark {
  const PdfBookmark({
    required this.id,
    required this.pdfId,
    required this.pageNumber,
    required this.label,
  });

  final String id;
  final String pdfId;
  final int pageNumber;
  final String label;

  factory PdfBookmark.fromJson(Map<String, dynamic> json) => PdfBookmark(
    id: json['id'] as String,
    pdfId: json['pdf_id'] as String,
    pageNumber: json['page_number'] as int,
    label: json['label'] as String,
  );
}

class NormalizedRect {
  const NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  factory NormalizedRect.fromJson(Map<String, dynamic> json) => NormalizedRect(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// MVP annotation scope: highlight and note only (OPEN_QUESTIONS.md) — the
/// legacy's freehand pen/shapes/stickers/image tools are cut.
class PdfAnnotation {
  const PdfAnnotation({
    required this.id,
    required this.pdfId,
    required this.pageNumber,
    required this.type,
    required this.color,
    required this.rects,
    required this.text,
    required this.note,
  });

  final String id;
  final String pdfId;
  final int pageNumber;
  final String type;
  final String color;
  final List<NormalizedRect> rects;
  final String text;
  final String note;

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) => PdfAnnotation(
    id: json['id'] as String,
    pdfId: json['pdf_id'] as String,
    pageNumber: json['page_number'] as int,
    type: json['type'] as String,
    color: json['color'] as String,
    rects: (json['rects'] as List<dynamic>)
        .map((e) => NormalizedRect.fromJson(e as Map<String, dynamic>))
        .toList(),
    text: json['text'] as String,
    note: json['note'] as String,
  );
}
