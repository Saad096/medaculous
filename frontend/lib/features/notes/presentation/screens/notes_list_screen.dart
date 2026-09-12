import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/theme_providers.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/nav_shell.dart';
import '../../domain/note.dart';
import '../../domain/note_content_codec.dart';
import '../providers/notes_providers.dart';

// Persisted (see LocalPrefs.get/setNotesSortMode) via NoteSortMode.name, so
// the sheet a user picks stays their default across app restarts.
enum NoteSortMode {
  date('Date', Icons.schedule_rounded),
  name('Name', Icons.sort_by_alpha_rounded),
  custom('Custom order', Icons.drag_indicator_rounded);

  const NoteSortMode(this.label, this.icon);

  final String label;
  final IconData icon;

  static NoteSortMode fromName(String? name) =>
      NoteSortMode.values.firstWhere((m) => m.name == name, orElse: () => NoteSortMode.date);
}

/// Pinned notes float to the top under Date/Name, matching the pin toggle's
/// existing meaning elsewhere in this screen. Custom order deliberately
/// skips that override — pinning fighting a user's own drag-and-drop
/// arrangement would be more confusing than helpful.
List<Note> _sortNotes(List<Note> notes, NoteSortMode mode) {
  final sorted = [...notes];
  switch (mode) {
    case NoteSortMode.date:
      sorted.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    case NoteSortMode.name:
      sorted.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final aTitle = a.title.trim().isEmpty ? 'Untitled' : a.title.trim();
        final bTitle = b.title.trim().isEmpty ? 'Untitled' : b.title.trim();
        return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
      });
    case NoteSortMode.custom:
      sorted.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  return sorted;
}

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

// Not a real folder id — the "Move to folder" picker returns this to mean
// "top level" while still letting a plain `null` mean "the user cancelled",
// since a bottom sheet result can't otherwise tell those two apart.
const _kTopLevelSentinel = ' top-level';

Set<String> _descendantFolderIds(String rootId, List<Folder> all) {
  final result = <String>{};
  var frontier = [rootId];
  while (frontier.isNotEmpty) {
    final children = all.where((f) => frontier.contains(f.parentId)).map((f) => f.id).toList();
    result.addAll(children);
    frontier = children;
  }
  return result;
}

/// Long-press action sheet for a folder — Rename / Move to folder / Delete
/// — shared between the top-level folder browser and the sub-folders shown
/// inside an open folder, since a folder needs the exact same actions
/// regardless of where it's being long-pressed from (owner feedback,
/// 2026-09-11: nested folders had no long-press actions at all, and the
/// top-level ones were missing Move).
Future<void> showFolderActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required Folder folder,
  required Future<void> Function() onChanged,
}) async {
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
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to folder'),
            onTap: () => Navigator.of(sheetContext).pop('move'),
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
  if (!context.mounted) return;
  switch (action) {
    case 'rename':
      await _renameFolderDialog(context, ref, folder, onChanged);
    case 'move':
      await _moveFolderFlow(context, ref, folder, onChanged);
    case 'delete':
      await _deleteFolderFlow(context, ref, folder, onChanged);
  }
}

Future<void> _renameFolderDialog(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
  Future<void> Function() onChanged,
) async {
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
  await onChanged();
}

Future<void> _deleteFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
  Future<void> Function() onChanged,
) async {
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
  await onChanged();
}

Future<void> _moveFolderFlow(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
  Future<void> Function() onChanged,
) async {
  final allFolders = await ref.read(notesApiProvider).listFolders();
  if (!context.mounted) return;
  // A folder can never move into itself or into one of its own
  // sub-folders — that would create a cycle in the tree (also enforced
  // server-side, but excluding them here means the picker never even
  // offers an invalid destination).
  final excluded = _descendantFolderIds(folder.id, allFolders)..add(folder.id);
  final candidates = allFolders.where((f) => !excluded.contains(f.id)).toList();
  final destination = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _FolderPickerSheet(
      title: 'Move "${folder.name}" to',
      folders: candidates,
      currentParentId: folder.parentId,
    ),
  );
  if (destination == null) return;
  final newParentId = destination == _kTopLevelSentinel ? null : destination;
  if (newParentId == folder.parentId) return;
  await ref.read(notesApiProvider).moveFolder(folder.id, newParentId: newParentId);
  await onChanged();
}

