import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

class TrailPath {
  final String name;
  final String type;
  final List<Offset> points;
  final bool isCustom;
  final Uint8List? thumbnailBytes;

  const TrailPath({
    required this.name,
    required this.type,
    required this.points,
    this.isCustom = false,
    this.thumbnailBytes,
  });

  factory TrailPath.fromType(String type, double w, double h, {int numPoints = 200}) {
    final pts = <Offset>[];
    final pad = 40.0;
    final usableW = w - pad * 2;
    final usableH = h - pad * 2;

    if (type == 'wave') {
      for (int i = 0; i <= numPoints; i++) {
        final t = i / numPoints;
        final x = pad + t * usableW;
        final y = pad + usableH * 0.5 + sin(t * pi * 3) * (usableH * 0.35);
        pts.add(Offset(x, y));
      }
    } else if (type == 'zigzag') {
      const segs = 5;
      for (int i = 0; i <= numPoints; i++) {
        final t = i / numPoints;
        final x = pad + t * usableW;
        final segT = (t * segs) % 1;
        final segIdx = (t * segs).floor();
        final goUp = segIdx % 2 == 0;
        final yStart = goUp ? pad + usableH * 0.85 : pad + usableH * 0.15;
        final yEnd = goUp ? pad + usableH * 0.15 : pad + usableH * 0.85;
        final y = yStart + (yEnd - yStart) * segT;
        pts.add(Offset(x, y));
      }
    } else if (type == 'spiral') {
      final cx = w / 2;
      final cy = h / 2;
      final maxR = min(usableW, usableH) * 0.45;
      for (int i = 0; i <= numPoints; i++) {
        final t = i / numPoints;
        final angle = t * pi * 4 + pi;
        final r = maxR * (1 - t * 0.75);
        final x = cx + cos(angle) * r;
        final y = cy + sin(angle) * r;
        pts.add(Offset(x, y));
      }
    }

    return TrailPath(name: type, type: type, points: pts);
  }

  factory TrailPath.fromPhoto({
    required List<Offset> points,
    Uint8List? thumbnailBytes,
  }) {
    return TrailPath(
      name: 'Photo Trail',
      type: 'custom',
      points: points,
      isCustom: true,
      thumbnailBytes: thumbnailBytes,
    );
  }
}
