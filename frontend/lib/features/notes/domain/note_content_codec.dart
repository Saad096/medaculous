import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' show Document;

/// Encodes/decodes the rich-text body persisted in [Note.contentHtml].
///
/// The backend stores this as an opaque string column, so there is no schema
/// migration involved here — the client just chooses to put Quill's Delta
/// JSON in that string instead of plain text. Notes created before this
/// change (or anything that isn't valid Delta JSON, e.g. a future manual
/// edit) are treated as a single plain-text paragraph so old content is never
/// lost or garbled.
class NoteContentCodec {
  NoteContentCodec._();

  static Document decode(String raw) {
    if (raw.isEmpty) return Document();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return Document.fromJson(decoded);
      }
    } catch (_) {
      // Not JSON at all — fall through to the plain-text wrap below.
    }
    return Document.fromJson([
      {'insert': '$raw\n'},
    ]);
  }

  static String encode(Document document) {
    return jsonEncode(document.toDelta().toJson());
  }

  /// Short plain-text preview for list rows (strips formatting/images).
  static String previewText(String raw) {
    final document = decode(raw);
    final text = document
        .toPlainText()
        .replaceAll(
          String.fromCharCode(0xFFFC),
          '',
        ) // object-replacement char for embeds (images)
        .replaceAll('\n', ' ')
        .trim();
    return text;
  }

  /// All inline image sources (data URIs) embedded in a note body, in
  /// document order — used to surface a note's clinical images without
  /// opening the editor (disease topic "Clinical Images" list).
  static List<String> imageSources(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final op in decoded)
          if (op is Map<String, dynamic> &&
              op['insert'] is Map<String, dynamic> &&
              (op['insert'] as Map<String, dynamic>)['image'] is String)
            (op['insert'] as Map<String, dynamic>)['image'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }
}
