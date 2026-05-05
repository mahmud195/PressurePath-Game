// Reusable trail/path fixtures for unit and widget tests.

import 'dart:typed_data';
import 'dart:ui';

import 'package:pressure_path/models/trail_path.dart';

/// Simple two-point straight horizontal trail.
TrailPath straightTrail({double y = 100}) {
  return TrailPath(
    name: 'straight',
    type: 'straight',
    points: [Offset(20, y), Offset(380, y)],
  );
}

/// Multi-segment curved trail (smooth arc) with ~20 points.
TrailPath curvedTrail() {
  final points = <Offset>[];
  for (var i = 0; i <= 20; i++) {
    final t = i / 20.0;
    final x = 20 + t * 360;
    final y = 200 - 80 * (1 - (2 * t - 1) * (2 * t - 1));
    points.add(Offset(x, y));
  }
  return TrailPath(name: 'curved', type: 'curved', points: points);
}

/// Custom photo trail with thumbnail bytes — exercises the isCustom
/// branch and verifies thumbnail propagation.
TrailPath customPhotoTrail() {
  final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i));
  return TrailPath.fromPhoto(
    points: [
      const Offset(10, 10),
      const Offset(50, 30),
      const Offset(90, 70),
      const Offset(140, 120),
      const Offset(200, 180),
    ],
    thumbnailBytes: bytes,
  );
}

/// Empty / invalid trail — used to ensure consumers don't crash on it.
TrailPath emptyTrail() {
  return const TrailPath(name: 'empty', type: 'empty', points: []);
}

/// Long trail with many points — for sampling/simplification stress.
TrailPath longTrail({int count = 500}) {
  final points = <Offset>[];
  for (var i = 0; i < count; i++) {
    final t = i / (count - 1);
    final x = 10 + t * 600;
    final y = 200 + 60 * (t * 8 % 1 - 0.5);
    points.add(Offset(x, y));
  }
  return TrailPath(name: 'long', type: 'long', points: points);
}

/// A factory-derived wave trail at a known canvas size.
TrailPath waveTrailAt({double width = 400, double height = 400}) {
  return TrailPath.fromType('wave', width, height);
}

/// A factory-derived spiral trail at a known canvas size.
TrailPath spiralTrailAt({double width = 400, double height = 400}) {
  return TrailPath.fromType('spiral', width, height);
}

/// A factory-derived zigzag trail at a known canvas size.
TrailPath zigzagTrailAt({double width = 400, double height = 400}) {
  return TrailPath.fromType('zigzag', width, height);
}
