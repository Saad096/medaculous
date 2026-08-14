import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/knowledge_hub.dart';
import '../providers/knowledge_hub_providers.dart';

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The user's chosen destination from the "move to folder" picker — a plain
/// bool-return can't distinguish "cancelled" from "chose the root (null
/// folder)", so the picker returns this wrapper instead.
class _FolderChoice {
  const _FolderChoice(this.folderId);
  final String? folderId;
}

/// DISCOVERY_REPORT.md §8: personal PDF library with folders, search, viewer,
/// annotations, bookmarks. MVP scope decisions in docs/OPEN_QUESTIONS.md —
/// full server sync of PDFs (not just metadata), highlight+note annotations
/// only (no freehand/shapes), filename-only search (no PDF content search).
class KnowledgeHubListScreen extends ConsumerStatefulWidget {
  const KnowledgeHubListScreen({super.key});

  @override
  ConsumerState<KnowledgeHubListScreen> createState() =>
      _KnowledgeHubListScreenState();
}

class _KnowledgeHubListScreenState
    extends ConsumerState<KnowledgeHubListScreen> {
  final _searchController = TextEditingController();

  /// All of the user's non-deleted folders, flat — nesting is derived from
  /// each folder's `parentId`, same shape the backend stores.
  List<PdfFolder> _folders = [];
  List<PdfDocument> _pdfs = [];
  List<PdfSearchHit> _contentHits = [];

  /// null = viewing the root level (no folder).
  String? _currentFolderId;
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  /// Direct subfolders of the folder currently being viewed.
  List<PdfFolder> get _subfolders {
    final list = _folders
        .where((f) => f.parentId == _currentFolderId)
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Root-to-current chain of folders, for the breadcrumb bar.
  List<PdfFolder> get _breadcrumbTrail {
    final byId = {for (final f in _folders) f.id: f};
    final trail = <PdfFolder>[];
    var id = _currentFolderId;
    while (id != null) {
      final folder = byId[id];
      if (folder == null) break;
      trail.add(folder);
      id = folder.parentId;
    }
    return trail.reversed.toList();
  }

  /// Every folder the user owns, in depth-first tree order with a depth
  /// index — used by the "move to folder" picker so nesting is visible
  /// there too, not just while browsing.
  List<MapEntry<PdfFolder, int>> _flattenedFolderTree() {
    final byParent = <String?, List<PdfFolder>>{};
    for (final f in _folders) {
      byParent.putIfAbsent(f.parentId, () => []).add(f);
    }
    for (final siblings in byParent.values) {
      siblings.sort((a, b) => a.name.compareTo(b.name));
    }
    final flattened = <MapEntry<PdfFolder, int>>[];
    void visit(String? parentId, int depth) {
      for (final f in byParent[parentId] ?? const <PdfFolder>[]) {
        flattened.add(MapEntry(f, depth));
        visit(f.id, depth + 1);
      }
    }

    visit(null, 0);
    return flattened;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(knowledgeHubApiProvider);
      final query = _searchController.text.trim();
      final results = await Future.wait([
        api.listFolders(),
        api.listPdfs(
          folderId: query.isEmpty ? _currentFolderId : null,
          q: query.isEmpty ? null : query,
        ),
        // Filename matches (above) and content matches (this) are separate
        // queries — a PDF can match on content without its name containing
        // the search term at all, which is the whole point of indexing text.
        query.isEmpty
            ? Future.value(<PdfSearchHit>[])
            : api.searchContent(query),
      ]);
      if (!mounted) return;
      final pdfs = results[1] as List<PdfDocument>;
      final matchedIds = pdfs.map((p) => p.id).toSet();
      setState(() {
        _folders = results[0] as List<PdfFolder>;
        _pdfs = pdfs;
        // Don't show a PDF in both sections — if it already matched by name,
        // its content snippet is redundant with the row already shown.
        _contentHits = (results[2] as List<PdfSearchHit>)
            .where((h) => !matchedIds.contains(h.pdfId))
            .toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  void _openPdf(String pdfId, String filename, {int? initialPage}) {
    context.push(
      '/knowledge-hub/pdfs/$pdfId',
      extra: initialPage == null
          ? filename
          : {'filename': filename, 'initial_page': initialPage},
    );
  }

  void _openFolder(String? folderId) {
    setState(() => _currentFolderId = folderId);
    _load();
  }

  /// Drives both the app-bar back button and the system back gesture while
  /// nested — one level up at a time, rather than leaving the screen.
  void _goUpOneLevel() {
    final currentId = _currentFolderId;
    if (currentId == null) return;
    PdfFolder? current;
    for (final f in _folders) {
      if (f.id == currentId) {
        current = f;
        break;
      }
    }
    setState(() => _currentFolderId = current?.parentId);
    _load();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_currentFolderId == null ? 'New folder' : 'New subfolder'),
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
    await ref
        .read(knowledgeHubApiProvider)
        .createFolder(name: name, parentId: _currentFolderId);
    await _load();
  }

  Future<void> _uploadPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final file = result?.files.single;
    if (file?.path == null) return;

    setState(() => _isUploading = true);
    try {
      await ref
          .read(knowledgeHubApiProvider)
          .uploadPdf(
            filePath: file!.path!,
            filename: file.name,
            folderId: _currentFolderId,
          );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showPdfDetails(PdfDocument pdf) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pdf.displayTitle, style: AppTextStyles.headline),
              const SizedBox(height: AppSpacing.md),
              _DetailRow(label: 'Filename', value: pdf.filename),
              _DetailRow(label: 'Pages', value: '${pdf.pageCount}'),
              _DetailRow(label: 'Size', value: _formatSize(pdf.sizeBytes)),
              if (pdf.author != null) _DetailRow(label: 'Author', value: pdf.author!),
              _DetailRow(
                label: 'Uploaded',
                value: '${pdf.updatedAt.toLocal()}'.split('.').first,
              ),
              if (pdf.contentPreview != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Content preview', style: AppTextStyles.bodyStrong),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  pdf.contentPreview!,
                  style: AppTextStyles.body.copyWith(color: context.secondaryText),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No extractable text found — this PDF may be a scan or image-only document.',
                  style: AppTextStyles.caption.copyWith(color: context.secondaryText),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deletePdf(PdfDocument pdf) async {
    await ref.read(knowledgeHubApiProvider).deletePdf(pdf.id);
    await _load();
  }

  Future<_FolderChoice?> _pickMoveDestination() {
    final tree = _flattenedFolderTree();
    return showDialog<_FolderChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Root (no folder)'),
                onTap: () =>
                    Navigator.of(context).pop(const _FolderChoice(null)),
              ),
              for (final entry in tree)
                ListTile(
                  contentPadding: EdgeInsets.only(
                    left: AppSpacing.lg + entry.value * AppSpacing.lg,
                    right: AppSpacing.lg,
                  ),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    entry.key.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_FolderChoice(entry.key.id)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _movePdf(PdfDocument pdf) async {
    final choice = await _pickMoveDestination();
    if (choice == null) return;
    try {
      await ref
          .read(knowledgeHubApiProvider)
          .movePdf(pdf.id, choice.folderId);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, kind: AppToastKind.error);
    }
  }

  Widget _buildBreadcrumbBar() {
    final trail = _breadcrumbTrail;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _BreadcrumbItem(
              label: 'Home',
              isCurrent: trail.isEmpty,
              onTap: trail.isEmpty ? null : () => _openFolder(null),
            ),
            for (final folder in trail) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.slate400,
                ),
              ),
              _BreadcrumbItem(
                label: folder.name,
                isCurrent: folder.id == _currentFolderId,
                onTap: folder.id == _currentFolderId
                    ? null
                    : () => _openFolder(folder.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subfolders = _isSearching ? const <PdfFolder>[] : _subfolders;
    final showEmptyState = _isSearching
        ? (_pdfs.isEmpty && _contentHits.isEmpty)
        : (subfolders.isEmpty && _pdfs.isEmpty);

    return PopScope(
      canPop: _currentFolderId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goUpOneLevel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _currentFolderId != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  onPressed: _goUpOneLevel,
                )
              : null,
          title: Text(
            _currentFolderId == null || _breadcrumbTrail.isEmpty
                ? 'Knowledge Hub'
                : _breadcrumbTrail.last.name,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: _currentFolderId == null ? 'New folder' : 'New subfolder',
              onPressed: _createFolder,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _isUploading ? null : _uploadPdf,
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file_rounded),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Search PDFs by name…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _load();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.slate700
                          : AppColors.slate200,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (!_isSearching) _buildBreadcrumbBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    )
                  : showEmptyState
                  ? Center(
                      child: Text(
                        _isSearching
                            ? 'No matches in filenames or PDF content.'
                            : _currentFolderId == null
                            ? 'No PDFs yet — tap upload to add one.'
                            : 'This folder is empty.',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.slate400,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        for (final folder in subfolders)
                          _FolderTile(
                            folder: folder,
                            onTap: () => _openFolder(folder.id),
                          ),
                        for (final pdf in _pdfs)
                          Dismissible(
                            key: ValueKey(pdf.id),
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
                            onDismissed: (_) => _deletePdf(pdf),
                            child: Card(
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: AppColors.danger,
                                ),
                                title: Text(
                                  pdf.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyStrong,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pdf.pageCount} pages · ${_formatSize(pdf.sizeBytes)}'
                                      '${pdf.author != null ? ' · ${pdf.author}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.caption.copyWith(
                                        color: context.secondaryText,
                                      ),
                                    ),
                                    if (pdf.contentPreview != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        pdf.contentPreview!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: context.secondaryText,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.info_outline_rounded,
                                        color: context.secondaryText,
                                      ),
                                      tooltip: 'Document details',
                                      onPressed: () => _showPdfDetails(pdf),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.drive_file_move_outlined,
                                        color: context.secondaryText,
                                      ),
                                      tooltip: 'Move to folder',
                                      onPressed: () => _movePdf(pdf),
                                    ),
                                  ],
                                ),
                                onTap: () => _openPdf(pdf.id, pdf.filename),
                              ),
                            ),
                          ),
                        if (_contentHits.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Text(
                              'Found in PDF content',
                              style: AppTextStyles.caption.copyWith(
                                color: context.secondaryText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          for (final hit in _contentHits)
                            Card(
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.find_in_page_outlined,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  hit.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyStrong,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (hit.pageNumber != null)
                                      Text(
                                        'Page ${hit.pageNumber}',
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    Text(
                                      hit.snippet,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                onTap: () => _openPdf(
                                  hit.pdfId,
                                  hit.filename,
                                  initialPage: hit.pageNumber,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single crumb in the "Home > Folder > Subfolder" trail above the list.
class _BreadcrumbItem extends StatelessWidget {
  const _BreadcrumbItem({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrent
                ? AppTextStyles.bodyStrong.copyWith(color: AppColors.titleText)
                : AppTextStyles.body.copyWith(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

/// A folder row in the list — same elevated-card treatment as the Home
/// screen's feature cards (soft shadow + tinted icon chip) rather than the
/// flat `Card` used for PDF rows, so folders read as distinct, tappable
/// containers you drill into.
class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap});

  final PdfFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate800 : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.knowledgeHubCardBg,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: AppColors.knowledgeHubIcon,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: isDark ? Colors.white : AppColors.cardTitleText,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: AppTextStyles.caption.copyWith(color: context.secondaryText)),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}
