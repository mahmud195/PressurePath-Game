// Unit tests for PressureCalibration — defaults, JSON round-trip,
// fallback safety, normalization, and per-difficulty thresholds.

import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/pressure_calibration.dart';

void main() {
  group('PressureCalibration — defaults', () {
    test('default calibration has valid pressure range', () {
      final cal = PressureCalibration.defaultCalibration();
      expect(cal.calibratedMinPressure, greaterThanOrEqualTo(0.0));
      expect(cal.calibratedMaxPressure, greaterThan(cal.calibratedMinPressure));
      expect(cal.calibratedNormalPressure,
          inInclusiveRange(cal.calibratedMinPressure, cal.calibratedMaxPressure));
      expect(cal.supportsPressure, isTrue);
      expect(cal.isCalibrated, isFalse,
          reason: 'Default calibration must NOT be marked as completed');
      expect(cal.sensitivityMultiplier, inInclusiveRange(0.35, 1.25));
    });

    test('fallback calibration is marked calibrated but unsupported', () {
      final cal = PressureCalibration.fallbackCalibration();
      expect(cal.supportsPressure, isFalse);
      expect(cal.isCalibrated, isTrue);
      expect(cal.calibratedMaxPressure, greaterThan(cal.calibratedMinPressure));
    });
  });

  group('PressureCalibration — JSON round-trip', () {
    test('toJson then fromJson preserves all fields', () {
      final original = PressureCalibration(
        calibratedMinPressure: 0.05,
        calibratedNormalPressure: 0.42,
        calibratedMaxPressure: 0.93,
        supportsPressure: true,
        isCalibrated: true,
        sensitivityMultiplier: 0.85,
        selectedDifficulty: PressureDifficulty.hard,
      );

      final round = PressureCalibration.fromJson(original.toJson());

      expect(round.calibratedMinPressure, closeTo(0.05, 1e-9));
      expect(round.calibratedNormalPressure, closeTo(0.42, 1e-9));
      expect(round.calibratedMaxPressure, closeTo(0.93, 1e-9));
      expect(round.supportsPressure, isTrue);
      expect(round.isCalibrated, isTrue);
      expect(round.sensitivityMultiplier, closeTo(0.85, 1e-9));
      expect(round.selectedDifficulty, PressureDifficulty.hard);
    });

    test('fromJson with junk values falls back to safe defaults', () {
      final junk = <String, dynamic>{
        'calibratedMinPressure': 'oops',
        'calibratedNormalPressure': null,
        'calibratedMaxPressure': double.nan,
        'supportsPressure': 'not-a-bool',
        'isCalibrated': null,
        'sensitivityMultiplier': 'broken',
        'selectedDifficulty': 'asteroid',
      };

      final cal = PressureCalibration.fromJson(junk);

      expect(cal.calibratedMinPressure, greaterThanOrEqualTo(0.0));
      expect(cal.calibratedMaxPressure, greaterThan(cal.calibratedMinPressure));
      expect(cal.calibratedNormalPressure,
          inInclusiveRange(cal.calibratedMinPressure, cal.calibratedMaxPressure));
      expect(cal.supportsPressure, isFalse);
      expect(cal.isCalibrated, isFalse);
      expect(cal.sensitivityMultiplier, inInclusiveRange(0.35, 1.25));
      expect(cal.selectedDifficulty, PressureDifficulty.normal);
    });

    test('sensitivityMultiplier is clamped on construction', () {
      final tooLow = PressureCalibration.defaultCalibration()
          .copyWith(sensitivityMultiplier: 0.05);
      final tooHigh = PressureCalibration.defaultCalibration()
          .copyWith(sensitivityMultiplier: 5.0);

      expect(tooLow.sensitivityMultiplier, greaterThanOrEqualTo(0.35));
      expect(tooHigh.sensitivityMultiplier, lessThanOrEqualTo(1.25));
    });

    test('normalized() repairs inverted min/max', () {
      final broken = PressureCalibration(
        calibratedMinPressure: 0.8,
        calibratedNormalPressure: 0.5,
        calibratedMaxPressure: 0.2,
        supportsPressure: true,
        isCalibrated: true,
        sensitivityMultiplier: 0.75,
        selectedDifficulty: PressureDifficulty.normal,
      );
      final fixed = broken.normalized();
      expect(fixed.calibratedMaxPressure,
          greaterThan(fixed.calibratedMinPressure));
      expect(fixed.calibratedNormalPressure,
          inInclusiveRange(fixed.calibratedMinPressure, fixed.calibratedMaxPressure));
    });
  });

  group('PressureCalibration — difficulty thresholds', () {
    test('easy is more permissive than normal which is more than hard', () {
      final easy = PressureDifficulty.easy.thresholds;
      final normal = PressureDifficulty.normal.thresholds;
      final hard = PressureDifficulty.hard.thresholds;

      expect(easy.failPressureThreshold,
          greaterThan(normal.failPressureThreshold));
      expect(normal.failPressureThreshold,
          greaterThan(hard.failPressureThreshold));

      expect(easy.warningPressureThreshold,
          greaterThan(normal.warningPressureThreshold));
      expect(normal.warningPressureThreshold,
          greaterThan(hard.warningPressureThreshold));
    });

    test('warning threshold is always below fail threshold', () {
      for (final d in PressureDifficulty.values) {
        expect(d.thresholds.warningPressureThreshold,
            lessThan(d.thresholds.failPressureThreshold),
            reason: 'Difficulty $d');
      }
    });

    test('storageKey round-trips through fromStorageKey', () {
      for (final d in PressureDifficulty.values) {
        expect(PressureDifficulty.fromStorageKey(d.storageKey), d);
      }
      expect(PressureDifficulty.fromStorageKey(null),
          PressureDifficulty.normal);
      expect(PressureDifficulty.fromStorageKey('asteroid'),
          PressureDifficulty.normal);
    });

    test('calibration exposes selected difficulty thresholds', () {
      final cal = PressureCalibration.defaultCalibration(
          selectedDifficulty: PressureDifficulty.hard);
      expect(cal.failPressureThreshold,
          PressureDifficulty.hard.thresholds.failPressureThreshold);
      expect(cal.warningPressureThreshold,
          PressureDifficulty.hard.thresholds.warningPressureThreshold);
    });
  });
}
