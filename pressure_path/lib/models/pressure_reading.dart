import 'pressure_calibration.dart';

enum PressureState { safe, warning, tooStrong }

class PressureReading {
  final double raw;
  final double rawMin;
  final double rawMax;
  final double normalized;
  final double adjusted;
  final bool isSupported;
  final bool isFallback;
  final PressureState state;

  const PressureReading({
    required this.raw,
    required this.rawMin,
    required this.rawMax,
    required this.normalized,
    required this.adjusted,
    required this.isSupported,
    required this.isFallback,
    required this.state,
  });

  factory PressureReading.zero([PressureCalibration? calibration]) {
    final effective = calibration ?? PressureCalibration.fallbackCalibration();
    return PressureReading(
      raw: 0.0,
      rawMin: effective.calibratedMinPressure,
      rawMax: effective.calibratedMaxPressure,
      normalized: 0.0,
      adjusted: 0.0,
      isSupported: effective.supportsPressure,
      isFallback: !effective.supportsPressure,
      state: PressureState.safe,
    );
  }

  double get percent => adjusted * 100.0;
}
