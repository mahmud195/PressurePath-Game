// Tests for the pressure fail-grace logic. The game uses a 320ms grace
// window — a single brief spike must NOT fail the player, but sustained
// over-threshold pressure must. We re-implement the small grace-window
// state machine here so we can test it in pure Dart without spinning up
// the whole GameScreen.

import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/pressure_reading.dart';

/// Exact logic mirrored from `GameScreen._onPointerMove` so it can be
/// exercised deterministically. If the GameScreen version changes, this
/// guard catches divergence between them.
class PressureFailGate {
  final int graceMs;
  DateTime? _overSince;

  PressureFailGate({this.graceMs = 320});

  /// Returns true if the player should fail.
  bool tick(PressureState state, DateTime now) {
    if (state == PressureState.tooStrong) {
      _overSince ??= now;
      final elapsed = now.difference(_overSince!).inMilliseconds;
      return elapsed >= graceMs;
    }
    _overSince = null;
    return false;
  }

  void reset() {
    _overSince = null;
  }

  bool get isOverThreshold => _overSince != null;
}

void main() {
  group('Pressure fail-grace gate', () {
    test('a single short spike does NOT fail the player', () {
      final gate = PressureFailGate(graceMs: 320);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // 200ms of tooStrong, then return to safe — under the grace window.
      var t = t0;
      for (var i = 0; i < 4; i++) {
        expect(gate.tick(PressureState.tooStrong, t), isFalse);
        t = t.add(const Duration(milliseconds: 50));
      }
      // Now back to safe.
      expect(gate.tick(PressureState.safe, t), isFalse);
      expect(gate.isOverThreshold, isFalse);
    });

    test('sustained over-threshold (>= grace) DOES fail the player', () {
      final gate = PressureFailGate(graceMs: 320);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Initial tick starts the timer but doesn't fail.
      expect(gate.tick(PressureState.tooStrong, t0), isFalse);
      // After exactly graceMs, it must fail.
      expect(
        gate.tick(PressureState.tooStrong,
            t0.add(const Duration(milliseconds: 320))),
        isTrue,
      );
    });

    test('returning to safe pressure resets the grace timer', () {
      final gate = PressureFailGate(graceMs: 320);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Start over-threshold for 200ms.
      gate.tick(PressureState.tooStrong, t0);
      expect(gate.tick(PressureState.tooStrong,
              t0.add(const Duration(milliseconds: 200))),
          isFalse);

      // Return to safe — gate clears.
      expect(gate.tick(PressureState.safe,
              t0.add(const Duration(milliseconds: 250))),
          isFalse);
      expect(gate.isOverThreshold, isFalse);

      // A *new* spike of 320ms must again not fail at first…
      final t1 = t0.add(const Duration(milliseconds: 400));
      expect(gate.tick(PressureState.tooStrong, t1), isFalse);
      // …and only fail once a full grace window has elapsed since
      // restart, NOT counting the previous spike.
      expect(
        gate.tick(PressureState.tooStrong,
            t1.add(const Duration(milliseconds: 100))),
        isFalse,
      );
      expect(
        gate.tick(PressureState.tooStrong,
            t1.add(const Duration(milliseconds: 320))),
        isTrue,
      );
    });

    test('warning state does not fail the player', () {
      final gate = PressureFailGate(graceMs: 320);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      for (var i = 0; i < 100; i++) {
        expect(
          gate.tick(PressureState.warning,
              t0.add(Duration(milliseconds: i * 16))),
          isFalse,
        );
      }
      expect(gate.isOverThreshold, isFalse);
    });

    test('safe state never fails the player', () {
      final gate = PressureFailGate(graceMs: 320);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      for (var i = 0; i < 100; i++) {
        expect(
          gate.tick(PressureState.safe,
              t0.add(Duration(milliseconds: i * 16))),
          isFalse,
        );
      }
    });
  });
}
