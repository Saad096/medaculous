import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sketch_screen.dart';

/// Renders `image` embeds inserted by the note editor.
///
/// flutter_quill's core package (as opposed to the separate
/// `flutter_quill_extensions` package we deliberately did not pull in) does
/// not ship a default embed builder for images, so without this the editor
/// would show nothing where a picture was inserted. Images picked via
/// [ImagePicker] are stored inline as `data:` URIs (see
/// `note_editor_screen.dart`), so the common case is base64 decode +
/// [Image.memory]; network/file paths are handled too in case content is
/// ever authored another way.
class DataUriImageEmbedBuilder extends EmbedBuilder {
  const DataUriImageEmbedBuilder();

  // `Image.memory` keys Flutter's image cache off the MemoryImage's byte
  // list *by reference*, not by content — decoding the same data URI fresh
  // on every rebuild (which is what a plain base64Decode() call in build()
  // does) handed it a new Uint8List each time, so it was NEVER cache-hit and
  // re-decoded a full JPEG on every keystroke elsewhere in the note. That's
  // what caused the "blinking screen" and eventual crash once a note had a
  // real photo in it (owner report, 2026-08-17) — this cache keeps the same
  // Uint8List instance alive across rebuilds so the same image only ever
  // decodes once.
  static final Map<String, Uint8List> _decodedCache = {};

  @override
  String get key => BlockEmbed.imageType;

  @override
  String toPlainText(Embed node) => '[image]';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data as String;
    final image = _resolveImage(source);
    final widthPercent = _widthPercent(embedContext);

    // Plain, static widget tree — no LayoutBuilder, no interactive chrome
    // inside the document flow (that extra surface area inside the embed
    // was itself part of what made the old version unstable). Resizing now
    // lives in the full-screen viewer instead — see _openFullScreen.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        // Feature PDF, Notes fix #1: attached images must support zooming
        // with hand gestures — tap opens a full-screen pinch-to-zoom viewer.
        onTap: () => _openFullScreen(context, embedContext, source),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthPercent / 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: image,
            ),
          ),
        ),
      ),
    );
  }

  double _widthPercent(EmbedContext embedContext) {
    final raw = embedContext.node.style.attributes['style']?.value as String?;
    if (raw == null) return 100;
    for (final declaration in raw.split(';')) {
      final parts = declaration.split(':');
      if (parts.length == 2 && parts[0].trim() == 'width') {
        final value = parts[1].trim().replaceAll('%', '');
        return double.tryParse(value) ?? 100;
      }
    }
    return 100;
  }

  void _setWidth(EmbedContext embedContext, double percent) {
    final offset = embedContext.node.documentOffset;
    embedContext.controller.formatText(
      offset,
      1,
      Attribute.fromKeyValue('style', 'width: ${percent.round()}%;'),
    );
  }

  void _openFullScreen(
    BuildContext context,
    EmbedContext embedContext,
    String source,
  ) {
    final bytes = _dataUriBytes(source);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _FullScreenImageViewer(
          image: _resolveImage(source),
          bytes: bytes,
          canEdit: !embedContext.readOnly,
          initialWidthPercent: _widthPercent(embedContext),
          onResize: (pct) => _setWidth(embedContext, pct),
          onAnnotate: bytes == null
              ? null
              : () => _annotateImage(context, embedContext, bytes),
        ),
      ),
    );
  }

  Future<void> _annotateImage(
    BuildContext context,
    EmbedContext embedContext,
    Uint8List bytes,
  ) async {
    final annotated = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SketchScreen(background: bytes),
      ),
    );
    if (annotated == null || !context.mounted) return;

    // Replace this embed in place with the annotated copy so the note keeps
    // a single, updated version of the picture.
    final offset = embedContext.node.documentOffset;
    embedContext.controller.replaceText(
      offset,
      1,
      BlockEmbed.image('data:image/png;base64,${base64Encode(annotated)}'),
      TextSelection.collapsed(offset: offset + 1),
    );
    Navigator.of(context).pop(); // close the (now stale) fullscreen viewer
  }

  Uint8List? _dataUriBytes(String source) {
    final cached = _decodedCache[source];
    if (cached != null) return cached;
    if (!source.startsWith('data:')) return null;
    final commaIndex = source.indexOf(',');
    if (commaIndex == -1) return null;
    try {
      final bytes = base64Decode(source.substring(commaIndex + 1));
      _decodedCache[source] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _resolveImage(String source) {
    if (source.startsWith('data:')) {
      final bytes = _dataUriBytes(source);
      if (bytes == null) return const _BrokenImagePlaceholder();
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _BrokenImagePlaceholder(),
      );
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _BrokenImagePlaceholder(),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const _BrokenImagePlaceholder(),
    );
  }
}

/// Full-screen pinch-to-zoom viewer — also where resizing and annotating
/// live now, instead of always-visible "S/M/L" chips cluttering the note
/// itself (owner feedback, 2026-08-17: those "don't make sense" inline;
/// resize should feel like a deliberate editor tool).
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.image,
    required this.bytes,
    required this.canEdit,
    required this.initialWidthPercent,
    required this.onResize,
    required this.onAnnotate,
  });

  final Widget image;
  final Uint8List? bytes;
  final bool canEdit;
  final double initialWidthPercent;
  final ValueChanged<double> onResize;
  final VoidCallback? onAnnotate;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late double _widthPercent = widget.initialWidthPercent;
  bool _showResize = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Image'),
        actions: [
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.photo_size_select_large_outlined),
              tooltip: 'Resize',
              onPressed: () => setState(() => _showResize = !_showResize),
            ),
          if (widget.onAnnotate != null)
            IconButton(
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Annotate image',
              onPressed: widget.onAnnotate,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: widget.image,
              ),
            ),
          ),
          if (_showResize)
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.photo_size_select_small_outlined, color: Colors.white70, size: 18),
                      Expanded(
                        child: Slider(
                          value: _widthPercent,
                          min: 20,
                          max: 100,
                          divisions: 16,
                          label: '${_widthPercent.round()}%',
                          onChanged: (value) => setState(() => _widthPercent = value),
                          onChangeEnd: widget.onResize,
                        ),
                      ),
                      const Icon(Icons.photo_size_select_large_outlined, color: Colors.white70, size: 22),
                    ],
                  ),
                  Text(
                    'Size in note: ${_widthPercent.round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}
