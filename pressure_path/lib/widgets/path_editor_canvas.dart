import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/editable_path.dart';
import '../services/path_simplifier.dart';
import '../theme/app_theme.dart';

class PathEditorCanvas extends StatefulWidget {
  final Uint8List imageBytes;
  final PathEditorState editorState;
  final Size imageOriginalSize;

  const PathEditorCanvas({
    super.key,
    required this.imageBytes,
    required this.editorState,
    required this.imageOriginalSize,
  });

  @override
  State<PathEditorCanvas> createState() => _PathEditorCanvasState();
}

class _PathEditorCanvasState extends State<PathEditorCanvas> {
  ui.Image? _bgImage;
  List<Offset> _drawingPoints = [];
  Offset? _erasePos;

  @override
  void initState() {
    super.initState();
    _decodeImage();
    widget.editorState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.editorState.removeListener(_onStateChanged);
    _bgImage?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _bgImage = frame.image);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _bgImage = null);
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final pos = event.localPosition;
    final state = widget.editorState;

    switch (state.mode) {
      case EditorMode.select:
        String? found;
        double minDist = 18;
        for (final path in state.paths) {
          if (!path.isVisible) continue;
          final result = PathSimplifier.closestPointOnPath(path.points, pos);
          if (result.distance < minDist) {
            minDist = result.distance;
            found = path.id;
          }
        }
        state.selectPath(found);

      case EditorMode.draw:
        _drawingPoints = [pos];

      case EditorMode.erase:
        _handleErase(pos);

      case EditorMode.adjustPoints:
        if (state.selectedId != null) {
          final selected = state.selectedPath;
          if (selected != null) {
            for (int i = 0; i < selected.points.length; i++) {
              if ((selected.points[i] - pos).distance < 14) {
                state.selectedPointIndex = i;
                state.snapshot();
                return;
              }
            }
          }
        }

      case EditorMode.markStart:
        state.setStartMarker(pos);

      case EditorMode.markEnd:
        state.setEndMarker(pos);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final pos = event.localPosition;
    final state = widget.editorState;

    switch (state.mode) {
      case EditorMode.draw:
        if (_drawingPoints.isNotEmpty) {
          final last = _drawingPoints.last;
          if ((pos - last).distance > 4) {
            setState(() => _drawingPoints.add(pos));
          }
        }

      case EditorMode.erase:
        setState(() => _erasePos = pos);
        _handleErase(pos);

      case EditorMode.adjustPoints:
        if (state.selectedPointIndex != null && state.selectedId != null) {
          state.updatePoint(state.selectedId!, state.selectedPointIndex!, pos);
        }

      default:
        break;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final state = widget.editorState;

    if (state.mode == EditorMode.draw && _drawingPoints.length >= 2) {
      var simplified = PathSimplifier.rdpSimplify(_drawingPoints, 3.0);
      simplified = PathSimplifier.chaikinSmooth(simplified, iterations: 1);
      final colorIdx = state.paths.length % kEditorPalette.length;
      state.addPath(EditablePath(
        points: simplified,
        color: kEditorPalette[colorIdx],
      ));
    }

    setState(() {
      _drawingPoints = [];
      _erasePos = null;
    });

    if (state.mode == EditorMode.adjustPoints) {
      state.selectedPointIndex = null;
    }
  }

  void _handleErase(Offset pos) {
    final state = widget.editorState;
    final toDelete = <String>[];
    for (final path in state.paths) {
      for (final pt in path.points) {
        if ((pt - pos).distance < 22) {
          toDelete.add(path.id);
          break;
        }
      }
    }
    for (final id in toDelete) {
      state.deletePath(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: CustomPaint(
        painter: _EditorPainter(
          bgImage: _bgImage,
          state: widget.editorState,
          drawingPoints: _drawingPoints,
          erasePos: _erasePos,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final ui.Image? bgImage;
  final PathEditorState state;
  final List<Offset> drawingPoints;
  final Offset? erasePos;

  _EditorPainter({
    this.bgImage,
    required this.state,
    required this.drawingPoints,
    this.erasePos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background image with dark overlay
    if (bgImage != null) {
      final src = Rect.fromLTWH(0, 0, bgImage!.width.toDouble(), bgImage!.height.toDouble());
      final imgAspect = bgImage!.width / bgImage!.height;
      final canvasAspect = size.width / size.height;
      Rect dst;
      if (imgAspect > canvasAspect) {
        final h = size.width / imgAspect;
        dst = Rect.fromLTWH(0, (size.height - h) / 2, size.width, h);
      } else {
        final w = size.height * imgAspect;
        dst = Rect.fromLTWH((size.width - w) / 2, 0, w, size.height);
      }
      canvas.drawImageRect(bgImage!, src, dst, Paint());
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0x88000000),
      );
    }

    // 2. Draw each path
    for (final path in state.paths) {
      if (!path.isVisible || path.points.length < 2) continue;

      final isSelected = path.id == state.selectedId;

      // Glow for selected
      if (isSelected) {
        final glowPaint = Paint()
          ..color = path.color.withValues(alpha: 0.3)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        _drawPolyline(canvas, path.points, glowPaint);
      }

      // Main line
      final linePaint = Paint()
        ..color = isSelected ? path.color : path.color.withValues(alpha: 0.7)
        ..strokeWidth = isSelected ? 4 : 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      _drawPolyline(canvas, path.points, linePaint);
    }

    // 3. Control points for selected path in adjust mode
    if (state.selectedId != null && state.mode == EditorMode.adjustPoints) {
      final selected = state.selectedPath;
      if (selected != null) {
        for (int i = 0; i < selected.points.length; i++) {
          final pt = selected.points[i];
          final isActive = state.selectedPointIndex == i;

          if (isActive) {
            canvas.drawCircle(pt, 9, Paint()..color = const Color(0xFFFFD700));
            // Crosshair
            final crossPaint = Paint()
              ..color = Colors.white
              ..strokeWidth = 1;
            canvas.drawLine(pt - const Offset(12, 0), pt + const Offset(12, 0), crossPaint);
            canvas.drawLine(pt - const Offset(0, 12), pt + const Offset(0, 12), crossPaint);
          } else {
            canvas.drawCircle(pt, 7, Paint()..color = Colors.white);
            canvas.drawCircle(pt, 5, Paint()..color = selected.color);
          }
        }
      }
    }

    // 4. In-progress drawing
    if (drawingPoints.length >= 2) {
      final drawPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      _drawPolyline(canvas, drawingPoints, drawPaint);
    }

    // 5. START marker
    if (state.startMarker != null) {
      final pos = state.startMarker!;
      canvas.drawCircle(pos, 14, Paint()..color = AppColors.success);
      final tp = TextPainter(
        text: const TextSpan(
          text: 'S',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // 6. END marker
    if (state.endMarker != null) {
      final pos = state.endMarker!;
      canvas.drawCircle(pos, 14, Paint()..color = AppColors.warning);
      final tp = TextPainter(
        text: const TextSpan(
          text: 'E',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // 7. Erase indicator
    if (state.mode == EditorMode.erase && erasePos != null) {
      canvas.drawCircle(
        erasePos!,
        22,
        Paint()..color = AppColors.danger.withValues(alpha: 0.3),
      );
      canvas.drawCircle(
        erasePos!,
        22,
        Paint()
          ..color = AppColors.danger.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawPolyline(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) => true;
}
