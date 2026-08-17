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

// Created once, the first time a user has zero folders (fresh account) —
// client feedback, 2026-08-15: opening Notes to a totally blank screen
// looked broken; a few folders already there makes it look finished.
const _defaultFolderNames = [
  'Cardiology',
  'Pulmonology',
  'Gastroenterology',
  'Endocrinology',
  'Urinary Tract',
  'Neurology',
  'Rheumatology',
  'Dermatology',
];

/// Folder browser — the Notes tab's landing screen, redesigned as a vertical
/// list (client feedback, 2026-08-15: horizontal folder tabs don't scale
/// past a handful of folders and don't match the iOS Notes layout they
/// want). Drilling into a folder opens _FolderNotesScreen.
class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  List<Folder> _folders = [];
  List<Note> _allNotes = [];
  bool _isLoading = true;
  bool _bootstrapAttempted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final api = ref.read(notesApiProvider);
    var folders = await api.listFolders();

    if (folders.isEmpty && !_bootstrapAttempted) {
      _bootstrapAttempted = true;
      for (final name in _defaultFolderNames) {
        await api.createFolder(name: name);
      }
      folders = await api.listFolders();
    }

    final notes = await api.listNotes();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _allNotes = notes;
      _isLoading = false;
    });
  }

  int _countFor(String? folderId) =>
      _allNotes.where((n) => n.folderId == folderId).length;

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
              title: Text('Delete folder', style: TextStyle(color: AppColors.danger)),
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
        content: const Text('Notes inside this folder are kept and moved to All Notes.'),
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
    await _load();
  }

  Future<void> _openFolder(String? folderId, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FolderNotesScreen(folderId: folderId, title: title)),
    );
    _load();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _TrashScreen()));
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                _FolderRow(
                  icon: Icons.notes_rounded,
                  iconColor: AppColors.primary,
                  title: 'All Notes',
                  count: _allNotes.length,
                  onTap: () => _openFolder(null, 'All Notes'),
                ),
                if (_folders.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
                    child: _SectionLabel('FOLDERS'),
                  ),
                  for (final folder in _folders)
                    _FolderRow(
                      icon: Icons.folder_rounded,
                      iconColor: AppColors.notesIcon,
                      title: folder.name,
                      count: _countFor(folder.id),
                      onTap: () => _openFolder(folder.id, folder.name),
                      onLongPress: () => _showFolderActions(folder),
                    ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(height: 1),
                ),
                _FolderRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: context.secondaryText,
                  title: 'Deleted Items',
                  count: null,
                  onTap: _openTrash,
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.micro.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final int? count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(title, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (count != null) ...[
              Text('$count', style: AppTextStyles.body.copyWith(color: context.secondaryText)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, color: context.secondaryText),
          ],
        ),
      ),
    );
  }
}

/// The notes inside one folder (or every note, for "All Notes") — split out
/// from the folder browser so a new note created here can be filed straight
/// into [folderId] (client feedback, 2026-08-15: a note created while a
/// folder was open used to land on the root screen instead of in it).
class _FolderNotesScreen extends ConsumerStatefulWidget {
  const _FolderNotesScreen({required this.folderId, required this.title});

  final String? folderId;
  final String title;

  @override
  ConsumerState<_FolderNotesScreen> createState() => _FolderNotesScreenState();
}

class _FolderNotesScreenState extends ConsumerState<_FolderNotesScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final notes = await ref.read(notesApiProvider).listNotes(folderId: widget.folderId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _isLoading = false;
    });
  }

  Future<void> _togglePin(Note note) async {
    await ref.read(notesApiProvider).updateNote(note.id, isPinned: !note.isPinned);
    await _load();
  }

  Future<void> _deleteNote(Note note) async {
    await ref.read(notesApiProvider).deleteNote(note.id);
    await _load();
    if (mounted) {
      showAppToast(context, 'Note moved to trash.', kind: AppToastKind.info);
    }
  }

  Future<void> _openEditor([Note? note]) async {
    await context.push(
      '/notes/editor',
      extra: {'note': note, 'folderId': widget.folderId, 'autoFocus': note == null},
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openEditor(),
          child: const Icon(Icons.add),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notes.isEmpty
            ? Center(
                child: Text(
                  'No notes yet — tap + to add one.',
                  style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  final preview = NoteContentCodec.previewText(note.contentHtml);
                  return Dismissible(
                    key: ValueKey(note.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      color: AppColors.danger,
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) => _deleteNote(note),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        onTap: () => _openEditor(note),
                        title: Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          style: AppTextStyles.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          preview.isEmpty ? _formatUpdatedAt(note.updatedAt) : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            color: note.isPinned ? AppColors.primary : AppColors.slate400,
                          ),
                          onPressed: () => _togglePin(note),
                        ),
                      ),
                    ),
                  );
                },
              ),
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

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text('${_notes.length} note${_notes.length == 1 ? '' : 's'} will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(notesApiProvider).emptyTrash();
    await _load();
    if (mounted) showAppToast(context, 'Trash emptied.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (_notes.isNotEmpty)
            TextButton(
              onPressed: _emptyTrash,
              child: Text('Empty Trash', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? Center(
              child: Text('Trash is empty.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)),
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
