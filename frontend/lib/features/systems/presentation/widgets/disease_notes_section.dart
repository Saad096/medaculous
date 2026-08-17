import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/domain/note_content_codec.dart';
import '../../../notes/presentation/providers/notes_providers.dart';

/// Client scope doc, Systems acceptance criteria: "The user can add notes
/// and attach images to each individual disease topic." Per the reference
/// screenshots this is NOT a separate feature — the Notes folder list *is*
/// the specialty list (e.g. "Cardiology"), and a disease's "Add Note" opens
/// the same rich-text editor pre-filed into that specialty's folder (the
/// screenshots' editor breadcrumb reads "‹ Cardiology"). This widget is the
/// disease-detail-screen half of that: it resolves/creates the folder
/// matching the disease's category, lists notes already filed there, and
/// opens the shared note editor (note_editor_screen.dart) for both adding
/// and viewing.
class DiseaseNotesSection extends ConsumerStatefulWidget {
  const DiseaseNotesSection({required this.folderName, super.key});

  /// The disease's specialty/category (e.g. "Cardiology") — doubles as the
  /// matching Notes folder's name.
  final String folderName;

  @override
  ConsumerState<DiseaseNotesSection> createState() =>
      _DiseaseNotesSectionState();
}

class _DiseaseNotesSectionState extends ConsumerState<DiseaseNotesSection> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _findFolderId() async {
    final folders = await ref.read(notesApiProvider).listFolders();
    for (final folder in folders) {
      if (folder.name.toLowerCase() == widget.folderName.toLowerCase()) {
        return folder.id;
      }
    }
    return null;
  }

  Future<String> _findOrCreateFolderId() async {
    final existingId = await _findFolderId();
    if (existingId != null) return existingId;
    final created = await ref
        .read(notesApiProvider)
        .createFolder(name: widget.folderName);
    return created.id;
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final folderId = await _findFolderId();
    final notes = folderId == null
        ? <Note>[]
        : await ref.read(notesApiProvider).listNotes(folderId: folderId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoading = false;
    });
  }

  Future<void> _addNote() async {
    final folderId = await _findOrCreateFolderId();
    if (!mounted) return;
    await context.push(
      '/notes/editor',
      extra: {'folderId': folderId, 'folderBreadcrumb': widget.folderName, 'autoFocus': true},
    );
    _load();
  }

  Future<void> _openNote(Note note) async {
    await context.push(
      '/notes/editor',
      extra: {'note': note, 'folderBreadcrumb': widget.folderName},
    );
    _load();
  }

  /// All clinical images attached across this topic's notes, decoded from
  /// their inline data URIs. Feature PDF: "upload clinical images or
  /// photographs" — surfaced here as a visible list with a View action
  /// instead of staying hidden inside the note body.
  List<Uint8List> get _attachedImages {
    final images = <Uint8List>[];
    for (final note in _notes) {
      for (final source in NoteContentCodec.imageSources(note.contentHtml)) {
        if (!source.startsWith('data:')) continue;
        final commaIndex = source.indexOf(',');
        if (commaIndex == -1) continue;
        try {
          images.add(base64Decode(source.substring(commaIndex + 1)));
        } catch (_) {
          // Skip undecodable embeds; the note editor shows its own placeholder.
        }
      }
    }
    return images;
  }

  void _viewImage(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Clinical image'),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Notes for this topic',
                    style: AppTextStyles.bodyStrong,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addNote,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add note'),
                ),
              ],
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  'No notes yet for this topic.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              )
            else ...[
              for (final note in _notes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppColors.notesIcon,
                  ),
                  title: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body,
                  ),
                  subtitle: Text(
                    NoteContentCodec.previewText(note.contentHtml),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: context.secondaryText,
                    ),
                  ),
                  onTap: () => _openNote(note),
                ),
              ..._buildImagesStrip(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildImagesStrip(BuildContext context) {
    final images = _attachedImages;
    if (images.isEmpty) return const [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 16,
            color: AppColors.notesIcon,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Clinical images (${images.length})',
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
            final bytes = images[index];
            return InkWell(
              onTap: () => _viewImage(bytes),
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Image.memory(
                      bytes,
                      width: 96,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.open_in_full_rounded,
                        size: 12,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'View',
                        style: AppTextStyles.micro.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }
}
