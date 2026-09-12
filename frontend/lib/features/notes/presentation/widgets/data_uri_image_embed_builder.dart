import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_colors.dart';
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

  // Which image (keyed by its own data URI, unique per embed in practice) is
  // currently showing its resize/delete handles — owner feedback,
  // 2026-09-11: tapping an image should select it for resize/delete without
  // the keyboard popping up, and tapping anywhere else in the note should
  // deselect it and hand focus back to typing. A single shared notifier (at
  // most one image is ever "selected" at a time) lets note_editor_screen.dart
  // clear it the moment the editor's own text focus node gains focus, which
  // is exactly the "tapped elsewhere" signal — see its FocusNode listener.
  static final ValueNotifier<String?> selectedKey = ValueNotifier<String?>(null);

  @override
  String get key => BlockEmbed.imageType;

  @override
  String toPlainText(Embed node) => '[image]';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data as String;
    final image = _resolveImage(source);
    final widthPercent = _widthPercent(embedContext);

    return Padding(
      // Taller than a plain 8px gap on both sides — a tight gap let the text
      // caret on the line right after the image render as if it were
      // overlapping the image's own bottom edge instead of clearly below it
      // (owner feedback, 2026-09-11: cursor "half under" the image).
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: _ResizableImageEmbed(
        embedKey: source,
        image: image,
        initialWidthPercent: widthPercent,
        canEdit: !embedContext.readOnly,
        onResize: (pct) => _setWidth(embedContext, pct),
        onDelete: () => _deleteEmbed(embedContext),
        onLongPress: () => _openFullScreen(context, embedContext, source),
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

  void _deleteEmbed(EmbedContext embedContext) {
    final offset = embedContext.node.documentOffset;
    selectedKey.value = null;
    embedContext.controller.replaceText(offset, 1, '', TextSelection.collapsed(offset: offset));
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
          canEdit: !embedContext.readOnly,
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

/// The inline, selectable image — plain by default; tapping it shows a
/// bordered selection frame with a delete button (top-right) and two drag
/// handles (bottom corners) for resizing, matching the owner-supplied
/// reference design (2026-09-11) instead of the old always-visible S/M/L
/// chips or a hidden-away fullscreen slider.
class _ResizableImageEmbed extends StatefulWidget {
  const _ResizableImageEmbed({
    required this.embedKey,
    required this.image,
    required this.initialWidthPercent,
    required this.canEdit,
    required this.onResize,
    required this.onDelete,
    required this.onLongPress,
  });

  final String embedKey;
  final Widget image;
  final double initialWidthPercent;
  final bool canEdit;
  final ValueChanged<double> onResize;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  State<_ResizableImageEmbed> createState() => _ResizableImageEmbedState();
}

class _ResizableImageEmbedState extends State<_ResizableImageEmbed> {
  late double _widthPercent = widget.initialWidthPercent;

  @override
  void initState() {
    super.initState();
    DataUriImageEmbedBuilder.selectedKey.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    DataUriImageEmbedBuilder.selectedKey.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  bool get _isSelected => DataUriImageEmbedBuilder.selectedKey.value == widget.embedKey;

  void _select() {
    if (!widget.canEdit) return;
    // Dismissing the keyboard here (rather than only on delete/resize) is
    // the actual fix for "keyboard shouldn't pop up while I'm resizing" —
    // selecting the image is the moment that used to leave the text field
    // focused underneath the newly-shown handles.
    FocusScope.of(context).unfocus();
    DataUriImageEmbedBuilder.selectedKey.value = widget.embedKey;
  }

  void _onHandleDrag(DragUpdateDetails details, double totalWidth) {
    if (totalWidth <= 0) return;
    final deltaPercent = (details.delta.dx / totalWidth) * 100;
    setState(() => _widthPercent = (_widthPercent + deltaPercent).clamp(20.0, 100.0));
  }

  void _onHandleDragEnd() => widget.onResize(_widthPercent);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final imageWidth = totalWidth * (_widthPercent / 100);
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _select,
            onLongPress: widget.onLongPress,
            child: SizedBox(
              // Extra margin around the actual image so the handles (which
              // sit half outside the image's own edge) have room without
              // getting clipped by the document's own layout.
              width: imageWidth + 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: SizedBox(width: imageWidth, child: widget.image),
                    ),
                  ),
                  if (_isSelected && widget.canEdit) ...[
                    Positioned(
                      left: 10,
                      top: 10,
                      width: imageWidth,
                      bottom: 10,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 2),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: widget.onDelete,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onPanUpdate: (details) => _onHandleDrag(details, totalWidth),
                        onPanEnd: (_) => _onHandleDragEnd(),
                        child: const _ResizeHandle(),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onPanUpdate: (details) => _onHandleDrag(details, totalWidth),
                        onPanEnd: (_) => _onHandleDragEnd(),
                        child: const _ResizeHandle(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
      ),
    );
  }
}

/// Full-screen pinch-to-zoom viewer, reached with a long-press — resizing
/// now happens inline (see _ResizableImageEmbed), so this is just for
/// getting a closer look and, if the image has one, re-opening the sketch
/// tool on top of it.
class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({
    required this.image,
    required this.canEdit,
    required this.onAnnotate,
  });

  final Widget image;
  final bool canEdit;
  final VoidCallback? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Image'),
        actions: [
          if (canEdit && onAnnotate != null)
            IconButton(
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Annotate image',
              onPressed: onAnnotate,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: image,
        ),
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
