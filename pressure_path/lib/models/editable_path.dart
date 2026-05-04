
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/path_simplifier.dart';

enum EditorMode { select, draw, erase, adjustPoints, markStart, markEnd }

class EditablePath {
  final String id;
  List<Offset> points;
  bool isSelected;
  bool isVisible;
  Color color;

  EditablePath({
    String? id,
    required this.points,
    this.isSelected = false,
    this.isVisible = true,
    required this.color,
  }) : id = id ?? const Uuid().v4();

  double get arcLength {
    double len = 0;
    for (int i = 1; i < points.length; i++) {
      len += (points[i] - points[i - 1]).distance;
    }
    return len;
  }

  Offset get start => points.first;
  Offset get end => points.last;

  EditablePath smoothed() {
    return EditablePath(
      id: id,
      points: PathSimplifier.chaikinSmooth(points, iterations: 2),
      isSelected: isSelected,
      isVisible: isVisible,
      color: color,
    );
  }

  EditablePath simplified() {
    return EditablePath(
      id: id,
      points: PathSimplifier.rdpSimplify(points, 3.0),
      isSelected: isSelected,
      isVisible: isVisible,
      color: color,
    );
  }

  EditablePath reversed() {
    return EditablePath(
      id: id,
      points: points.reversed.toList(),
      isSelected: isSelected,
      isVisible: isVisible,
      color: color,
    );
  }

  EditablePath copyWith({
    List<Offset>? points,
    bool? isSelected,
    bool? isVisible,
    Color? color,
  }) {
    return EditablePath(
      id: id,
      points: points ?? List.from(this.points),
      isSelected: isSelected ?? this.isSelected,
      isVisible: isVisible ?? this.isVisible,
      color: color ?? this.color,
    );
  }

  EditablePath deepCopy() {
    return EditablePath(
      id: id,
      points: List.from(points),
      isSelected: isSelected,
      isVisible: isVisible,
      color: color,
    );
  }
}

class PathEditorState extends ChangeNotifier {
  List<EditablePath> paths = [];
  EditorMode mode = EditorMode.select;
  String? selectedId;
  int? selectedPointIndex;
  Offset? startMarker;
  Offset? endMarker;

  final List<_Snapshot> _history = [];
  int _cursor = -1;

  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _history.length - 1;

  EditablePath? get selectedPath {
    if (selectedId == null) return null;
    final idx = paths.indexWhere((p) => p.id == selectedId);
    return idx >= 0 ? paths[idx] : null;
  }

  void snapshot() {
    if (_cursor < _history.length - 1) {
      _history.removeRange(_cursor + 1, _history.length);
    }
    _history.add(_Snapshot(
      paths: paths.map((p) => p.deepCopy()).toList(),
      startMarker: startMarker,
      endMarker: endMarker,
    ));
    _cursor = _history.length - 1;
  }

  void undo() {
    if (!canUndo) return;
    _cursor--;
    _restore(_history[_cursor]);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _cursor++;
    _restore(_history[_cursor]);
    notifyListeners();
  }

  void _restore(_Snapshot snap) {
    paths = snap.paths.map((p) => p.deepCopy()).toList();
    startMarker = snap.startMarker;
    endMarker = snap.endMarker;
    if (selectedId != null && !paths.any((p) => p.id == selectedId)) {
      selectedId = null;
      selectedPointIndex = null;
    }
  }

  void addPath(EditablePath p) {
    snapshot();
    paths.add(p);
    notifyListeners();
  }

  void deletePath(String id) {
    snapshot();
    paths.removeWhere((p) => p.id == id);
    if (selectedId == id) {
      selectedId = null;
      selectedPointIndex = null;
    }
    notifyListeners();
  }

  void toggleVisibility(String id) {
    final idx = paths.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      paths[idx].isVisible = !paths[idx].isVisible;
      notifyListeners();
    }
  }

  void selectPath(String? id) {
    selectedId = id;
    selectedPointIndex = null;
    for (final p in paths) {
      p.isSelected = p.id == id;
    }
    notifyListeners();
  }

  void updatePoint(String id, int index, Offset newPos) {
    final idx = paths.indexWhere((p) => p.id == id);
    if (idx >= 0 && index < paths[idx].points.length) {
      paths[idx].points[index] = newPos;
      notifyListeners();
    }
  }

  void smoothAll() {
    snapshot();
    for (int i = 0; i < paths.length; i++) {
      if (paths[i].isVisible) {
        paths[i] = paths[i].smoothed();
      }
    }
    notifyListeners();
  }

  void clearAll() {
    snapshot();
    paths.clear();
    selectedId = null;
    selectedPointIndex = null;
    startMarker = null;
    endMarker = null;
    notifyListeners();
  }

  void setStartMarker(Offset pos) {
    snapshot();
    startMarker = pos;
    mode = EditorMode.select;
    notifyListeners();
  }

  void setEndMarker(Offset pos) {
    snapshot();
    endMarker = pos;
    mode = EditorMode.select;
    notifyListeners();
  }

  void setMode(EditorMode m) {
    mode = m;
    notifyListeners();
  }

  void smoothPath(String id) {
    snapshot();
    final idx = paths.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      paths[idx] = paths[idx].smoothed();
      notifyListeners();
    }
  }

  void simplifyPath(String id) {
    snapshot();
    final idx = paths.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      paths[idx] = paths[idx].simplified();
      notifyListeners();
    }
  }

  void reversePath(String id) {
    snapshot();
    final idx = paths.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      paths[idx] = paths[idx].reversed();
      notifyListeners();
    }
  }

  void initHistory() {
    _history.clear();
    _cursor = -1;
    snapshot();
  }
}

class _Snapshot {
  final List<EditablePath> paths;
  final Offset? startMarker;
  final Offset? endMarker;

  _Snapshot({
    required this.paths,
    this.startMarker,
    this.endMarker,
  });
}

const List<Color> kEditorPalette = [
  Color(0xFF00BCD4),
  Color(0xFFCDDC39),
  Color(0xFFFF9800),
  Color(0xFFE91E63),
  Color(0xFFFFEB3B),
  Color(0xFF8BC34A),
  Color(0xFF03A9F4),
  Color(0xFFFF5722),
  Color(0xFF9C27B0),
  Color(0xFF009688),
];
