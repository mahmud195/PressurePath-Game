// Test utility for synthesizing PointerEvents with controlled pressure
// values. This lets us drive PressureInputService without real hardware
// and exercise iPhone-unsupported, Android-sensitive, normal-stylus, and
// invalid-input device profiles.

import 'package:flutter/gestures.dart';

/// Profiles approximating real-world pressure-reporting behaviors.
enum FakeDeviceProfile {
  /// Many iPhones without 3D/Force Touch report a constant 1.0 (or 0.0)
  /// pressure with pressureMin == pressureMax. The service should detect
  /// this and switch to fallback / Safe Touch Mode.
  iPhoneUnsupported,

  /// Some Android devices report raw pressures well above 1.0 (often
  /// 0.8..2.5 depending on driver/digitizer). The service must normalize
  /// these against calibratedMin/Max so they don't always read as
  /// "tooStrong".
  androidSensitive,

  /// Stylus / Apple Pencil / well-behaved touch screens that report
  /// pressure cleanly inside [0.0, 1.0] with a meaningful range.
  normalStylus,

  /// Junk values: NaN, infinity, negative. The service must never crash
  /// or produce non-finite output.
  brokenInvalid,
}

/// A single fake pointer sample produced by the helpers below.
class FakePressureSample {
  final double pressure;
  final double pressureMin;
  final double pressureMax;
  final Offset position;

  const FakePressureSample({
    required this.pressure,
    required this.pressureMin,
    required this.pressureMax,
    this.position = const Offset(100, 100),
  });
}

/// Builds a [PointerDownEvent] with the requested pressure values so it
/// can be fed into [PressureInputService.read] or a Listener's
/// onPointerDown directly.
PointerDownEvent buildPointerDownEvent({
  required double pressure,
  double pressureMin = 0.0,
  double pressureMax = 1.0,
  Offset position = const Offset(100, 100),
  Duration timeStamp = Duration.zero,
  int pointer = 1,
  PointerDeviceKind kind = PointerDeviceKind.touch,
  double radiusMajor = 0.0,
  double radiusMinor = 0.0,
}) {
  return PointerDownEvent(
    timeStamp: timeStamp,
    pointer: pointer,
    position: position,
    kind: kind,
    pressure: pressure,
    pressureMin: pressureMin,
    pressureMax: pressureMax,
    radiusMajor: radiusMajor,
    radiusMinor: radiusMinor,
  );
}

/// Builds a [PointerMoveEvent] with the requested pressure values.
PointerMoveEvent buildPointerMoveEvent({
  required double pressure,
  double pressureMin = 0.0,
  double pressureMax = 1.0,
  Offset position = const Offset(100, 100),
  Offset delta = Offset.zero,
  Duration timeStamp = Duration.zero,
  int pointer = 1,
  PointerDeviceKind kind = PointerDeviceKind.touch,
  double radiusMajor = 0.0,
  double radiusMinor = 0.0,
}) {
  return PointerMoveEvent(
    timeStamp: timeStamp,
    pointer: pointer,
    position: position,
    delta: delta,
    kind: kind,
    pressure: pressure,
    pressureMin: pressureMin,
    pressureMax: pressureMax,
    radiusMajor: radiusMajor,
    radiusMinor: radiusMinor,
  );
}

/// Builds a [PointerUpEvent].
PointerUpEvent buildPointerUpEvent({
  Offset position = const Offset(100, 100),
  Duration timeStamp = Duration.zero,
  int pointer = 1,
}) {
  return PointerUpEvent(
    timeStamp: timeStamp,
    pointer: pointer,
    position: position,
  );
}

/// A sequence of light, comfortable touches inside the safe range — the
/// kind a relaxed user would produce. Uses a normal stylus profile.
List<PointerMoveEvent> createSafePressureSequence({
  int count = 20,
  double basePressure = 0.30,
  Offset start = const Offset(50, 100),
}) {
  final events = <PointerMoveEvent>[];
  for (var i = 0; i < count; i++) {
    // Add tiny variation so the spread/variance heuristics see a real
    // signal and don't classify it as constant/default.
    final wobble = ((i % 5) - 2) * 0.012;
    events.add(
      buildPointerMoveEvent(
        pressure: basePressure + wobble,
        pressureMin: 0.0,
        pressureMax: 1.0,
        position: Offset(start.dx + i * 4.0, start.dy),
        delta: const Offset(4, 0),
        timeStamp: Duration(milliseconds: i * 16),
        pointer: 1,
        kind: PointerDeviceKind.stylus,
      ),
    );
  }
  return events;
}

