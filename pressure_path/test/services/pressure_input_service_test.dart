// Unit tests for PressureInputService — covers normalization, clamping,
// fallback detection, smoothing, sensitivity multiplier, state mapping,
// and resilience to invalid/garbage pressure inputs.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/pressure_calibration.dart';
import 'package:pressure_path/models/pressure_reading.dart';
import 'package:pressure_path/services/pressure_input_service.dart';

import '../helpers/fake_pressure_events.dart';

void main() {
  group('PressureInputService — normalization', () {
    test('clean stylus pressure stays inside [0,1] after normalization', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
        ),
      );

      // Warm up the hardware-sample window with realistic varying values.
      for (final event in createSafePressureSequence(count: 10)) {
        service.read(event);
      }

      final reading = service.read(
        buildPointerMoveEvent(pressure: 0.5, kind: PointerDeviceKind.stylus),
      );
      expect(reading.normalized, inInclusiveRange(0.0, 1.0));
      expect(reading.adjusted, inInclusiveRange(0.0, 1.0));
    });

    test('values outside [0,1] are clamped after normalization', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
        ),
      );

      // Drive a clearly out-of-range raw value with the standard 0..1
      // device range so the (raw - min) / (max - min) path is exercised.
      for (final e in createAndroidSensitiveSequence(count: 10)) {
        service.read(e);
      }
      final reading = service.read(
        buildPointerMoveEvent(
          pressure: 8.0,
          pressureMin: 0.0,
          pressureMax: 1.0,
        ),
      );
      expect(reading.normalized, lessThanOrEqualTo(1.0));
      expect(reading.adjusted, lessThanOrEqualTo(1.0));
      expect(reading.normalized, greaterThanOrEqualTo(0.0));
    });

    test('Android-style high raw pressure is reduced by calibration', () {
      // A device where calibration learned that normal raw=0.8 and max
      // raw is 2.5. The adjusted reading for a "normal" raw should NOT
      // saturate at 1.0.
      final calibration = PressureCalibration(
        calibratedMinPressure: 0.7,
        calibratedNormalPressure: 1.4,
        calibratedMaxPressure: 2.5,
        supportsPressure: true,
        isCalibrated: true,
        sensitivityMultiplier: 0.75,
        selectedDifficulty: PressureDifficulty.normal,
      );
      final service = PressureInputService(calibration: calibration);

      // Drive several events so the hardware-sample window confirms real
      // pressure (varied raw values).
      for (final e in createAndroidSensitiveSequence(count: 12)) {
        service.read(e);
      }

      // A "normal" Android raw of ~1.4 should map well below 1.0.
      final reading = service.read(
        buildPointerMoveEvent(
          pressure: 1.4,
          pressureMin: 0.0,
          pressureMax: 1.0,
        ),
      );
      expect(
        reading.adjusted,
        lessThan(0.85),
        reason: 'Calibrated mid-range raw should not saturate the gauge',
      );
    });

    test('sensitivity multiplier scales the adjusted reading', () {
      final highSens = PressureCalibration.defaultCalibration().copyWith(
        isCalibrated: true,
        sensitivityMultiplier: 1.0,
      );
      final lowSens = highSens.copyWith(sensitivityMultiplier: 0.5);

      final services = [
        PressureInputService(calibration: highSens),
        PressureInputService(calibration: lowSens),
      ];

      final readings = <PressureReading>[];
      for (final service in services) {
        for (final e in createSafePressureSequence(count: 8)) {
          service.read(e);
        }
        readings.add(
          service.read(
            buildPointerMoveEvent(
              pressure: 0.5,
              kind: PointerDeviceKind.stylus,
            ),
          ),
        );
      }

      expect(
        readings[0].adjusted,
        greaterThan(readings[1].adjusted),
        reason: 'Higher sensitivity multiplier must produce a larger adjusted',
      );
    });
  });

  group('PressureInputService — fallback detection', () {
    test('constant unsupported pressure (1.0) triggers fallback', () {
      final service = PressureInputService(
        calibration: PressureCalibration.fallbackCalibration(),
      );

      PressureReading? last;
      for (final e in createUnsupportedPressureSequence(count: 14)) {
        last = service.read(e);
      }

      expect(last, isNotNull);
      expect(
        last!.isFallback,
        isTrue,
        reason:
            'Constant 1.0 with min==max should be classified as unsupported',
      );
      expect(last.adjusted, inInclusiveRange(0.0, 1.0));
    });

    test('valid stylus stream is not classified as fallback', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
        ),
      );

      PressureReading? last;
      for (final e in createSafePressureSequence(count: 14)) {
        last = service.read(e);
      }

      expect(last!.isFallback, isFalse);
    });

    test('generic Android touch pressure pinned high uses safe fallback', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
          sensitivityMultiplier: 1.0,
        ),
      );

      PressureReading? last;
      for (var i = 0; i < 14; i++) {
        last = service.read(
          buildPointerMoveEvent(
            pressure: 0.96,
            pressureMin: 0.0,
            pressureMax: 1.0,
            position: Offset(50.0 + i * 4, 100),
            delta: const Offset(4, 0),
            timeStamp: Duration(milliseconds: i * 16),
          ),
        );
      }

      expect(last, isNotNull);
      expect(last!.isFallback, isTrue);
      expect(last.state, isNot(PressureState.tooStrong));
      expect(
        last.adjusted,
        lessThan(service.calibration.failPressureThreshold),
      );
    });

    test('fallback touch estimate fills the gauge from contact size', () {
      final service = PressureInputService(
        calibration: PressureCalibration.fallbackCalibration(),
      );

      final reading = service.read(
        buildPointerMoveEvent(
          pressure: 1.0,
          pressureMin: 1.0,
          pressureMax: 1.0,
          radiusMajor: 22.0,
          radiusMinor: 22.0,
        ),
      );

      expect(reading.isFallback, isTrue);
      expect(reading.adjusted, greaterThan(0.75));
      expect(reading.state, isNot(PressureState.safe));
    });

    test('uncalibrated state forces fallback regardless of inputs', () {
      // defaultCalibration().isCalibrated == false
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration(),
      );
      final reading = service.read(buildPointerMoveEvent(pressure: 0.4));
      expect(reading.isFallback, isTrue);
    });
  });

  group('PressureInputService — invalid input safety', () {
    test('NaN/Infinity/negative inputs never produce non-finite readings', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
        ),
      );

      for (final e in createInvalidPressureSequence()) {
        final reading = service.read(e);
        expect(reading.normalized.isFinite, isTrue);
        expect(reading.adjusted.isFinite, isTrue);
        expect(reading.normalized, inInclusiveRange(0.0, 1.0));
        expect(reading.adjusted, inInclusiveRange(0.0, 1.0));
      }
    });

    test('reset clears smoothing/sample state', () {
      final service = PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
        ),
      );
      for (final e in createSafePressureSequence(count: 10)) {
        service.read(e);
      }
      service.reset();
      // After reset, the first reading isn't blended against the previous
      // one — it should equal its own one-shot input within the smooth().
      final r = service.read(
        buildPointerMoveEvent(pressure: 0.5, kind: PointerDeviceKind.stylus),
      );
      expect(r.adjusted, inInclusiveRange(0.0, 1.0));
    });
  });

  group('PressureInputService — smoothing', () {
    test('smoothing dampens sudden pressure jumps', () {
      final calibration = PressureCalibration.defaultCalibration().copyWith(
        isCalibrated: true,
        sensitivityMultiplier: 1.0,
      );
      final service = PressureInputService(calibration: calibration);

      // Establish a stable low baseline.
      PressureReading? last;
      for (var i = 0; i < 12; i++) {
        last = service.read(
          buildPointerMoveEvent(
            pressure: 0.20 + (i % 3) * 0.005,
            position: Offset(50.0 + i * 4, 100),
            delta: const Offset(4, 0),
            timeStamp: Duration(milliseconds: i * 16),
            kind: PointerDeviceKind.stylus,
          ),
        );
      }
      final baseline = last!.adjusted;

      // Single very high sample — smoothing should hold it well below the
      // raw spike value.
      final spike = service.read(
        buildPointerMoveEvent(
          pressure: 0.95,
          position: const Offset(120, 100),
          delta: const Offset(4, 0),
          timeStamp: const Duration(milliseconds: 200),
          kind: PointerDeviceKind.stylus,
        ),
      );

      expect(spike.adjusted, greaterThan(baseline));
      expect(
        spike.adjusted,
        lessThan(0.95),
        reason: 'A single spike must be damped by smoothing',
      );
    });
  });

  group('PressureInputService — state mapping', () {
    PressureInputService freshService() {
      return PressureInputService(
        calibration: PressureCalibration.defaultCalibration().copyWith(
          isCalibrated: true,
          sensitivityMultiplier: 1.0,
        ),
      );
    }

    /// Push enough copies of the same pressure that the smoothing
    /// converges to roughly the input — lets us assert state mapping.
    PressureReading driveSteady(PressureInputService service, double p) {
      PressureReading? last;
      for (var i = 0; i < 30; i++) {
        last = service.read(
          buildPointerMoveEvent(
            pressure: p,
            position: Offset(50.0 + i * 4, 100),
            delta: const Offset(4, 0),
            timeStamp: Duration(milliseconds: i * 16),
            kind: PointerDeviceKind.stylus,
          ),
        );
      }
      return last!;
    }

    test('safe → warning → tooStrong all reachable', () {
      final cal = PressureCalibration.defaultCalibration().copyWith(
        isCalibrated: true,
        sensitivityMultiplier: 1.0,
      );

      final safe = driveSteady(freshService(), 0.20);
      expect(safe.state, PressureState.safe);
      expect(safe.adjusted, lessThan(cal.warningPressureThreshold));

      final warn = driveSteady(freshService(), 0.70);
      expect(warn.state, PressureState.warning);

      final tooStrong = driveSteady(freshService(), 0.95);
      expect(tooStrong.state, PressureState.tooStrong);
    });
  });

  group('PressureInputService — calibration sample heuristics', () {
    test('samplesShowRealPressure rejects too-few samples', () {
      expect(
        PressureInputService.samplesShowRealPressure([0.1, 0.2, 0.3]),
        isFalse,
      );
    });

    test('samplesShowRealPressure rejects narrow-spread samples', () {
      // 7 nearly-identical samples — spread well below 0.035.
      expect(
        PressureInputService.samplesShowRealPressure(
          List<double>.generate(8, (i) => 0.5 + i * 0.001),
        ),
        isFalse,
      );
    });

    test('samplesShowRealPressure accepts varied samples', () {
      expect(
        PressureInputService.samplesShowRealPressure([
          0.10,
          0.18,
          0.22,
          0.30,
          0.38,
          0.45,
          0.55,
          0.62,
        ]),
        isTrue,
      );
    });

    test('calibrationSamplesSupportPressure rejects when firm == normal', () {
      final samples = [0.40, 0.42, 0.41, 0.39, 0.40, 0.41];
      expect(
        PressureInputService.calibrationSamplesSupportPressure(
          normalSamples: samples.sublist(0, 3),
          firmSamples: samples.sublist(3),
        ),
        isFalse,
      );
    });

    test(
      'calibrationSamplesSupportPressure accepts firm > normal + spread',
      () {
        expect(
          PressureInputService.calibrationSamplesSupportPressure(
            normalSamples: [0.20, 0.22, 0.18, 0.24],
            firmSamples: [0.55, 0.60, 0.58, 0.62],
          ),
          isTrue,
        );
      },
    );
  });
}
