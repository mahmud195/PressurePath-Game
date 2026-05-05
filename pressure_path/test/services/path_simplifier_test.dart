// Unit tests for PathSimplifier — RDP simplification, Chaikin smoothing,
// uniform sampling, normalization, closest-point-on-path, and arc-length.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/services/path_simplifier.dart';

void main() {
  group('PathSimplifier.rdpSimplify', () {
    test('simplification reduces collinear point counts', () {
      // 100 collinear points along y = 0 should collapse to 2.
      final pts = List<Offset>.generate(100, (i) => Offset(i.toDouble(), 0));
      final simplified = PathSimplifier.rdpSimplify(pts, 1.0);
      expect(simplified.length, 2);
      expect(simplified.first, pts.first);
      expect(simplified.last, pts.last);
    });

    test('simplification preserves real corners', () {
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(50, 0),
        const Offset(50, 50),
        const Offset(100, 50),
      ];
      final simplified = PathSimplifier.rdpSimplify(pts, 1.0);
      // The two corners should survive simplification.
      expect(simplified.length, greaterThanOrEqualTo(3));
    });

    test('paths shorter than 3 points are returned unchanged', () {
      final pts = [const Offset(0, 0), const Offset(10, 0)];
      final simplified = PathSimplifier.rdpSimplify(pts, 1.0);
      expect(simplified, pts);
    });
  });

  group('PathSimplifier.chaikinSmooth', () {
    test('smoothing returns valid finite points', () {
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(50, 100),
        const Offset(100, 0),
        const Offset(150, 100),
      ];
      final smoothed = PathSimplifier.chaikinSmooth(pts, iterations: 2);
      expect(smoothed.length, greaterThan(pts.length));
      for (final p in smoothed) {
        expect(p.dx.isFinite, isTrue);
        expect(p.dy.isFinite, isTrue);
      }
    });

    test('smoothing keeps endpoints', () {
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(10, 20),
        const Offset(30, 5),
      ];
      final smoothed = PathSimplifier.chaikinSmooth(pts);
      expect(smoothed.first, pts.first);
      expect(smoothed.last, pts.last);
    });
  });

  group('PathSimplifier.sampleUniform', () {
    test('returns exactly the requested number of points', () {
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
      ];
      final sampled = PathSimplifier.sampleUniform(pts, 50);
      expect(sampled.length, 50);
    });

    test('first and last sample equal the polyline endpoints', () {
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 100),
      ];
      final sampled = PathSimplifier.sampleUniform(pts, 10);
      expect(sampled.first, pts.first);
      expect(sampled.last, pts.last);
    });

    test('zero-length polyline returns the start point repeatedly', () {
      final pts = <Offset>[const Offset(5, 5), const Offset(5, 5)];
      final sampled = PathSimplifier.sampleUniform(pts, 4);
      expect(sampled, [
        const Offset(5, 5),
        const Offset(5, 5),
        const Offset(5, 5),
        const Offset(5, 5),
      ]);
    });
  });

  group('PathSimplifier.normalizePoints', () {
    test('scales points from one canvas size to another', () {
      final pts = <Offset>[
        const Offset(50, 50),
        const Offset(100, 100),
      ];
      final scaled = PathSimplifier.normalizePoints(
        pts,
        const Size(100, 100),
        const Size(200, 400),
      );
      expect(scaled[0], const Offset(100, 200));
      expect(scaled[1], const Offset(200, 400));
    });

    test('zero source size returns the input unchanged', () {
      final pts = <Offset>[const Offset(1, 2)];
      final scaled = PathSimplifier.normalizePoints(
        pts,
        Size.zero,
        const Size(100, 100),
      );
      expect(scaled, pts);
    });
  });

  group('PathSimplifier.closestPointOnPath', () {
    test('finds the closest segment projection', () {
      final path = <Offset>[
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
      ];
      final result =
          PathSimplifier.closestPointOnPath(path, const Offset(50, 30));
      expect(result.distance, closeTo(30.0, 1e-6));
      expect(result.closest, const Offset(50, 0));
    });
  });

  group('PathSimplifier.totalArcLength', () {
    test('computes the sum of segment lengths', () {
      final path = <Offset>[
        const Offset(0, 0),
        const Offset(3, 4), // 5
        const Offset(3, 4 + 12), // +12
      ];
      expect(PathSimplifier.totalArcLength(path), closeTo(17.0, 1e-9));
    });

    test('single-point path has zero arc length', () {
      expect(PathSimplifier.totalArcLength([const Offset(0, 0)]), 0.0);
    });
  });
}