/// A short, very high-pressure spike — the kind that should NOT fail the
/// player on its own. The duration is below the fail-grace window.
List<PointerMoveEvent> createHighPressureSpike({
  int count = 4,
  double spikePressure = 0.98,
  Offset start = const Offset(50, 100),
  int millisBetweenSamples = 16,
}) {
  final events = <PointerMoveEvent>[];
  for (var i = 0; i < count; i++) {
    events.add(
      buildPointerMoveEvent(
        pressure: spikePressure,
        pressureMin: 0.0,
        pressureMax: 1.0,
        position: Offset(start.dx + i * 2.0, start.dy),
        delta: const Offset(2, 0),
        timeStamp: Duration(milliseconds: i * millisBetweenSamples),
        pointer: 1,
      ),
    );
  }
  return events;
}

/// Mimics an iPhone without Force/3D Touch: pressureMin == pressureMax,
/// pressure pinned at 1.0. The service should treat this as unsupported.
List<PointerMoveEvent> createUnsupportedPressureSequence({
  int count = 12,
  Offset start = const Offset(50, 100),
}) {
  final events = <PointerMoveEvent>[];
  for (var i = 0; i < count; i++) {
    events.add(
      buildPointerMoveEvent(
        pressure: 1.0,
        pressureMin: 1.0,
        pressureMax: 1.0,
        position: Offset(start.dx + i * 5.0, start.dy),
        delta: const Offset(5, 0),
        timeStamp: Duration(milliseconds: i * 16),
        pointer: 1,
      ),
    );
  }
  return events;
}

/// Android-style sensitive raw pressures (0.8..2.5). After calibration
/// these should normalize into a usable [0,1] range.
List<PointerMoveEvent> createAndroidSensitiveSequence({
  int count = 12,
  double rawMin = 0.8,
  double rawMax = 2.5,
  Offset start = const Offset(50, 100),
}) {
  final events = <PointerMoveEvent>[];
  for (var i = 0; i < count; i++) {
    final t = count == 1 ? 0.0 : i / (count - 1);
    final raw = rawMin + (rawMax - rawMin) * t;
    events.add(
      buildPointerMoveEvent(
        pressure: raw,
        // Many Android digitizers report a unit range even when the raw
        // value exceeds it, which is exactly the bug we want covered.
        pressureMin: 0.0,
        pressureMax: 1.0,
        position: Offset(start.dx + i * 4.0, start.dy),
        delta: const Offset(4, 0),
        timeStamp: Duration(milliseconds: i * 16),
        pointer: 1,
      ),
    );
  }
  return events;
}

/// NaN / infinity / negative inputs. The service must remain crash-free.
List<PointerMoveEvent> createInvalidPressureSequence({
  Offset start = const Offset(50, 100),
}) {
  final values = <double>[
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -1.5,
    -0.001,
  ];
  final events = <PointerMoveEvent>[];
  for (var i = 0; i < values.length; i++) {
    events.add(
      buildPointerMoveEvent(
        pressure: values[i],
        pressureMin: 0.0,
        pressureMax: 1.0,
        position: Offset(start.dx + i * 3.0, start.dy),
        delta: const Offset(3, 0),
        timeStamp: Duration(milliseconds: i * 16),
        pointer: 1,
      ),
    );
  }
  return events;
}

/// Convenience: a small batch of PointerDown events with the supplied
/// pressures, useful for driving the calibration screen.
List<PointerDownEvent> createCalibrationDownEvents({
  required List<double> pressures,
  double pressureMin = 0.0,
  double pressureMax = 1.0,
  Offset position = const Offset(160, 320),
}) {
  final events = <PointerDownEvent>[];
  for (var i = 0; i < pressures.length; i++) {
    events.add(
      buildPointerDownEvent(
        pressure: pressures[i],
        pressureMin: pressureMin,
        pressureMax: pressureMax,
        position: position,
        timeStamp: Duration(milliseconds: i * 100),
        pointer: i + 1,
      ),
    );
  }
  return events;
}
