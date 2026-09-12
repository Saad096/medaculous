import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart' hide PdfDocument;
import 'package:pdfx/pdfx.dart' as pdfx show PdfDocument;

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/knowledge_hub.dart';
import '../providers/knowledge_hub_providers.dart';

/// Annotation tools modeled on the reference screenshot in the feature PDF:
/// pan hand, freehand pen, highlighter, eraser, color dots, undo/redo, page
/// arrows, plus rename/delete of the document itself.
enum _ViewerTool { pan, highlight, draw, erase }

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    required this.pdfId,
    required this.filename,
    this.initialPage,
    super.key,
  });

  final String pdfId;
  final String? filename;

  /// Set when navigated here from a content-search result (see
  /// KnowledgeHubListScreen) so the viewer opens directly on the matching
  /// page instead of page 1.
  final int? initialPage;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  static const _palette = [
    Color(0xFFFFEB3B), // yellow
    Color(0xFF66BB6A), // green
    Color(0xFF42A5F5), // blue
    Color(0xFFEF5350), // red
  ];

  PdfController? _controller;
  List<PdfBookmark> _bookmarks = [];
  List<PdfAnnotation> _annotations = [];
  List<PdfOutlineEntry> _outline = [];
  int _currentPage = 1;
  int? _pageCount;
  bool _isLoading = true;
  String? _error;
  String? _filename;

  _ViewerTool _tool = _ViewerTool.pan;
  Color _color = _palette.first;

  // Highlight drag state.
  Offset? _dragStart;
  Offset? _dragCurrent;

  // Freehand pen stroke in progress (viewport coordinates).
  final List<Offset> _inkPoints = [];

  // Session undo/redo over annotations created or removed here.
  final List<PdfAnnotation> _undoStack = [];
  final List<PdfAnnotation> _redoStack = [];

  /// width/height per page, recorded by the custom renderer, so annotation
  /// coordinates can be normalized against the *displayed page bounds*
  /// instead of the whole viewport (which misaligned them on every page
  /// whose aspect ratio didn't match the screen).
  final Map<int, double> _pageAspects = {};

  @override
  void initState() {
    super.initState();
    _filename = widget.filename;
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Sharper rendering than pdfx's default (2x JPEG): 3x PNG with the
  /// Android print-quality hint — the feature PDF's Knowledge Hub fix #1
  /// ("the pdf viewed appears a bit blurry").
  Future<PdfPageImage?> _renderPage(PdfPage page) {
    _pageAspects[page.pageNumber] = page.width / page.height;
    return page.render(
      width: page.width * 3,
      height: page.height * 3,
      format: PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
      forPrint: true,
    );
  }

  /// pdfx's *default* page builder wraps every page in its own independently
  /// pinch-zoomable PhotoView — great on its own, but the highlight/drawing
  /// overlays are positioned from _pageRect(), which only ever knows the
  /// page's fit-to-viewport rect and has no way to see that per-page zoom.
  /// Once a user pinched in, whatever they highlighted landed in the wrong
  /// place relative to the now-zoomed page (owner feedback, 2026-09-12).
  /// Fix: lock this PhotoView to a single fixed scale (`disableGestures` +
  /// min == max == initial) so it can never zoom on its own, and let a
  /// single InteractiveViewer around the *whole* Stack (page + overlays,
  /// see the build method below) own zooming instead — everything inside it
  /// scales as one unit, so overlay coordinates stay correct at any zoom.
  PhotoViewGalleryPageOptions _pageBuilder(
    BuildContext context,
    Future<PdfPageImage> pageImage,
    int index,
    pdfx.PdfDocument document,
  ) {
    const fixedScale = PhotoViewComputedScale.contained;
    return PhotoViewGalleryPageOptions(
      imageProvider: PdfPageImageProvider(pageImage, index, document.id),
      minScale: fixedScale,
      maxScale: fixedScale,
      initialScale: fixedScale,
      disableGestures: true,
      heroAttributes: PhotoViewHeroAttributes(tag: '${document.id}-$index'),
    );
  }

  Future<void> _load() async {
    try {
      final api = ref.read(knowledgeHubApiProvider);
      final results = await Future.wait([
        api.downloadPdfBytes(widget.pdfId),
        api.listBookmarks(widget.pdfId),
        api.listAnnotations(widget.pdfId),
        api.getOutline(widget.pdfId),
      ]);
      if (!mounted) return;
      final bytes = results[0] as Uint8List;
      setState(() {
        _controller = PdfController(
          document: pdfx.PdfDocument.openData(bytes),
          initialPage: widget.initialPage ?? 1,
        );
        _bookmarks = results[1] as List<PdfBookmark>;
        _annotations = results[2] as List<PdfAnnotation>;
        _outline = results[3] as List<PdfOutlineEntry>;
        _currentPage = widget.initialPage ?? 1;
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

  bool get _currentPageBookmarked =>
      _bookmarks.any((b) => b.pageNumber == _currentPage);

  /// The rectangle the current page actually occupies inside the viewport
  /// (BoxFit.contain, centered) — the coordinate space for annotations.
  Rect _pageRect(Size viewportSize) {
    final aspect = _pageAspects[_currentPage];
    if (aspect == null) return Offset.zero & viewportSize;
    final viewportAspect = viewportSize.width / viewportSize.height;
    double width, height;
    if (aspect > viewportAspect) {
      width = viewportSize.width;
      height = width / aspect;
    } else {
      height = viewportSize.height;
      width = height * aspect;
    }
    return Rect.fromLTWH(
      (viewportSize.width - width) / 2,
      (viewportSize.height - height) / 2,
      width,
      height,
    );
  }

  static Color parseHexColor(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFEB3B);
  }

  static String _toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Future<void> _toggleBookmark() async {
    final api = ref.read(knowledgeHubApiProvider);
    final existing = _bookmarks
        .where((b) => b.pageNumber == _currentPage)
        .firstOrNull;
    if (existing != null) {
      await api.deleteBookmark(existing.id);
      setState(() => _bookmarks.removeWhere((b) => b.id == existing.id));
    } else {
      final bookmark = await api.addBookmark(
        widget.pdfId,
        pageNumber: _currentPage,
      );
      setState(() => _bookmarks.add(bookmark));
    }
  }

  Future<void> _renamePdf() async {
    final controller = TextEditingController(text: _filename ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'File name'),
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
    if (name == null || name.isEmpty || name == _filename) return;
    final updated = await ref
        .read(knowledgeHubApiProvider)
        .renamePdf(widget.pdfId, name);
    if (!mounted) return;
    setState(() => _filename = updated.filename);
    showAppToast(context, 'Renamed to "${updated.filename}".');
  }

  Future<void> _deletePdf() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this PDF?'),
        content: Text(
          '"${_filename ?? 'This document'}" and its bookmarks, highlights '
          'and notes will be deleted.',
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
    await ref.read(knowledgeHubApiProvider).deletePdf(widget.pdfId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showOutline() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _outline.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('This document has no built-in table of contents.'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _outline.length,
                itemBuilder: (context, index) {
                  final entry = _outline[index];
                  return ListTile(
                    dense: entry.level > 0,
                    contentPadding: EdgeInsets.only(
                      left: AppSpacing.lg + entry.level * 20.0,
                      right: AppSpacing.lg,
                    ),
                    leading: Icon(
                      entry.level == 0
                          ? Icons.article_outlined
                          : Icons.subdirectory_arrow_right_rounded,
                      size: entry.level == 0 ? 22 : 18,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: entry.level == 0
                          ? AppTextStyles.bodyStrong
                          : AppTextStyles.body,
                    ),
                    trailing: Text(
                      'p. ${entry.page}',
                      style: AppTextStyles.caption.copyWith(
                        color: context.secondaryText,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _controller?.jumpToPage(entry.page);
                    },
                  );
                },
              ),
      ),
    );
  }

  void _showBookmarks() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _bookmarks.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No bookmarks yet. Use the bookmark icon in the top bar to save the current page.',
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final bookmark in _bookmarks)
                    ListTile(
                      leading: const Icon(
                        Icons.bookmark_rounded,
                        color: AppColors.warning,
                      ),
                      title: Text(
                        bookmark.label.isEmpty
                            ? 'Page ${bookmark.pageNumber}'
                            : bookmark.label,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _controller?.jumpToPage(bookmark.pageNumber);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add note to page $_currentPage'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Note text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    final annotation = await ref
        .read(knowledgeHubApiProvider)
        .addAnnotation(
          widget.pdfId,
          pageNumber: _currentPage,
          type: 'note',
          note: note,
        );
    if (!mounted) return;
    setState(() => _annotations.add(annotation));
    showAppToast(context, 'Note saved to page $_currentPage.');
  }

  Future<void> _saveHighlight(Rect dragRect, Size viewportSize) async {
    final pageRect = _pageRect(viewportSize);
    final clipped = dragRect.intersect(pageRect);
    if (clipped.width <= 8 || clipped.height <= 8) return;
    final normalized = NormalizedRect(
      x: (clipped.left - pageRect.left) / pageRect.width,
      y: (clipped.top - pageRect.top) / pageRect.height,
      width: clipped.width / pageRect.width,
      height: clipped.height / pageRect.height,
    );
    final annotation = await ref
        .read(knowledgeHubApiProvider)
        .addAnnotation(
          widget.pdfId,
          pageNumber: _currentPage,
          type: 'highlight',
          color: _toHex(_color),
          rects: [normalized],
        );
    setState(() {
      _annotations.add(annotation);
      _undoStack.add(annotation);
      _redoStack.clear();
    });
  }

  /// Persists the in-progress freehand stroke as an "ink" annotation. Points
  /// are stored in the existing rects column as ordered zero-size rects
  /// (page-relative fractions), stroke width as a page-width fraction in the
  /// text field — no backend schema change needed.
  Future<void> _saveInk(Size viewportSize) async {
    final pageRect = _pageRect(viewportSize);
    final points = [
      for (final p in _inkPoints)
        if (pageRect.contains(p))
          NormalizedRect(
            x: (p.dx - pageRect.left) / pageRect.width,
            y: (p.dy - pageRect.top) / pageRect.height,
            width: 0,
            height: 0,
          ),
    ];
    _inkPoints.clear();
    if (points.length < 2) {
      setState(() {});
      return;
    }
    final annotation = await ref
        .read(knowledgeHubApiProvider)
        .addAnnotation(
          widget.pdfId,
          pageNumber: _currentPage,
          type: 'ink',
          color: _toHex(_color),
          rects: points,
          text: '0.007', // stroke width as a fraction of page width
        );
    if (!mounted) return;
    setState(() {
      _annotations.add(annotation);
      _undoStack.add(annotation);
      _redoStack.clear();
    });
  }

  /// Eraser: tap near a pen stroke or inside a highlight to remove it.
  Future<void> _eraseAt(Offset point, Size viewportSize) async {
    final pageRect = _pageRect(viewportSize);
    PdfAnnotation? hit;
    for (final annotation in _annotations.reversed) {
      if (annotation.pageNumber != _currentPage) continue;
      if (annotation.type == 'highlight') {
        final contains = annotation.rects.any((r) {
          final rect = Rect.fromLTWH(
            pageRect.left + r.x * pageRect.width,
            pageRect.top + r.y * pageRect.height,
            r.width * pageRect.width,
            r.height * pageRect.height,
          );
          return rect.inflate(6).contains(point);
        });
        if (contains) hit = annotation;
      } else if (annotation.type == 'ink') {
        final near = annotation.rects.any((r) {
          final p = Offset(
            pageRect.left + r.x * pageRect.width,
            pageRect.top + r.y * pageRect.height,
          );
          return (p - point).distance <= 18;
        });
        if (near) hit = annotation;
      }
      if (hit != null) break;
    }
    final target = hit;
    if (target == null) return;
    await ref.read(knowledgeHubApiProvider).deleteAnnotation(target.id);
    if (!mounted) return;
    setState(() {
      _annotations.removeWhere((a) => a.id == target.id);
      _undoStack.removeWhere((a) => a.id == target.id);
    });
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final annotation = _undoStack.removeLast();
    await ref.read(knowledgeHubApiProvider).deleteAnnotation(annotation.id);
    if (!mounted) return;
    setState(() {
      _annotations.removeWhere((a) => a.id == annotation.id);
      _redoStack.add(annotation);
    });
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final annotation = _redoStack.removeLast();
    final recreated = await ref
        .read(knowledgeHubApiProvider)
        .addAnnotation(
          widget.pdfId,
          pageNumber: annotation.pageNumber,
          type: annotation.type,
          color: annotation.color,
          rects: annotation.rects,
          text: annotation.text,
          note: annotation.note,
        );
    if (!mounted) return;
    setState(() {
      _annotations.add(recreated);
      _undoStack.add(recreated);
    });
  }

  Future<void> _showPageAnnotations() async {
    final pageAnnotations = _annotations
        .where((a) => a.pageNumber == _currentPage)
        .toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: pageAnnotations.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No highlights, drawings or notes on this page yet. Use the toolbar below the page to add one.',
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final annotation in pageAnnotations)
                    ListTile(
                      leading: Icon(
                        switch (annotation.type) {
                          'note' => Icons.sticky_note_2_outlined,
                          'ink' => Icons.draw_outlined,
                          _ => Icons.border_color_rounded,
                        },
                        color: annotation.type == 'note'
                            ? AppColors.warning
                            : parseHexColor(annotation.color),
                      ),
                      title: Text(switch (annotation.type) {
                        'note' => annotation.note,
                        'ink' => 'Pen drawing',
                        _ => 'Highlight',
                      }),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await ref
                              .read(knowledgeHubApiProvider)
                              .deleteAnnotation(annotation.id);
                          if (!mounted || !context.mounted) return;
                          Navigator.of(context).pop();
                          setState(
                            () => _annotations.removeWhere(
                              (a) => a.id == annotation.id,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  int get _currentPageNoteCount => _annotations
      .where((a) => a.pageNumber == _currentPage && a.type == 'note')
      .length;

  String get _statusText => switch (_tool) {
    _ViewerTool.highlight => 'Highlighter: drag over the text to highlight',
    _ViewerTool.draw => 'Pen: draw on the page with your finger',
    _ViewerTool.erase => 'Eraser: tap a highlight or drawing to remove it',
    _ViewerTool.pan => '',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filename ?? 'PDF',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_controller != null) ...[
            IconButton(
              icon: Icon(
                _currentPageBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
              tooltip: 'Bookmark this page',
              onPressed: _toggleBookmark,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (action) {
                switch (action) {
                  case 'contents':
                    _showOutline();
                  case 'bookmarks':
                    _showBookmarks();
                  case 'annotations':
                    _showPageAnnotations();
                  case 'rename':
                    _renamePdf();
                  case 'delete':
                    _deletePdf();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'contents',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.toc_rounded),
                    title: Text('Contents'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'bookmarks',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.bookmarks_outlined),
                    title: Text('Bookmarks'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'annotations',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.list_alt_rounded),
                    title: Text('Annotations on this page'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename PDF'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    title: Text(
                      'Delete PDF',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
            )
          : Column(
              children: [
                // Page navigation bar: ‹ Page X of Y › (reference screenshot's
                // page arrows), doubling as the active-tool hint strip.
                Container(
                  width: double.infinity,
                  color: isDark ? AppColors.slate800 : AppColors.slate50,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous page',
                        onPressed: _currentPage > 1
                            ? () => _controller?.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          _tool != _ViewerTool.pan
                              ? _statusText
                              : 'Page $_currentPage${_pageCount != null ? ' of $_pageCount' : ''}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: _tool != _ViewerTool.pan
                                ? AppColors.primary
                                : context.secondaryText,
                            fontWeight: _tool != _ViewerTool.pan
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next page',
                        onPressed:
                            _pageCount != null && _currentPage < _pageCount!
                            ? () => _controller?.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final pageRect = _pageRect(viewportSize);
                      return InteractiveViewer(
                        // The single source of zoom/pan for this whole page
                        // — see _pageBuilder's doc comment for why this
                        // replaces PhotoView's own per-page zoom instead of
                        // living alongside it. Pan only claims single-finger
                        // drags in the plain "pan" tool — otherwise it would
                        // compete with (and normally win over) the
                        // highlight/draw/erase tools' own onPan* handlers
                        // further down this Stack. Pinch-to-zoom stays on
                        // regardless of tool, since it's a two-finger
                        // gesture none of those tools use.
                        panEnabled: _tool == _ViewerTool.pan,
                        scaleEnabled: true,
                        minScale: 1,
                        maxScale: 4,
                        child: Stack(
                          children: [
                            PdfView(
                              controller: _controller!,
                              renderer: _renderPage,
                              builders: PdfViewBuilders<DefaultBuilderOptions>(
                                options: const DefaultBuilderOptions(),
                                pageBuilder: _pageBuilder,
                              ),
                              onDocumentLoaded: (doc) =>
                                  setState(() => _pageCount = doc.pagesCount),
                              onPageChanged: (page) =>
                                  setState(() => _currentPage = page),
                            ),
                            // Saved highlights for the current page, mapped from
                            // page-normalized coordinates back onto the displayed
                            // page bounds, in their saved colors.
                            for (final annotation in _annotations.where(
                              (a) =>
                                  a.pageNumber == _currentPage &&
                                  a.type == 'highlight',
                            ))
                              for (final rect in annotation.rects)
                                Positioned(
                                  left: pageRect.left + rect.x * pageRect.width,
                                  top: pageRect.top + rect.y * pageRect.height,
                                  width: rect.width * pageRect.width,
                                  height: rect.height * pageRect.height,
                                  child: IgnorePointer(
                                    child: Container(
                                      color: parseHexColor(
                                        annotation.color,
                                      ).withValues(alpha: 0.35),
                                    ),
                                  ),
                                ),
                            // Saved pen strokes + the stroke being drawn.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _InkOverlayPainter(
                                    annotations: _annotations,
                                    currentPage: _currentPage,
                                    pageRect: pageRect,
                                    liveStroke: _inkPoints,
                                    liveColor: _color,
                                  ),
                                ),
                              ),
                            ),
                            // Sticky-note badge: page notes have no position, so
                            // surface them with a visible marker instead of
                            // hiding them behind a menu.
                            if (_currentPageNoteCount > 0)
                              Positioned(
                                top: pageRect.top + 8,
                                right: viewportSize.width - pageRect.right + 8,
                                child: Material(
                                  color: AppColors.warning,
                                  borderRadius: BorderRadius.circular(8),
                                  elevation: 2,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: _showPageAnnotations,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.sticky_note_2_rounded,
                                            size: 15,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$_currentPageNoteCount',
                                            style: AppTextStyles.micro.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_tool == _ViewerTool.highlight)
                              Positioned.fill(
                                child: GestureDetector(
                                  onPanStart: (details) => setState(() {
                                    _dragStart = details.localPosition;
                                    _dragCurrent = details.localPosition;
                                  }),
                                  onPanUpdate: (details) => setState(
                                    () => _dragCurrent = details.localPosition,
                                  ),
                                  onPanEnd: (_) {
                                    if (_dragStart != null &&
                                        _dragCurrent != null) {
                                      final rect = Rect.fromPoints(
                                        _dragStart!,
                                        _dragCurrent!,
                                      );
                                      if (rect.width > 8 && rect.height > 8) {
                                        _saveHighlight(rect, viewportSize);
                                      }
                                    }
                                    setState(() {
                                      _dragStart = null;
                                      _dragCurrent = null;
                                    });
                                  },
                                  child: CustomPaint(
                                    painter:
                                        _dragStart != null &&
                                            _dragCurrent != null
                                        ? _DragRectPainter(
                                            Rect.fromPoints(
                                              _dragStart!,
                                              _dragCurrent!,
                                            ),
                                            _color,
                                          )
                                        : null,
                                    child: Container(color: Colors.transparent),
                                  ),
                                ),
                              ),
                            if (_tool == _ViewerTool.draw)
                              Positioned.fill(
                                child: GestureDetector(
                                  onPanStart: (details) => setState(
                                    () => _inkPoints
                                      ..clear()
                                      ..add(details.localPosition),
                                  ),
                                  onPanUpdate: (details) => setState(
                                    () => _inkPoints.add(details.localPosition),
                                  ),
                                  onPanEnd: (_) => _saveInk(viewportSize),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                            if (_tool == _ViewerTool.erase)
                              Positioned.fill(
                                child: GestureDetector(
                                  onTapUp: (details) => _eraseAt(
                                    details.localPosition,
                                    viewportSize,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_controller != null)
                  _ViewerToolbar(
                    tool: _tool,
                    color: _color,
                    palette: _palette,
                    canUndo: _undoStack.isNotEmpty,
                    canRedo: _redoStack.isNotEmpty,
                    onTool: (tool) => setState(
                      () => _tool = _tool == tool ? _ViewerTool.pan : tool,
                    ),
                    onColor: (color) => setState(() => _color = color),
                    onUndo: _undo,
                    onRedo: _redo,
                    onAddNote: _addNote,
                  ),
              ],
            ),
    );
  }
}

/// Always-visible annotation toolbar under the page, modeled on the tool row
/// in the reference screenshot: undo/redo, pan hand, pen, highlighter,
/// eraser, note, and color dots when a drawing tool is active.
class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.tool,
    required this.color,
    required this.palette,
    required this.canUndo,
    required this.canRedo,
    required this.onTool,
    required this.onColor,
    required this.onUndo,
    required this.onRedo,
    required this.onAddNote,
  });

  final _ViewerTool tool;
  final Color color;
  final List<Color> palette;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<_ViewerTool> onTool;
  final ValueChanged<Color> onColor;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showColors =
        tool == _ViewerTool.highlight || tool == _ViewerTool.draw;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.slate700 : AppColors.slate200,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showColors)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in palette)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: InkWell(
                          onTap: () => onColor(c),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c
                                    ? AppColors.primary
                                    : (isDark
                                          ? AppColors.slate700
                                          : AppColors.slate200),
                                width: color == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                _ToolbarButton(
                  icon: Icons.undo_rounded,
                  label: 'Undo',
                  enabled: canUndo,
                  onTap: onUndo,
                ),
                _ToolbarButton(
                  icon: Icons.redo_rounded,
                  label: 'Redo',
                  enabled: canRedo,
                  onTap: onRedo,
                ),
                _ToolbarButton(
                  icon: Icons.back_hand_outlined,
                  label: 'Pan',
                  active: tool == _ViewerTool.pan,
                  onTap: () => onTool(_ViewerTool.pan),
                ),
                _ToolbarButton(
                  icon: Icons.draw_outlined,
                  label: 'Pen',
                  active: tool == _ViewerTool.draw,
                  onTap: () => onTool(_ViewerTool.draw),
                ),
                _ToolbarButton(
                  icon: Icons.border_color_rounded,
                  label: 'Highlight',
                  active: tool == _ViewerTool.highlight,
                  onTap: () => onTool(_ViewerTool.highlight),
                ),
                _ToolbarButton(
                  icon: Icons.cleaning_services_rounded,
                  label: 'Eraser',
                  active: tool == _ViewerTool.erase,
                  onTap: () => onTool(_ViewerTool.erase),
                ),
                _ToolbarButton(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Note',
                  onTap: onAddNote,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = !enabled
        ? (isDark ? AppColors.slate700 : AppColors.slate300)
        : active
        ? AppColors.primary
        : (isDark ? AppColors.slate400 : AppColors.slate500);
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTextStyles.micro.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragRectPainter extends CustomPainter {
  _DragRectPainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _DragRectPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}

/// Paints saved "ink" annotations (freehand pen strokes stored as ordered
/// page-relative points) plus the stroke currently being drawn.
class _InkOverlayPainter extends CustomPainter {
  _InkOverlayPainter({
    required this.annotations,
    required this.currentPage,
    required this.pageRect,
    required this.liveStroke,
    required this.liveColor,
  });

  final List<PdfAnnotation> annotations;
  final int currentPage;
  final Rect pageRect;
  final List<Offset> liveStroke;
  final Color liveColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      if (annotation.pageNumber != currentPage || annotation.type != 'ink') {
        continue;
      }
      if (annotation.rects.length < 2) continue;
      final widthFraction = double.tryParse(annotation.text) ?? 0.007;
      final paint = Paint()
        ..color = _PdfViewerScreenState.parseHexColor(annotation.color)
        ..strokeWidth = (widthFraction * pageRect.width).clamp(1.5, 12)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < annotation.rects.length; i++) {
        final r = annotation.rects[i];
        final p = Offset(
          pageRect.left + r.x * pageRect.width,
          pageRect.top + r.y * pageRect.height,
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    if (liveStroke.length >= 2) {
      final paint = Paint()
        ..color = liveColor
        ..strokeWidth = (0.007 * pageRect.width).clamp(1.5, 12)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(liveStroke.first.dx, liveStroke.first.dy);
      for (final p in liveStroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkOverlayPainter oldDelegate) => true;
}
