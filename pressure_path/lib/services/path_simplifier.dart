import 'dart:ui';


class PathSimplifier {
  /// Ramer-Douglas-Peucker polyline simplification.
  static List<Offset> rdpSimplify(List<Offset> points, double epsilon) {
    if (points.length < 3) return List.from(points);

    double maxDist = 0;
    int maxIdx = 0;

    final first = points.first;
    final last = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDist(points[i], first, last);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon) {
      final left = rdpSimplify(points.sublist(0, maxIdx + 1), epsilon);
      final right = rdpSimplify(points.sublist(maxIdx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  static double _perpendicularDist(Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) return (point - lineStart).distance;

    final t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / lenSq;
    final tClamped = t.clamp(0.0, 1.0);
    final proj = Offset(lineStart.dx + tClamped * dx, lineStart.dy + tClamped * dy);
    return (point - proj).distance;
  }

  /// Chaikin curve smoothing — subdivides corners into smooth curves.
  static List<Offset> chaikinSmooth(List<Offset> points, {int iterations = 2}) {
    if (points.length < 3) return List.from(points);

    var result = List<Offset>.from(points);

    for (int iter = 0; iter < iterations; iter++) {
      final smoothed = <Offset>[result.first];
      for (int i = 0; i < result.length - 1; i++) {
        final p0 = result[i];
        final p1 = result[i + 1];
        final q = Offset(p0.dx * 0.75 + p1.dx * 0.25, p0.dy * 0.75 + p1.dy * 0.25);
        final r = Offset(p0.dx * 0.25 + p1.dx * 0.75, p0.dy * 0.25 + p1.dy * 0.75);
        smoothed.add(q);
        smoothed.add(r);
      }
      smoothed.add(result.last);
      result = smoothed;
    }

    return result;
  }

  /// Resample a polyline into [count] evenly-spaced points by arc length.
  static List<Offset> sampleUniform(List<Offset> points, int count) {
    if (points.length < 2 || count < 2) return List.from(points);

    // Compute cumulative arc lengths
    final cumLen = <double>[0];
    for (int i = 1; i < points.length; i++) {
      cumLen.add(cumLen.last + (points[i] - points[i - 1]).distance);
    }
    final totalLen = cumLen.last;
    if (totalLen == 0) return List.filled(count, points.first);

    final result = <Offset>[];
    int segIdx = 0;

    for (int i = 0; i < count; i++) {
      final targetLen = (i / (count - 1)) * totalLen;

      while (segIdx < cumLen.length - 2 && cumLen[segIdx + 1] < targetLen) {
        segIdx++;
      }

      final segStart = cumLen[segIdx];
      final segEnd = cumLen[segIdx + 1];
      final segLen = segEnd - segStart;
      final t = segLen > 0 ? (targetLen - segStart) / segLen : 0.0;

      result.add(Offset(
        points[segIdx].dx + (points[segIdx + 1].dx - points[segIdx].dx) * t,
        points[segIdx].dy + (points[segIdx + 1].dy - points[segIdx].dy) * t,
      ));
    }

    return result;
  }

  /// Scale points from one coordinate space to another.
  static List<Offset> normalizePoints(List<Offset> points, Size from, Size to) {
    if (from.width == 0 || from.height == 0) return List.from(points);
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    return points.map((p) => Offset(p.dx * sx, p.dy * sy)).toList();
  }

  /// Find the closest point on a polyline path to a given point.
  static ({Offset closest, double distance}) closestPointOnPath(
    List<Offset> path,
    Offset point,
  ) {
    double minDist = double.infinity;
    Offset closest = path.first;

    for (int i = 0; i < path.length - 1; i++) {
      final result = _closestOnSegment(path[i], path[i + 1], point);
      if (result.distance < minDist) {
        minDist = result.distance;
        closest = result.closest;
      }
    }

    // Also check individual points
    for (final p in path) {
      final d = (p - point).distance;
      if (d < minDist) {
        minDist = d;
        closest = p;
      }
    }

    return (closest: closest, distance: minDist);
  }

  static ({Offset closest, double distance}) _closestOnSegment(
    Offset a,
    Offset b,
    Offset p,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) {
      final d = (p - a).distance;
      return (closest: a, distance: d);
    }

    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (closest: proj, distance: (p - proj).distance);
  }

  /// Compute total arc length of a polyline.
  static double totalArcLength(List<Offset> points) {
    double len = 0;
    for (int i = 1; i < points.length; i++) {
      len += (points[i] - points[i - 1]).distance;
    }
    return len;
  }
}
