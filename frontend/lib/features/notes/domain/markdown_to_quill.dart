import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:markdown/markdown.dart' as md;

import 'note_content_codec.dart';

/// Converts the Markdown text Medaculous AI returns (headers, bold, bullet
/// lists, etc. — the same text the chat bubble renders via flutter_markdown,
/// see chat_screen.dart) into a proper Quill Delta note body.
///
/// Without this, saving an AI answer straight into `contentHtml` (a plain
/// markdown string) meant NoteContentCodec.decode had no Delta JSON to
/// parse, so it fell back to wrapping the *raw* markdown as one plain-text
/// paragraph — the note then showed literal '#' and '**' characters instead
/// of an actual heading and bold text (owner feedback, 2026-09-12).
String markdownToNoteContent(String markdown) {
  final blocks = md.Document().parseLines(markdown.split('\n'));
  final ops = <Map<String, dynamic>>[];
  for (final block in blocks) {
    _renderBlock(block, ops);
  }
  if (ops.isEmpty) {
    ops.add({'insert': '\n'});
  }
  return NoteContentCodec.encode(Document.fromJson(ops));
}

void _renderBlock(md.Node node, List<Map<String, dynamic>> ops) {
  if (node is md.Text) {
    // A bare text node at block level (rare, but package:markdown allows
    // it) — treat as its own paragraph rather than dropping it.
    if (node.text.trim().isEmpty) return;
    ops.add({'insert': node.text});
    ops.add({'insert': '\n'});
    return;
  }
  if (node is! md.Element) return;

  switch (node.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      // Quill's own header attribute only styles levels 1-3 distinctly —
      // deeper markdown headings (##### etc, uncommon in AI answers anyway)
      // collapse to the smallest heading rather than being dropped.
      final level = int.parse(node.tag.substring(1)).clamp(1, 3);
      _renderInlineChildren(node, ops, null);
      ops.add({
        'insert': '\n',
        'attributes': {'header': level},
      });
    case 'ul':
      _renderListItems(node, ops, ordered: false);
    case 'ol':
      _renderListItems(node, ops, ordered: true);
    case 'blockquote':
      for (final child in node.children ?? const <md.Node>[]) {
        _renderBlock(child, ops);
      }
    case 'hr':
      ops.add({'insert': '\n'});
    case 'pre':
      ops.add({'insert': node.textContent});
      ops.add({
        'insert': '\n',
        'attributes': {'code-block': true},
      });
    case 'p':
    default:
      _renderInlineChildren(node, ops, null);
      ops.add({'insert': '\n'});
  }
}

void _renderListItems(md.Element list, List<Map<String, dynamic>> ops, {required bool ordered}) {
  for (final child in list.children ?? const <md.Node>[]) {
    if (child is! md.Element || child.tag != 'li') continue;
    // A list item's own children are usually a single implicit paragraph
    // (or bare inline nodes for a "tight" list) — either way, only the
    // inline content matters here since the list-ness itself is carried as
    // a Quill line attribute, not a nested block.
    for (final grandchild in child.children ?? const <md.Node>[]) {
      if (grandchild is md.Element && grandchild.tag == 'p') {
        _renderInlineChildren(grandchild, ops, null);
      } else {
        _renderInline(grandchild, ops, null);
      }
    }
    ops.add({
      'insert': '\n',
      'attributes': {'list': ordered ? 'ordered' : 'bullet'},
    });
  }
}

void _renderInlineChildren(
  md.Element node,
  List<Map<String, dynamic>> ops,
  Map<String, dynamic>? inherited,
) {
  for (final child in node.children ?? const <md.Node>[]) {
    _renderInline(child, ops, inherited);
  }
}

void _renderInline(
  md.Node node,
  List<Map<String, dynamic>> ops,
  Map<String, dynamic>? inherited,
) {
  if (node is md.Text) {
    if (node.text.isEmpty) return;
    ops.add(inherited == null ? {'insert': node.text} : {'insert': node.text, 'attributes': inherited});
    return;
  }
  if (node is! md.Element) return;

  if (node.tag == 'br') {
    ops.add({'insert': '\n'});
    return;
  }

  var attrs = inherited;
  switch (node.tag) {
    case 'strong':
      attrs = {...?attrs, 'bold': true};
    case 'em':
      attrs = {...?attrs, 'italic': true};
    case 'code':
      attrs = {...?attrs, 'code': true};
    case 'del':
      attrs = {...?attrs, 'strike': true};
    case 'a':
      final href = node.attributes['href'];
      if (href != null) attrs = {...?attrs, 'link': href};
  }
  for (final child in node.children ?? const <md.Node>[]) {
    _renderInline(child, ops, attrs);
  }
}
