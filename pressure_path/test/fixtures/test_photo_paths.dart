// Fixtures for photo / edge-detected path data. We deliberately avoid
// running real edge detection (which depends on Flutter's compute() and
// real image decoding) — instead we hand-craft EdgeDetectionResult
// instances that mimic what the detector would produce for a couple of
// canonical drawings.

import 'dart:ui';

import 'package:pressure_path/services/edge_detection_service.dart';

/// A single short straight segment from a 200x200 source image.
EdgeDetectionResult singleStraightSegment() {
  return EdgeDetectionResult(
    paths: [
      [
        const Offset(20, 100),
        const Offset(60, 100),
        const Offset(100, 100),
        const Offset(140, 100),
        const Offset(180, 100),
      ],
    ],
    imageSize: const Size(200, 200),
  );
}

/// Two disconnected segments — the path-merging behavior in the
/// PathEditor relies on having more than one path.
EdgeDetectionResult twoDisconnectedSegments() {
  return EdgeDetectionResult(
    paths: [
      [
        const Offset(10, 50),
        const Offset(40, 50),
        const Offset(70, 50),
        const Offset(100, 50),
      ],
      [
        const Offset(120, 150),
        const Offset(150, 150),
        const Offset(180, 150),
        const Offset(210, 150),
      ],
    ],
    imageSize: const Size(240, 200),
  );
}

/// A loopy curve — useful for testing simplification.
EdgeDetectionResult curvedSegment() {
  final pts = <Offset>[];
  for (var i = 0; i < 40; i++) {
    final t = i / 39.0;
    pts.add(Offset(40 + t * 200, 100 + 50 * (t * 6 % 1 - 0.5)));
  }
  return EdgeDetectionResult(paths: [pts], imageSize: const Size(300, 220));
}

/// Empty detection result — represents "no edges detected" UI state.
EdgeDetectionResult emptyDetection() {
  return const EdgeDetectionResult(paths: [], imageSize: Size(200, 200));
}
