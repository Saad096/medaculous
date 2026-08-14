import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../domain/note.dart';
import '../../domain/note_content_codec.dart';
import '../providers/notes_providers.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatUpdatedAt(DateTime dt) {
  final local = dt.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year} · $hour12:$minute $period';
}

/// DISCOVERY_REPORT.md §5: the legacy app is a full rich-text/image/drawing
/// notes editor. Rich text (headings/bold/italic/lists/alignment) and inline
/// images are supported (see note_editor_screen.dart, built on flutter_quill)
/// alongside folders, pin, and trash/restore — freehand drawing, manual
/// reorder, and JSON export/import remain deliberately deferred (tracked
/// separately, not silently dropped).
class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  List<Folder> _folders = [];
  List<Note> _notes = [];
  String? _selectedFolderId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final api = ref.read(notesApiProvider);
    final results = await Future.wait([
      api.listFolders(),
      api.listNotes(folderId: _selectedFolderId),
    ]);
    if (!mounted) return;
    setState(() {
      _folders = results[0] as List<Folder>;
      _notes = results[1] as List<Note>;
      _isLoading = false;
    });
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(notesApiProvider).createFolder(name: name);
    await _load();
  }

  /// Long-press actions on a folder chip — folders were create-only before
  /// ("folder in notes is not able to delete, should be delete and editable").
  Future<void> _showFolderActions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_rounded, color: AppColors.notesIcon),
              title: Text(folder.name, style: AppTextStyles.bodyStrong),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename folder'),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text(
                'Delete folder',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _renameFolder(folder);
    } else if (action == 'delete') {
      await _deleteFolder(folder);
    }
  }

  Future<void> _renameFolder(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == folder.name) return;
    await ref.read(notesApiProvider).updateFolder(folder.id, name: name);
    await _load();
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: const Text(
          'Notes inside this folder are kept and moved to All notes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(notesApiProvider).deleteFolder(folder.id);
    if (_selectedFolderId == folder.id) _selectedFolderId = null;
    await _load();
  }

  Future<void> _togglePin(Note note) async {
    await ref
        .read(notesApiProvider)
        .updateNote(note.id, isPinned: !note.isPinned);
    await _load();
  }

  Future<void> _deleteNote(Note note) async {
    await ref.read(notesApiProvider).deleteNote(note.id);
    await _load();
    if (mounted) {
      showAppToast(
        context,
        'Note moved to trash.',
        kind: AppToastKind.info,
        action: SnackBarAction(label: 'View trash', onPressed: _openTrash),
      );
    }
  }

  Future<void> _openTrash() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _TrashScreen()));
    _load();
  }

  Future<void> _openEditor([Note? note]) async {
    await context.push('/notes/editor', extra: note);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return NavShell(
      current: AppNavTab.notes,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: _createFolder,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: _openTrash,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _selectedFolderId == null,
                          onSelected: (_) {
                            setState(() => _selectedFolderId = null);
                            _load();
                          },
                        ),
                      ),
                      for (final folder in _folders)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          // Long-press for rename/delete actions.
                          child: GestureDetector(
                            onLongPress: () => _showFolderActions(folder),
                            child: ChoiceChip(
                              label: Text(folder.name),
                              selected: _selectedFolderId == folder.id,
                              onSelected: (_) {
                                setState(() => _selectedFolderId = folder.id);
                                _load();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _notes.isEmpty
                      ? Center(
                          child: Text(
                            'No notes yet — tap + to add one.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.slate400,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _notes.length,
                          itemBuilder: (context, index) {
                            final note = _notes[index];
                            final preview = NoteContentCodec.previewText(
                              note.contentHtml,
                            );
                            return Dismissible(
                              key: ValueKey(note.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                color: AppColors.danger,
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) => _deleteNote(note),
                              child: Card(
                                margin: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: ListTile(
                                  onTap: () => _openEditor(note),
                                  title: Text(
                                    note.title.isEmpty
                                        ? 'Untitled'
                                        : note.title,
                                    style: AppTextStyles.bodyStrong,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    preview.isEmpty
                                        ? _formatUpdatedAt(note.updatedAt)
                                        : preview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption.copyWith(
                                      color: context.secondaryText,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      note.isPinned
                                          ? Icons.push_pin_rounded
                                          : Icons.push_pin_outlined,
                                      color: note.isPinned
                                          ? AppColors.primary
                                          : AppColors.slate400,
                                    ),
                                    onPressed: () => _togglePin(note),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _TrashScreen extends ConsumerStatefulWidget {
  const _TrashScreen();

  @override
  ConsumerState<_TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<_TrashScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final notes = await ref.read(notesApiProvider).listTrash();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoading = false;
    });
  }

  Future<void> _restore(Note note) async {
    await ref.read(notesApiProvider).restoreNote(note.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? Center(
              child: Text(
                'Trash is empty.',
                style: AppTextStyles.body.copyWith(color: AppColors.slate400),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                return ListTile(
                  title: Text(note.title.isEmpty ? 'Untitled' : note.title),
                  trailing: TextButton(
                    onPressed: () => _restore(note),
                    child: const Text('Restore'),
                  ),
                );
              },
            ),
    );
  }
}
