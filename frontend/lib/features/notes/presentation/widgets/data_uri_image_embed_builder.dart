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

  @override
  String get key => BlockEmbed.imageType;

  @override
  String toPlainText(Embed node) => '[image]';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data as String;
    final image = _resolveImage(source);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        // Feature PDF, Notes fix #1: attached images must support zooming
        // with hand gestures — tap opens a full-screen pinch-to-zoom viewer.
        onTap: () => _openFullScreen(context, embedContext, image, source),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: image,
        ),
      ),
    );
  }

  void _openFullScreen(
    BuildContext context,
    EmbedContext embedContext,
    Widget image,
    String source,
  ) {
    final bytes = _dataUriBytes(source);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Image'),
            actions: [
              // Freehand annotation over the opened image (feature request:
              // "add the pen sign, hand sketching, even when image open").
              // Only for inline data-URI images in an editable note.
              if (bytes != null && !embedContext.readOnly)
                IconButton(
                  icon: const Icon(Icons.draw_outlined),
                  tooltip: 'Annotate image',
                  onPressed: () =>
                      _annotateImage(context, embedContext, bytes),
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
    if (!source.startsWith('data:')) return null;
    final commaIndex = source.indexOf(',');
    if (commaIndex == -1) return null;
    try {
      return base64Decode(source.substring(commaIndex + 1));
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
