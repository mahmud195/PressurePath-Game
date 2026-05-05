import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../models/editable_path.dart';
import '../models/trail_path.dart';
import '../services/edge_detection_service.dart';
import '../services/path_simplifier.dart';
import '../theme/app_theme.dart';
import '../widgets/path_editor_canvas.dart';
import 'pressure_calibration_screen.dart';

class PathEditorScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final EdgeDetectionResult detectionResult;

  const PathEditorScreen({
    super.key,
    required this.imageBytes,
    required this.detectionResult,
  });

  @override
  State<PathEditorScreen> createState() => _PathEditorScreenState();
}

class _PathEditorScreenState extends State<PathEditorScreen> {
  late final PathEditorState _editorState;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _editorState = PathEditorState();
    _editorState.addListener(_onEditorChanged);
    _initPaths();
  }

  void _initPaths() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canvasSize = _getCanvasSize();
      if (canvasSize == Size.zero) return;

      final result = widget.detectionResult;
      for (int i = 0; i < result.paths.length; i++) {
        final normalized = PathSimplifier.normalizePoints(
          result.paths[i],
          result.imageSize,
          canvasSize,
        );
        final colorIdx = i % kEditorPalette.length;
        _editorState.addPath(EditablePath(
          points: normalized,
          color: kEditorPalette[colorIdx],
        ));
      }
      _editorState.initHistory();
    });
  }

  Size _getCanvasSize() {
    final ctx = context;
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) return Size.zero;
    return renderBox.size;
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _editorState.removeListener(_onEditorChanged);
    _editorState.dispose();
    super.dispose();
  }

  Future<void> _onUseAsTrail() async {
    if (_editorState.startMarker == null || _editorState.endMarker == null) return;

    // Merge all visible paths
    final visiblePaths = _editorState.paths.where((p) => p.isVisible && p.points.isNotEmpty).toList();
    if (visiblePaths.isEmpty) return;

    List<Offset> merged;
    if (visiblePaths.length == 1) {
      merged = List.from(visiblePaths.first.points);
    } else {
      visiblePaths.sort((a, b) => a.start.dx.compareTo(b.start.dx));
      merged = [];
      for (final p in visiblePaths) {
        merged.addAll(p.points);
      }
    }

    // Uniform sample
    final sampled = PathSimplifier.sampleUniform(merged, 100);

    final trail = TrailPath.fromPhoto(
      points: sampled,
      thumbnailBytes: widget.imageBytes,
    );

    await PressureCalibrationScreen.startGame(
      context,
      customTrail: trail,
      replace: true,
    );
  }

  Future<bool> _onWillPop() async {
    if (_editorState.paths.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(I18n.t('discardChanges')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.t('discard'), style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final hasStartEnd = _editorState.startMarker != null && _editorState.endMarker != null;
    final selectedPath = _editorState.selectedPath;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) Navigator.pop(context);
            },
          ),
          title: Text(I18n.t('editPath')),
          actions: [
            IconButton(
              icon: Icon(Icons.undo,
                  color: _editorState.canUndo ? AppColors.text : AppColors.muted),
              onPressed: _editorState.canUndo ? () => _editorState.undo() : null,
            ),
            IconButton(
              icon: Icon(Icons.redo,
                  color: _editorState.canRedo ? AppColors.text : AppColors.muted),
              onPressed: _editorState.canRedo ? () => _editorState.redo() : null,
            ),
            TextButton(
              onPressed: hasStartEnd ? _onUseAsTrail : null,
              child: Text(
                I18n.t('useAsTrail'),
                style: TextStyle(
                  color: hasStartEnd ? AppColors.success : AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        endDrawer: _buildPathListDrawer(),
        body: Column(
          children: [
            // Canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PathEditorCanvas(
                    imageBytes: widget.imageBytes,
                    editorState: _editorState,
                    imageOriginalSize: widget.detectionResult.imageSize,
                  ),
                ),
              ),
            ),

            // Selected path actions
            if (selectedPath != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ActionChip(
                      label: I18n.t('smooth'),
                      icon: Icons.waves,
                      onTap: () => _editorState.smoothPath(selectedPath.id),
                    ),
                    _ActionChip(
                      label: I18n.t('simplify'),
                      icon: Icons.compress,
                      onTap: () => _editorState.simplifyPath(selectedPath.id),
                    ),
                    _ActionChip(
                      label: I18n.t('reverse'),
                      icon: Icons.swap_horiz,
                      onTap: () => _editorState.reversePath(selectedPath.id),
                    ),
                    _ActionChip(
                      label: I18n.t('delete'),
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      onTap: () => _editorState.deletePath(selectedPath.id),
                    ),
                  ],
                ),
              ),

            // Context hint
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _hintForMode(_editorState.mode),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ),

            // Mode toolbar
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ModeChip(
                            label: I18n.t('select'),
                            icon: Icons.near_me,
                            active: _editorState.mode == EditorMode.select,
                            onTap: () => _editorState.setMode(EditorMode.select),
                          ),
                          _ModeChip(
                            label: I18n.t('draw'),
                            icon: Icons.edit,
                            active: _editorState.mode == EditorMode.draw,
                            onTap: () => _editorState.setMode(EditorMode.draw),
                          ),
                          _ModeChip(
                            label: I18n.t('erase'),
                            icon: Icons.block,
                            active: _editorState.mode == EditorMode.erase,
                            onTap: () => _editorState.setMode(EditorMode.erase),
                          ),
                          _ModeChip(
                            label: I18n.t('adjust'),
                            icon: Icons.control_point,
                            active: _editorState.mode == EditorMode.adjustPoints,
                            onTap: () => _editorState.setMode(EditorMode.adjustPoints),
                          ),
                          _ModeChip(
                            label: I18n.t('start'),
                            icon: Icons.play_arrow,
                            active: _editorState.mode == EditorMode.markStart,
                            onTap: () => _editorState.setMode(EditorMode.markStart),
                            color: AppColors.success,
                          ),
                          _ModeChip(
                            label: I18n.t('end'),
                            icon: Icons.stop,
                            active: _editorState.mode == EditorMode.markEnd,
                            onTap: () => _editorState.setMode(EditorMode.markEnd),
                            color: AppColors.warning,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.list, color: AppColors.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  String _hintForMode(EditorMode mode) {
    switch (mode) {
      case EditorMode.select:
        return I18n.t('hintSelect');
      case EditorMode.draw:
        return I18n.t('hintDraw');
      case EditorMode.erase:
        return I18n.t('hintErase');
      case EditorMode.adjustPoints:
        return I18n.t('hintAdjust');
      case EditorMode.markStart:
        return I18n.t('hintMarkStart');
      case EditorMode.markEnd:
        return I18n.t('hintMarkEnd');
    }
  }

  Widget _buildPathListDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Paths (${_editorState.paths.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _editorState.paths.length,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (ctx, i) {
                  final path = _editorState.paths[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: path.id == _editorState.selectedId
                          ? AppColors.card
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: path.color,
                        ),
                      ),
                      title: Text('Path ${i + 1}',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${path.points.length} pts',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              path.isVisible ? Icons.visibility : Icons.visibility_off,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            onPressed: () => _editorState.toggleVisibility(path.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                            onPressed: () => _editorState.deletePath(path.id),
                          ),
                        ],
                      ),
                      onTap: () => _editorState.selectPath(path.id),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _editorState.smoothAll(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(I18n.t('smoothAll')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: Text(I18n.t('confirmClear')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(I18n.t('cancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(I18n.t('confirm'),
                                    style: const TextStyle(color: AppColors.danger)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) _editorState.clearAll();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      child: Text(I18n.t('clearAll')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? activeColor : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: active ? Colors.white : AppColors.muted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color ?? AppColors.text),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 11, color: color ?? AppColors.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
