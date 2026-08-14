import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Freehand sketch canvas (feature PDF, Notes: "Create freehand sketches and
/// annotations directly within notes for drawing anatomical diagrams,
/// flowcharts, and concept maps").
///
/// Used two ways:
/// - blank canvas from the note editor's pencil button (new sketch), and
/// - over a [background] image (annotate an attached photo/screenshot).
///
/// Pops with the flattened PNG bytes on Done, or null on discard.
class SketchScreen extends StatefulWidget {
  const SketchScreen({this.background, super.key});

  /// Optional image to draw on top of. When set, the exported PNG contains
  /// the image with the strokes flattened onto it.
  final Uint8List? background;

  @override
  State<SketchScreen> createState() => _SketchScreenState();
}

enum _SketchTool { pen, highlighter, eraser }

class _Stroke {
  _Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.isHighlighter,
  });

  final List<Offset> points;
  final Color color;
  final double width;
  final bool isHighlighter;

  Paint get paint => Paint()
    ..color = isHighlighter ? color.withValues(alpha: 0.35) : color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  bool hits(Offset point, double tolerance) {
    for (final p in points) {
      if ((p - point).distance <= tolerance + width / 2) return true;
    }
    return false;
  }
}

class _SketchScreenState extends State<SketchScreen> {
  static const _palette = [
    Colors.black,
    AppColors.danger,
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
  ];
  static const _widths = <String, double>{'Fine': 2.5, 'Medium': 5, 'Bold': 10};

  final List<_Stroke> _strokes = [];
  final List<_Stroke> _redo = [];
  _SketchTool _tool = _SketchTool.pen;
  Color _color = Colors.black;
  double _width = 5;
  ui.Image? _backgroundImage;
  bool _decodingBackground = false;

  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.background != null) {
      _decodingBackground = true;
      ui.decodeImageFromList(widget.background!, (image) {
        if (!mounted) return;
        setState(() {
          _backgroundImage = image;
          _decodingBackground = false;
        });
      });
    }
  }

  void _startStroke(Offset point) {
    if (_tool == _SketchTool.eraser) {
      _eraseAt(point);
      return;
    }
    setState(() {
      _redo.clear();
      _strokes.add(
        _Stroke(
          points: [point],
          color: _color,
          width: _tool == _SketchTool.highlighter ? _width * 3 : _width,
          isHighlighter: _tool == _SketchTool.highlighter,
        ),
      );
    });
  }

  void _extendStroke(Offset point) {
    if (_tool == _SketchTool.eraser) {
      _eraseAt(point);
      return;
    }
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(point));
  }

  void _eraseAt(Offset point) {
    final hit = _strokes.lastWhere(
      (s) => s.hits(point, 12),
      orElse: () => _Stroke(points: const [], color: Colors.black, width: 0, isHighlighter: false),
    );
    if (hit.points.isEmpty) return;
    setState(() {
      _strokes.remove(hit);
      _redo.clear();
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _redo.add(_strokes.removeLast()));
  }

  void _redoStroke() {
    if (_redo.isEmpty) return;
    setState(() => _strokes.add(_redo.removeLast()));
  }

  Future<void> _done() async {
    final renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    // Export at 2x for crisp results when the sketch is zoomed later.
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    final bg = _backgroundImage;
    if (bg != null) {
      final fitted = _backgroundRect(size, bg);
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        fitted,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    for (final stroke in _strokes) {
      _paintStroke(canvas, stroke);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || byteData == null) return;
    Navigator.of(context).pop(byteData.buffer.asUint8List());
  }

  static void _paintStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.width / 2,
        stroke.paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final p in stroke.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, stroke.paint);
  }

  static Rect _backgroundRect(Size canvasSize, ui.Image image) {
    final imageAspect = image.width / image.height;
    final canvasAspect = canvasSize.width / canvasSize.height;
    double width, height;
    if (imageAspect > canvasAspect) {
      width = canvasSize.width;
      height = width / imageAspect;
    } else {
      height = canvasSize.height;
      width = height * imageAspect;
    }
    return Rect.fromLTWH(
      (canvasSize.width - width) / 2,
      (canvasSize.height - height) / 2,
      width,
      height,
    );
  }

  Future<void> _confirmDiscard() async {
    if (_strokes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard sketch?'),
        content: const Text('Your drawing will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Discard',
            onPressed: _confirmDiscard,
          ),
          title: Text(widget.background == null ? 'Sketch' : 'Annotate image'),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo',
              onPressed: _strokes.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Redo',
              onPressed: _redo.isEmpty ? null : _redoStroke,
            ),
            FilledButton.icon(
              onPressed: _strokes.isEmpty && widget.background == null
                  ? null
                  : _done,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Done'),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _decodingBackground
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                      key: _canvasKey,
                      width: double.infinity,
                      color: Colors.white,
                      child: GestureDetector(
                        onPanStart: (d) => _startStroke(d.localPosition),
                        onPanUpdate: (d) => _extendStroke(d.localPosition),
                        child: CustomPaint(
                          painter: _SketchPainter(
                            strokes: _strokes,
                            background: _backgroundImage,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
            ),
            _ToolBar(
              tool: _tool,
              color: _color,
              width: _width,
              palette: _palette,
              widths: _widths,
              isDark: isDark,
              onTool: (t) => setState(() => _tool = t),
              onColor: (c) => setState(() {
                _color = c;
                if (_tool == _SketchTool.eraser) _tool = _SketchTool.pen;
              }),
              onWidth: (w) => setState(() => _width = w),
            ),
          ],
        ),
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({required this.strokes, this.background});

  final List<_Stroke> strokes;
  final ui.Image? background;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = background;
    if (bg != null) {
      final fitted = _SketchScreenState._backgroundRect(size, bg);
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        fitted,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    for (final stroke in strokes) {
      _SketchScreenState._paintStroke(canvas, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.color,
    required this.width,
    required this.palette,
    required this.widths,
    required this.isDark,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final _SketchTool tool;
  final Color color;
  final double width;
  final List<Color> palette;
  final Map<String, double> widths;
  final bool isDark;
  final ValueChanged<_SketchTool> onTool;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;

  @override
  Widget build(BuildContext context) {
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
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ToolButton(
                    icon: Icons.edit_rounded,
                    label: 'Pen',
                    active: tool == _SketchTool.pen,
                    onTap: () => onTool(_SketchTool.pen),
                  ),
                  _ToolButton(
                    icon: Icons.brush_rounded,
                    label: 'Highlighter',
                    active: tool == _SketchTool.highlighter,
                    onTap: () => onTool(_SketchTool.highlighter),
                  ),
                  _ToolButton(
                    icon: Icons.cleaning_services_rounded,
                    label: 'Eraser',
                    active: tool == _SketchTool.eraser,
                    onTap: () => onTool(_SketchTool.eraser),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: isDark ? AppColors.slate700 : AppColors.slate200,
                  ),
                  for (final entry in widths.entries)
                    _WidthButton(
                      label: entry.key,
                      value: entry.value,
                      active: width == entry.value,
                      onTap: () => onWidth(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
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
                          width: 28,
                          height: 28,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? AppColors.primary
        : (isDark ? AppColors.slate400 : AppColors.slate500);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
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
    );
  }
}

class _WidthButton extends StatelessWidget {
  const _WidthButton({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final double value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? AppColors.primary
        : (isDark ? AppColors.slate400 : AppColors.slate500);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 22,
              alignment: Alignment.center,
              child: Container(
                width: 22,
                height: value.clamp(2, 12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
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
    );
  }
}
