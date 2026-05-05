// Unit tests for TrailPath — predefined factories, custom-photo factory,
// and graceful behavior with empty point lists.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/trail_path.dart';

import '../fixtures/test_trails.dart';

void main() {
  group('TrailPath.fromType', () {
    test('wave produces points spanning the canvas width', () {
      final t = TrailPath.fromType('wave', 400, 300);
      expect(t.type, 'wave');
      expect(t.name, 'wave');
      expect(t.isCustom, isFalse);
      expect(t.points, isNotEmpty);
      expect(t.points.first.dx, lessThan(t.points.last.dx));
      // All points should sit inside the canvas bounds.
      for (final p in t.points) {
        expect(p.dx, inInclusiveRange(0, 400));
        expect(p.dy, inInclusiveRange(0, 300));
      }
    });

    test('zigzag and spiral produce non-empty point sequences', () {
      final z = TrailPath.fromType('zigzag', 400, 300);
      final s = TrailPath.fromType('spiral', 400, 300);
      expect(z.points, isNotEmpty);
      expect(s.points, isNotEmpty);
    });

    test('unknown type yields an empty (but not null) trail', () {
      final unknown = TrailPath.fromType('martian', 400, 300);
      expect(unknown.points, isEmpty);
    });
  });

  group('TrailPath.fromPhoto', () {
    test('preserves points, isCustom, name, and thumbnailBytes', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final pts = [
        const Offset(10, 10),
        const Offset(50, 60),
        const Offset(100, 200),
      ];
      final t = TrailPath.fromPhoto(points: pts, thumbnailBytes: bytes);
      expect(t.isCustom, isTrue);
      expect(t.type, 'custom');
      expect(t.name, 'Photo Trail');
      expect(t.points, pts);
      expect(t.thumbnailBytes, bytes);
    });

    test('thumbnailBytes is optional', () {
      final t = TrailPath.fromPhoto(points: const [Offset(0, 0)]);
      expect(t.thumbnailBytes, isNull);
      expect(t.isCustom, isTrue);
    });
  });

  group('TrailPath — empty/edge cases', () {
    test('empty trail does not crash any consumers we test', () {
      final t = emptyTrail();
      expect(t.points, isEmpty);
      // Iterating is safe.
      double sum = 0;
      for (final p in t.points) {
        sum += p.dx;
      }
      expect(sum, 0);
    });

    test('long trail can be created with many points', () {
      final t = longTrail(count: 1000);
      expect(t.points.length, 1000);
    });
  });
}