/// Long-press action sheet for a note — Rename / Move to folder / Delete —
/// the same three actions a folder gets, so long-pressing either kind of
/// row behaves consistently (owner feedback, 2026-09-12: notes had no
/// long-press action at all before this).
Future<void> showNoteActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required Note note,
  required Future<void> Function() onChanged,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined, color: AppColors.notesIcon),
            title: Text(
              note.title.isEmpty ? 'Untitled' : note.title,
              style: AppTextStyles.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            dense: true,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename note'),
            onTap: () => Navigator.of(sheetContext).pop('rename'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to folder'),
            onTap: () => Navigator.of(sheetContext).pop('move'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            title: Text('Delete note', style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.of(sheetContext).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'rename':
      await _renameNoteDialog(context, ref, note, onChanged);
    case 'move':
      await _moveNoteFlow(context, ref, note, onChanged);
    case 'delete':
      await _deleteNoteFlow(context, ref, note, onChanged);
  }
}

Future<void> _renameNoteDialog(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Future<void> Function() onChanged,
) async {
  final controller = TextEditingController(text: note.title);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Note title'),
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
  if (title == null || title == note.title) return;
  await ref.read(notesApiProvider).updateNote(note.id, title: title);
  await onChanged();
}

Future<void> _deleteNoteFlow(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Future<void> Function() onChanged,
) async {
  await ref.read(notesApiProvider).deleteNote(note.id);
  await onChanged();
  if (context.mounted) {
    showAppToast(context, 'Note moved to trash.', kind: AppToastKind.info);
  }
}

Future<void> _moveNoteFlow(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Future<void> Function() onChanged,
) async {
  final allFolders = await ref.read(notesApiProvider).listFolders();
  if (!context.mounted) return;
  final destination = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _FolderPickerSheet(
      title: 'Move "${note.title.isEmpty ? 'Untitled' : note.title}" to',
      folders: allFolders,
      currentParentId: note.folderId,
      topLevelLabel: 'All Notes',
      topLevelIcon: Icons.notes_rounded,
    ),
  );
  if (destination == null) return;
  final newFolderId = destination == _kTopLevelSentinel ? null : destination;
  if (newFolderId == note.folderId) return;
  await ref.read(notesApiProvider).moveNote(note.id, newFolderId: newFolderId);
  await onChanged();
}

/// Destination list for "Move to folder" — Top Level plus every folder that
/// isn't the one being moved or nested inside it.
class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({
    required this.title,
    required this.folders,
    required this.currentParentId,
    this.topLevelLabel = 'Top Level',
    this.topLevelIcon = Icons.home_outlined,
  });

  final String title;
  final List<Folder> folders;
  final String? currentParentId;
  final String topLevelLabel;
  final IconData topLevelIcon;

  Folder? _findById(String id) {
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  int _depthOf(Folder folder) {
    var depth = 0;
    var current = folder;
    while (current.parentId != null) {
      final parent = _findById(current.parentId!);
      if (parent == null) break;
      current = parent;
      depth++;
    }
    return depth;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            child: Align(alignment: Alignment.centerLeft, child: Text(title, style: AppTextStyles.title)),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Icon(topLevelIcon, color: AppColors.notesIcon),
                  title: Text(topLevelLabel),
                  trailing: currentParentId == null
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(_kTopLevelSentinel),
                ),
                for (final folder in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded, color: AppColors.notesIcon),
                    title: Padding(
                      padding: EdgeInsets.only(left: _depthOf(folder) * AppSpacing.md),
                      child: Text(folder.name),
                    ),
                    trailing: currentParentId == folder.id
                        ? const Icon(Icons.check_rounded, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(folder.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<Note> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    // Debounced rather than firing on every keystroke — searching hits the
    // backend (see NotesApi.searchNotes), not an already-loaded in-memory
    // list, so typing fast would otherwise fire a request per character.
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isSearching = true);
      final results = await ref.read(notesApiProvider).searchNotes(value.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() {
      _query = '';
      _searchResults = [];
      _isSearching = false;
    });
  }

  Future<void> _openNoteFromSearch(Note note) async {
    await context.push('/notes/editor', extra: {'note': note});
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
      // listFolders() returns the whole tree flat — this screen is only the
      // top level, so a folder nested inside another (parentId set) must
      // not also show up here, or it reads as duplicated everywhere its
      // ancestors are (owner feedback, 2026-09-11).
      _folders = folders.where((f) => f.parentId == null).toList();
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearSearch,
                      ),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _query.trim().length >= 2
                ? _buildSearchResults()
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
                            onLongPress: () => showFolderActionsSheet(context, ref, folder: folder, onChanged: _load),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No notes match "${_query.trim()}".',
          style: AppTextStyles.body.copyWith(color: AppColors.slate400),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final note = _searchResults[index];
        final preview = NoteContentCodec.previewText(note.contentHtml);
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            onTap: () => _openNoteFromSearch(note),
            onLongPress: () => showNoteActionsSheet(context, ref, note: note, onChanged: _refreshSearch),
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
          ),
        );
      },
    );
  }

  Future<void> _refreshSearch() async {
    final query = _query.trim();
    if (query.length < 2) return;
    final results = await ref.read(notesApiProvider).searchNotes(query);
    if (!mounted) return;
    setState(() => _searchResults = results);
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
  List<Folder> _subFolders = [];
  Map<String, int> _subFolderCounts = {};
  bool _isLoading = true;
  NoteSortMode _sortMode = NoteSortMode.date;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final saved = await ref.read(localPrefsProvider).getNotesSortMode();
    if (!mounted) return;
    setState(() => _sortMode = NoteSortMode.fromName(saved));
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final api = ref.read(notesApiProvider);
    final results = await Future.wait([
      api.listNotes(folderId: widget.folderId),
      // "Folder within folders" (owner feedback, 2026-09-11) — a nested
      // folder is just another Folder row whose parentId is this screen's
      // folderId; listFolders() returns the whole tree flat, so the
      // children of *this* folder are filtered out client-side.
      widget.folderId == null
          ? Future<List<Folder>>.value(const [])
          : api.listFolders(),
      api.listNotes(),
    ]);
    if (!mounted) return;
    final allFolders = results[1] as List<Folder>;
    final allNotes = results[2] as List<Note>;
    final subFolders = allFolders.where((f) => f.parentId == widget.folderId).toList();
    setState(() {
      _notes = _sortNotes(results[0] as List<Note>, _sortMode);
      _subFolders = subFolders;
      _subFolderCounts = {
        for (final folder in subFolders)
          folder.id: allNotes.where((n) => n.folderId == folder.id).length,
      };
      _isLoading = false;
    });
  }

  Future<void> _openSortSheet() async {
    final mode = await showModalBottomSheet<NoteSortMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Text('Sort notes by', style: AppTextStyles.bodyStrong),
            ),
            for (final mode in NoteSortMode.values)
              ListTile(
                leading: Icon(mode.icon, color: mode == _sortMode ? AppColors.primary : null),
                title: Text(mode.label),
                trailing: mode == _sortMode ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
              ),
          ],
        ),
      ),
    );
    if (mode == null || mode == _sortMode || !mounted) return;
    await ref.read(localPrefsProvider).setNotesSortMode(mode.name);
    if (!mounted) return;
    setState(() {
      _sortMode = mode;
      _notes = _sortNotes(_notes, mode);
    });
  }

  Future<void> _onReorderNotes(int oldIndex, int newIndex) async {
    setState(() {
      final note = _notes.removeAt(oldIndex);
      _notes.insert(newIndex, note);
    });
    await ref.read(notesApiProvider).reorderNotes(_notes.map((n) => n.id).toList());
  }

  Future<void> _createSubFolder() async {
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
    await ref.read(notesApiProvider).createFolder(name: name, parentId: widget.folderId);
    await _load();
  }

  Future<void> _openSubFolder(Folder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FolderNotesScreen(folderId: folder.id, title: folder.name)),
    );
    _load();
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

  Widget _buildNoteTile(Note note) {
    final preview = NoteContentCodec.previewText(note.contentHtml);
    return Padding(
      // On the outer widget, not just the inner Dismissible — required by
      // ReorderableListView.builder (Custom sort mode) since it reads the
      // key off the direct child returned from itemBuilder.
      key: ValueKey(note.id),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Dismissible(
        key: ValueKey('${note.id}-dismissible'),
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
            onLongPress: () => showNoteActionsSheet(context, ref, note: note, onChanged: _load),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort notes',
              onPressed: _openSortSheet,
            ),
            // Not offered on the virtual "All Notes" view (folderId null) —
            // a folder nested "inside" that aggregate view isn't a coherent
            // location. Real folders always have a real parent to nest under.
            if (widget.folderId != null)
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'New folder',
                onPressed: _createSubFolder,
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openEditor(),
          child: const Icon(Icons.add),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _subFolders.isEmpty && _notes.isEmpty
            ? Center(
                child: Text(
                  'No notes yet — tap + to add one.',
                  style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                ),
              )
            // A Column with a scrollable Expanded below the (bounded)
            // subfolders section, rather than one flat ListView like before
            // — ReorderableListView (Custom sort mode) needs to own its own
            // scroll view, it can't just be more children mixed into a
            // plain ListView.
            : Column(
                children: [
                  if (_subFolders.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                      child: _SectionLabel('FOLDERS'),
                    ),
                    for (final folder in _subFolders)
                      _FolderRow(
                        icon: Icons.folder_rounded,
                        iconColor: AppColors.notesIcon,
                        title: folder.name,
                        count: _subFolderCounts[folder.id] ?? 0,
                        onTap: () => _openSubFolder(folder),
                        onLongPress: () => showFolderActionsSheet(context, ref, folder: folder, onChanged: _load),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Divider(height: 1),
                    ),
                  ],
                  Expanded(
                    child: _notes.isEmpty
                        ? Center(
                            child: Text(
                              'No notes in this folder yet.',
                              style: AppTextStyles.body.copyWith(color: AppColors.slate400),
                            ),
                          )
                        : _sortMode == NoteSortMode.custom
                        ? ReorderableListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            itemCount: _notes.length,
                            onReorderItem: _onReorderNotes,
                            itemBuilder: (context, index) => _buildNoteTile(_notes[index]),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            itemCount: _notes.length,
                            itemBuilder: (context, index) => _buildNoteTile(_notes[index]),
                          ),
                  ),
                ],
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
  List<Folder> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final api = ref.read(notesApiProvider);
    final results = await Future.wait([api.listTrash(), api.listTrashedFolders()]);
    if (!mounted) return;
    setState(() {
      _notes = results[0] as List<Note>;
      _folders = results[1] as List<Folder>;
      _isLoading = false;
    });
  }

  Future<void> _restoreNote(Note note) async {
    await ref.read(notesApiProvider).restoreNote(note.id);
    _load();
  }

  Future<void> _restoreFolder(Folder folder) async {
    await ref.read(notesApiProvider).restoreFolder(folder.id);
    _load();
  }

  Future<void> _emptyTrash() async {
    final itemCount = _notes.length + _folders.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text('$itemCount item${itemCount == 1 ? '' : 's'} will be permanently deleted. This cannot be undone.'),
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
    final isEmpty = _notes.isEmpty && _folders.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (!isEmpty)
            TextButton(
              onPressed: _emptyTrash,
              child: Text('Empty Trash', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isEmpty
          ? Center(
              child: Text('Trash is empty.', style: AppTextStyles.body.copyWith(color: AppColors.slate400)),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                for (final folder in _folders)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded, color: AppColors.notesIcon),
                    title: Text(folder.name),
                    trailing: TextButton(
                      onPressed: () => _restoreFolder(folder),
                      child: const Text('Restore'),
                    ),
                  ),
                for (final note in _notes)
                  ListTile(
                    title: Text(note.title.isEmpty ? 'Untitled' : note.title),
                    trailing: TextButton(
                      onPressed: () => _restoreNote(note),
                      child: const Text('Restore'),
                    ),
                  ),
              ],
            ),
    );
  }
}
