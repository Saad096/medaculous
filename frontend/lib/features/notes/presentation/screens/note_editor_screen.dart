import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
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
/// Explicit save via the checkmark in the app bar — owner feedback,
/// 2026-08-17: autosave-on-every-keystroke made it impossible to leave
/// without something already being written, and gave no clear "this is
/// saved" moment. Leaving with unsaved changes prompts first.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.note,
    this.initialFolderId,
    this.folderBreadcrumb,
    this.autoFocus = false,
  });

  final Note? note;

  /// Folder a brand-new note should be filed into (e.g. a disease's matching
  /// specialty folder). Ignored when [note] is non-null — an existing note
  /// keeps its own folder.
  final String? initialFolderId;

  /// Optional label shown above the title (e.g. "Cardiology") when opened
  /// from a disease topic, mirroring the reference UI's folder breadcrumb.
  final String? folderBreadcrumb;

  /// Focuses the body straight away — used when this screen opens as the
  /// *only* affordance for adding a note (e.g. a disease's Notes tab), so
  /// the user can start typing immediately instead of tapping an "Add
  /// note" button first (owner feedback, 2026-08-17).
  final bool autoFocus;

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
  bool _isSaving = false;
  bool _dirty = false;
  bool _toolbarExpanded = false;

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
    _quillController.changes.listen((_) => _markDirty());
    _titleController.addListener(_markDirty);

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _editorFocusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
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
    if (mounted) {
      setState(() {
        _isSaving = false;
        _dirty = false;
      });
    }
  }

  Future<void> _handleBack() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      // Tapping outside just closes the dialog and stays on the editor —
      // owner feedback, 2026-08-17: "if user click on somewhere else the
      // card must be removed automatically", i.e. treat it as cancel.
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 32),
        title: const Text('Save this note?'),
        content: const Text(
          "You've written something here. Leaving now without saving means it won't be kept.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'save') await _save();
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
    _markDirty();
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
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  Icons.check_rounded,
                  color: _dirty ? AppColors.primary : AppColors.slate400,
                ),
                tooltip: 'Save',
                onPressed: _dirty ? _save : null,
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _CompactToolbarRow(
                expanded: _toolbarExpanded,
                onToggleFormatting: () => setState(() => _toolbarExpanded = !_toolbarExpanded),
                onInsertImage: _pickAndInsertImage,
                onSketch: _openSketch,
                controller: _quillController,
              ),
              // Collapsed by default — owner feedback, 2026-08-17: a full
              // formatting bar permanently on screen "reserved space" and
              // overlapped the content; now it only appears when asked for.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _toolbarExpanded
                    ? QuillSimpleToolbar(
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
                          showUndo: false,
                          showRedo: false,
                        ),
                      )
                    : const SizedBox.shrink(),
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

/// Always-visible slim bar: a formatting toggle plus the two "attach media"
/// actions, so those stay reachable without expanding the full toolbar.
class _CompactToolbarRow extends StatelessWidget {
  const _CompactToolbarRow({
    required this.expanded,
    required this.onToggleFormatting,
    required this.onInsertImage,
    required this.onSketch,
    required this.controller,
  });

  final bool expanded;
  final VoidCallback onToggleFormatting;
  final VoidCallback onInsertImage;
  final VoidCallback onSketch;
  final QuillController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(expanded ? Icons.expand_less_rounded : Icons.text_format_rounded),
            tooltip: expanded ? 'Hide formatting' : 'Formatting',
            onPressed: onToggleFormatting,
          ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Insert image',
            onPressed: onInsertImage,
          ),
          IconButton(
            icon: const Icon(Icons.draw_outlined),
            tooltip: 'Add sketch',
            onPressed: onSketch,
          ),
          const Spacer(),
          QuillToolbarHistoryButton(controller: controller, isUndo: true),
          QuillToolbarHistoryButton(controller: controller, isUndo: false),
        ],
      ),
    );
  }
}
