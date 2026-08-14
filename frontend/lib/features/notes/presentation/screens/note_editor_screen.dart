import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sketch_screen.dart';
import '../../domain/note.dart';
import '../../domain/note_content_codec.dart';
import '../providers/notes_providers.dart';
import '../widgets/data_uri_image_embed_builder.dart';

/// Rich-text note editor built on flutter_quill. Body is persisted as Quill
/// Delta JSON into the existing `contentHtml` string column (see
/// NoteContentCodec) — no backend change needed, it's an opaque string.
///
/// Autosaves on a short debounce after each edit rather than requiring an
/// explicit save action, same as before.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.note,
    this.initialFolderId,
    this.folderBreadcrumb,
  });

  final Note? note;

  /// Folder a brand-new note should be filed into (e.g. a disease's matching
  /// specialty folder). Ignored when [note] is non-null — an existing note
  /// keeps its own folder.
  final String? initialFolderId;

  /// Optional label shown above the title (e.g. "Cardiology") when opened
  /// from a disease topic, mirroring the reference UI's folder breadcrumb.
  final String? folderBreadcrumb;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  String? _noteId;
  String? _folderId;
  Timer? _debounce;
  bool _isSaving = false;
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _noteId = widget.note?.id;
    _folderId = widget.note?.folderId ?? widget.initialFolderId;

    final document = NoteContentCodec.decode(widget.note?.contentHtml ?? '');
    _quillController = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changesSub = _quillController.changes.listen((_) => _scheduleSave());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changesSub?.cancel();
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _quillController.document.isEmpty()) return;
    final content = NoteContentCodec.encode(_quillController.document);

    setState(() => _isSaving = true);
    final api = ref.read(notesApiProvider);
    if (_noteId == null) {
      final created = await api.createNote(
        title: title,
        contentHtml: content,
        folderId: _folderId,
      );
      _noteId = created.id;
    } else {
      await api.updateNote(_noteId!, title: title, contentHtml: content);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _handleBack() async {
    _debounce?.cancel();
    await _save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickAndInsertImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    _insertImageEmbed(
      'data:${_mimeTypeFor(picked.path)};base64,${base64Encode(bytes)}',
    );
  }

  /// Feature PDF, Notes: "Create freehand sketches and annotations directly
  /// within notes" — opens the drawing canvas and embeds the result as an
  /// inline image, same storage path as photos.
  Future<void> _openSketch() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SketchScreen(),
      ),
    );
    if (bytes == null || !mounted) return;
    _insertImageEmbed('data:image/png;base64,${base64Encode(bytes)}');
  }

  void _insertImageEmbed(String dataUri) {
    final selection = _quillController.selection;
    final index = selection.start;
    final length = selection.end - index;
    _quillController.replaceText(
      index,
      length,
      BlockEmbed.image(dataUri),
      TextSelection.collapsed(offset: index + 1),
    );
    _scheduleSave();
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: widget.folderBreadcrumb != null
              ? Text(
                  widget.folderBreadcrumb!,
                  style: Theme.of(context).textTheme.titleMedium,
                )
              : null,
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              QuillSimpleToolbar(
                controller: _quillController,
                config: QuillSimpleToolbarConfig(
                  headerStyleType: HeaderStyleType.buttons,
                  buttonOptions: QuillSimpleToolbarButtonOptions(
                    selectHeaderStyleButtons:
                        const QuillToolbarSelectHeaderStyleButtonsOptions(
                          attributes: [Attribute.h1, Attribute.h2],
                        ),
                    base: QuillToolbarBaseButtonOptions(
                      afterButtonPressed: () => _editorFocusNode.requestFocus(),
                    ),
                  ),
                  showAlignmentButtons: true,
                  showFontFamily: false,
                  showFontSize: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: false,
                  showStrikeThrough: false,
                  showInlineCode: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showQuote: false,
                  showCodeBlock: false,
                  showSearchButton: false,
                  showLink: false,
                  customButtons: [
                    QuillToolbarCustomButtonOptions(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: 'Insert image',
                      onPressed: _pickAndInsertImage,
                    ),
                    QuillToolbarCustomButtonOptions(
                      icon: const Icon(Icons.draw_outlined),
                      tooltip: 'Add sketch',
                      onPressed: _openSketch,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => _scheduleSave(),
                ),
              ),
              Expanded(
                child: QuillEditor(
                  focusNode: _editorFocusNode,
                  scrollController: _editorScrollController,
                  controller: _quillController,
                  config: QuillEditorConfig(
                    placeholder: 'Start writing…',
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    expands: true,
                    embedBuilders: const [DataUriImageEmbedBuilder()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
