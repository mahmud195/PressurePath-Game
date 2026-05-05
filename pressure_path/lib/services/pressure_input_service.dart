import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pressure_calibration.dart';
import '../models/pressure_reading.dart';

class PressureInputService {
  static const String _prefsKey = 'pressure_calibration_v1';
  static const int _sampleWindow = 18;
  static const int _minRealPressureSamples = 6;
  static const double _realPressureSpread = 0.035;
  static const double _smoothingPreviousWeight = 0.75;
  static const double _smoothingNewWeight = 0.25;

  PressureCalibration _calibration;
  final List<double> _recentHardwareSamples = [];
  double? _previousAdjusted;
  Offset? _lastPosition;
  DateTime? _lastEventAt;
  DateTime? _lastDebugLogAt;

  PressureInputService({PressureCalibration? calibration})
    : _calibration = calibration ?? PressureCalibration.fallbackCalibration();

  PressureCalibration get calibration => _calibration;

  static Future<PressureCalibration> loadCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return PressureCalibration.defaultCalibration();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PressureCalibration.fromJson(decoded);
      }
      if (decoded is Map) {
        return PressureCalibration.fromJson(
          decoded.map((key, value) => MapEntry('$key', value)),
        );
      }
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
    return PressureCalibration.defaultCalibration();
  }

  static Future<void> saveCalibration(PressureCalibration calibration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(calibration.normalized().toJson()),
    );
  }

  static Future<void> clearCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static bool samplesShowRealPressure(List<double> normalizedSamples) {
    if (normalizedSamples.length < _minRealPressureSamples) return false;
    final finite = normalizedSamples.where((value) => value.isFinite).toList();
    if (finite.length < _minRealPressureSamples) return false;

    final minValue = finite.reduce(math.min);
    final maxValue = finite.reduce(math.max);
    final spread = maxValue - minValue;
    if (spread < _realPressureSpread) return false;

    final mean = finite.reduce((a, b) => a + b) / finite.length;
    final variance =
        finite
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        finite.length;
    return math.sqrt(variance) > 0.012;
  }

  static bool calibrationSamplesSupportPressure({
    required List<double> normalSamples,
    required List<double> firmSamples,
  }) {
    if (normalSamples.length < 3 || firmSamples.length < 3) return false;
    final all = [...normalSamples, ...firmSamples];
    if (!samplesShowRealPressure(all)) return false;

    final normalAvg = _average(normalSamples);
    final firmAvg = _average(firmSamples);
    return firmAvg > normalAvg + 0.025;
  }

  void updateCalibration(PressureCalibration calibration) {
    _calibration = calibration.normalized();
    reset();
  }

  void reset() {
    _recentHardwareSamples.clear();
    _previousAdjusted = null;
    _lastPosition = null;
    _lastEventAt = null;
    _lastDebugLogAt = null;
  }

  void endGesture() {
    _previousAdjusted = null;
    _lastPosition = null;
    _lastEventAt = null;
  }

  PressureReading read(PointerEvent event) {
    final now = DateTime.now();
    final raw = _finiteOr(
      event.pressure,
      _calibration.calibratedNormalPressure,
    );
    final rawMin = _finiteOr(event.pressureMin, 0.0);
    final rawMax = _finiteOr(event.pressureMax, 1.0);
    final hasEventRange = rawMax > rawMin;
    final eventNormalized = hasEventRange
        ? _clamp((raw - rawMin) / (rawMax - rawMin), 0.0, 1.0)
        : _clamp(raw, 0.0, 1.0);

    _trackHardwareSample(eventNormalized);

    final speed = _speedFor(event, now);
    final hasRealPressure = _hasUsableHardwarePressure(
      normalizedHardware: eventNormalized,
      hasEventRange: hasEventRange,
    );

    final normalized = hasRealPressure
        ? _normalizeHardwarePressure(raw, rawMin, rawMax)
        : _simulateFallbackPressure(event, speed);
    final isFallback = !hasRealPressure;
    final normalizedSafe = isFallback
        ? _clamp(
            normalized,
            _calibration.minAllowedPressure,
            _calibration.maxAllowedPressure,
          )
        : _clamp(normalized, 0.0, 1.0);
    final adjustedInput = _clamp(
      normalizedSafe * _calibration.sensitivityMultiplier,
      0.0,
      1.0,
    );
    final adjusted = _smooth(adjustedInput);
    final state = _stateFor(adjusted);

    _lastPosition = event.localPosition;
    _lastEventAt = now;

    final reading = PressureReading(
      raw: raw,
      rawMin: rawMin,
      rawMax: rawMax,
      normalized: normalizedSafe,
      adjusted: adjusted,
      isSupported: hasRealPressure,
      isFallback: isFallback,
      state: state,
    );
    _debugLog(reading);
    return reading;
  }

  bool _hasUsableHardwarePressure({
    required double normalizedHardware,
    required bool hasEventRange,
  }) {
    if (!_calibration.isCalibrated || !_calibration.supportsPressure) {
      return false;
    }
    if (!hasEventRange) return false;

    if (_recentHardwareSamples.length < _minRealPressureSamples) {
      return !_looksLikeDefaultPressure(normalizedHardware);
    }

    if (samplesShowRealPressure(_recentHardwareSamples)) return true;

    final minValue = _recentHardwareSamples.reduce(math.min);
    final maxValue = _recentHardwareSamples.reduce(math.max);
    final constantDefault =
        maxValue - minValue < 0.01 &&
        _recentHardwareSamples.every(_looksLikeDefaultPressure);
    return !constantDefault;
  }

  double _normalizeHardwarePressure(
    double raw,
    double eventMin,
    double eventMax,
  ) {
    var minPressure = _calibration.calibratedMinPressure;
    var maxPressure = _calibration.calibratedMaxPressure;
    if (maxPressure <= minPressure) {
      minPressure = eventMin;
      maxPressure = eventMax;
    }
    if (maxPressure <= minPressure) return 0.0;
    return _clamp((raw - minPressure) / (maxPressure - minPressure), 0.0, 1.0);
  }

  double _simulateFallbackPressure(PointerEvent event, double? speedPxPerMs) {
    final speed = speedPxPerMs ?? 0.55;
    final slowFactor = 1.0 - _clamp(speed / 1.35, 0.0, 1.0);
    var simulated = 0.32 + slowFactor * 0.18;

    final radiusMajor = _finiteOr(event.radiusMajor, 0.0);
    final radiusMinor = _finiteOr(event.radiusMinor, 0.0);
    if (radiusMajor > 0 && radiusMinor > 0) {
      final area = radiusMajor * radiusMinor;
      final areaSignal = _clamp((area - 40.0) / 310.0, 0.0, 1.0);
      simulated += areaSignal * 0.06;
    } else if (radiusMajor > 0) {
      final radiusSignal = _clamp((radiusMajor - 5.0) / 25.0, 0.0, 1.0);
      simulated += radiusSignal * 0.04;
    }

    return _clamp(simulated, 0.30, 0.56);
  }

  PressureState _stateFor(double adjustedPressure) {
    if (adjustedPressure >= _calibration.failPressureThreshold) {
      return PressureState.tooStrong;
    }
    if (adjustedPressure >= _calibration.warningPressureThreshold) {
      return PressureState.warning;
    }
    return PressureState.safe;
  }

  double _smooth(double adjustedInput) {
    final previous = _previousAdjusted;
    final smoothed = previous == null
        ? adjustedInput
        : previous * _smoothingPreviousWeight +
              adjustedInput * _smoothingNewWeight;
    _previousAdjusted = _clamp(smoothed, 0.0, 1.0);
    return _previousAdjusted!;
  }

  double? _speedFor(PointerEvent event, DateTime now) {
    final lastPosition = _lastPosition;
    final lastEventAt = _lastEventAt;
    if (lastPosition == null || lastEventAt == null) return null;

    final elapsedMs = now.difference(lastEventAt).inMilliseconds;
    if (elapsedMs <= 0) return null;
    final distance = (event.localPosition - lastPosition).distance;
    return distance / elapsedMs;
  }

  void _trackHardwareSample(double normalizedHardware) {
    if (!normalizedHardware.isFinite) return;
    _recentHardwareSamples.add(_clamp(normalizedHardware, 0.0, 1.0));
    if (_recentHardwareSamples.length > _sampleWindow) {
      _recentHardwareSamples.removeAt(0);
    }
  }

  bool _looksLikeDefaultPressure(double normalizedHardware) {
    return normalizedHardware <= 0.001 ||
        normalizedHardware >= 0.999 ||
        (normalizedHardware - 0.5).abs() <= 0.001;
  }

  void _debugLog(PressureReading reading) {
    if (!kDebugMode) return;

    final now = DateTime.now();
    final lastLog = _lastDebugLogAt;
    if (lastLog != null && now.difference(lastLog).inMilliseconds < 180) {
      return;
    }
    _lastDebugLogAt = now;

    final platform = '${kIsWeb ? 'web/' : ''}${defaultTargetPlatform.name}';
    debugPrint(
      'PressureInput platform=$platform '
      'raw=${reading.raw.toStringAsFixed(3)} '
      'range=${reading.rawMin.toStringAsFixed(3)}..${reading.rawMax.toStringAsFixed(3)} '
      'normalized=${reading.normalized.toStringAsFixed(3)} '
      'adjusted=${reading.adjusted.toStringAsFixed(3)} '
      'fallback=${reading.isFallback}',
    );
  }

  static double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _finiteOr(double value, double fallback) {
    return value.isFinite ? value : fallback;
  }

  static double _clamp(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }
}
