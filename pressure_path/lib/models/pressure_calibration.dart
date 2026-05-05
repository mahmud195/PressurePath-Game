class PressureThresholds {
  final double minAllowedPressure;
  final double maxAllowedPressure;
  final double warningPressureThreshold;
  final double failPressureThreshold;

  const PressureThresholds({
    required this.minAllowedPressure,
    required this.maxAllowedPressure,
    required this.warningPressureThreshold,
    required this.failPressureThreshold,
  });
}

enum PressureDifficulty {
  easy,
  normal,
  hard;

  String get storageKey {
    switch (this) {
      case PressureDifficulty.easy:
        return 'easy';
      case PressureDifficulty.normal:
        return 'normal';
      case PressureDifficulty.hard:
        return 'hard';
    }
  }

  String get label {
    switch (this) {
      case PressureDifficulty.easy:
        return 'Easy';
      case PressureDifficulty.normal:
        return 'Normal';
      case PressureDifficulty.hard:
        return 'Hard';
    }
  }

  String get description {
    switch (this) {
      case PressureDifficulty.easy:
        return 'More forgiving';
      case PressureDifficulty.normal:
        return 'Balanced';
      case PressureDifficulty.hard:
        return 'Stricter control';
    }
  }

  PressureThresholds get thresholds {
    switch (this) {
      case PressureDifficulty.easy:
        return const PressureThresholds(
          minAllowedPressure: 0.08,
          maxAllowedPressure: 0.86,
          warningPressureThreshold: 0.74,
          failPressureThreshold: 0.94,
        );
      case PressureDifficulty.normal:
        return const PressureThresholds(
          minAllowedPressure: 0.10,
          maxAllowedPressure: 0.75,
          warningPressureThreshold: 0.65,
          failPressureThreshold: 0.85,
        );
      case PressureDifficulty.hard:
        return const PressureThresholds(
          minAllowedPressure: 0.12,
          maxAllowedPressure: 0.66,
          warningPressureThreshold: 0.56,
          failPressureThreshold: 0.74,
        );
    }
  }

  static PressureDifficulty fromStorageKey(String? value) {
    for (final difficulty in PressureDifficulty.values) {
      if (difficulty.storageKey == value) return difficulty;
    }
    return PressureDifficulty.normal;
  }
}

class PressureCalibration {
  final double calibratedMinPressure;
  final double calibratedNormalPressure;
  final double calibratedMaxPressure;
  final bool supportsPressure;
  final bool isCalibrated;
  final double sensitivityMultiplier;
  final PressureDifficulty selectedDifficulty;

  const PressureCalibration({
    required this.calibratedMinPressure,
    required this.calibratedNormalPressure,
    required this.calibratedMaxPressure,
    required this.supportsPressure,
    required this.isCalibrated,
    required this.sensitivityMultiplier,
    required this.selectedDifficulty,
  });

  factory PressureCalibration.defaultCalibration({
    PressureDifficulty selectedDifficulty = PressureDifficulty.normal,
  }) {
    return PressureCalibration(
      calibratedMinPressure: 0.0,
      calibratedNormalPressure: 0.45,
      calibratedMaxPressure: 1.0,
      supportsPressure: true,
      isCalibrated: false,
      sensitivityMultiplier: 0.75,
      selectedDifficulty: selectedDifficulty,
    );
  }

  factory PressureCalibration.fallbackCalibration({
    PressureDifficulty selectedDifficulty = PressureDifficulty.normal,
  }) {
    return PressureCalibration(
      calibratedMinPressure: 0.0,
      calibratedNormalPressure: 0.42,
      calibratedMaxPressure: 1.0,
      supportsPressure: false,
      isCalibrated: true,
      sensitivityMultiplier: 0.75,
      selectedDifficulty: selectedDifficulty,
    );
  }

  factory PressureCalibration.fromJson(Map<String, dynamic> json) {
    return PressureCalibration(
      calibratedMinPressure: _readDouble(json['calibratedMinPressure'], 0.0),
      calibratedNormalPressure: _readDouble(
        json['calibratedNormalPressure'],
        0.45,
      ),
      calibratedMaxPressure: _readDouble(json['calibratedMaxPressure'], 1.0),
      supportsPressure: json['supportsPressure'] == true,
      isCalibrated: json['isCalibrated'] == true,
      sensitivityMultiplier: _clamp(
        _readDouble(json['sensitivityMultiplier'], 0.75),
        0.35,
        1.25,
      ),
      selectedDifficulty: PressureDifficulty.fromStorageKey(
        json['selectedDifficulty'] as String?,
      ),
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    return {
      'calibratedMinPressure': calibratedMinPressure,
      'calibratedNormalPressure': calibratedNormalPressure,
      'calibratedMaxPressure': calibratedMaxPressure,
      'supportsPressure': supportsPressure,
      'isCalibrated': isCalibrated,
      'sensitivityMultiplier': sensitivityMultiplier,
      'selectedDifficulty': selectedDifficulty.storageKey,
    };
  }

  PressureCalibration copyWith({
    double? calibratedMinPressure,
    double? calibratedNormalPressure,
    double? calibratedMaxPressure,
    bool? supportsPressure,
    bool? isCalibrated,
    double? sensitivityMultiplier,
    PressureDifficulty? selectedDifficulty,
  }) {
    return PressureCalibration(
      calibratedMinPressure:
          calibratedMinPressure ?? this.calibratedMinPressure,
      calibratedNormalPressure:
          calibratedNormalPressure ?? this.calibratedNormalPressure,
      calibratedMaxPressure:
          calibratedMaxPressure ?? this.calibratedMaxPressure,
      supportsPressure: supportsPressure ?? this.supportsPressure,
      isCalibrated: isCalibrated ?? this.isCalibrated,
      sensitivityMultiplier:
          sensitivityMultiplier ?? this.sensitivityMultiplier,
      selectedDifficulty: selectedDifficulty ?? this.selectedDifficulty,
    ).normalized();
  }

  PressureCalibration normalized() {
    final safeMin = _clamp(calibratedMinPressure, 0.0, 10.0);
    final safeMax = _clamp(calibratedMaxPressure, safeMin + 0.01, 10.0);
    final safeNormal = _clamp(calibratedNormalPressure, safeMin, safeMax);
    return PressureCalibration(
      calibratedMinPressure: safeMin,
      calibratedNormalPressure: safeNormal,
      calibratedMaxPressure: safeMax,
      supportsPressure: supportsPressure,
      isCalibrated: isCalibrated,
      sensitivityMultiplier: _clamp(sensitivityMultiplier, 0.35, 1.25),
      selectedDifficulty: selectedDifficulty,
    );
  }

  PressureThresholds get thresholds => selectedDifficulty.thresholds;

  double get minAllowedPressure => thresholds.minAllowedPressure;

  double get maxAllowedPressure => thresholds.maxAllowedPressure;

  double get warningPressureThreshold => thresholds.warningPressureThreshold;

  double get failPressureThreshold => thresholds.failPressureThreshold;

  static double _readDouble(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    return fallback;
  }

  static double _clamp(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }
}
