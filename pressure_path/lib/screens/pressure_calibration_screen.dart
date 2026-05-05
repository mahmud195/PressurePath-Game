import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/pressure_calibration.dart';
import '../models/trail_path.dart';
import '../services/pressure_input_service.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';

class PressureCalibrationScreen extends StatefulWidget {
  final TrailPath? customTrail;
  final PressureCalibration? initialCalibration;

  const PressureCalibrationScreen({
    super.key,
    this.customTrail,
    this.initialCalibration,
  });

  static Future<void> startGame(
    BuildContext context, {
    TrailPath? customTrail,
    bool forceCalibration = false,
    bool replace = false,
  }) async {
    final calibration = await PressureInputService.loadCalibration();
    if (!context.mounted) return;

    final Widget nextScreen = !forceCalibration && calibration.isCalibrated
        ? GameScreen(customTrail: customTrail)
        : PressureCalibrationScreen(
            customTrail: customTrail,
            initialCalibration: calibration,
          );
    final route = MaterialPageRoute(builder: (_) => nextScreen);

    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  State<PressureCalibrationScreen> createState() =>
      _PressureCalibrationScreenState();
}

enum _CalibrationPhase { normal, firm, fallbackReady }

class _PressureCalibrationScreenState extends State<PressureCalibrationScreen> {
  static const int _requiredSamples = 3;

  final List<_PressureSample> _normalSamples = [];
  final List<_PressureSample> _firmSamples = [];
  late PressureDifficulty _difficulty;
  late double _sensitivityMultiplier;
  _CalibrationPhase _phase = _CalibrationPhase.normal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialCalibration ?? PressureCalibration.defaultCalibration();
    _difficulty = initial.selectedDifficulty;
    _sensitivityMultiplier = initial.sensitivityMultiplier;
  }

  void _recordSample(PointerDownEvent event) {
    if (_saving || _phase == _CalibrationPhase.fallbackReady) return;

    final sample = _PressureSample.fromEvent(event);
    setState(() {
      if (_phase == _CalibrationPhase.normal) {
        _normalSamples.add(sample);
        if (_normalSamples.length >= _requiredSamples) {
          _phase = _CalibrationPhase.firm;
        }
      } else if (_phase == _CalibrationPhase.firm) {
        _firmSamples.add(sample);
      }
    });

    if (_normalSamples.length >= _requiredSamples &&
        _firmSamples.length >= _requiredSamples) {
      _completeCalibration();
    }
  }

  Future<void> _completeCalibration() async {
    if (_saving) return;
    setState(() => _saving = true);

    final allSamples = [..._normalSamples, ..._firmSamples];
    final allRaw = allSamples.map((sample) => sample.raw).toList();
    final hasOutOfRangeRaw = allSamples.any(
      (sample) => sample.rawOutsideEventRange,
    );
    final allGenericTouch = allSamples.every((sample) => sample.isGenericTouch);
    final minRaw = allRaw.reduce(math.min);
    final maxRaw = allRaw.reduce(math.max);
    final normalNormalized = hasOutOfRangeRaw
        ? _normalizeRawSamples(_normalSamples, minRaw, maxRaw)
        : _normalSamples.map((sample) => sample.normalized).toList();
    final firmNormalized = hasOutOfRangeRaw
        ? _normalizeRawSamples(_firmSamples, minRaw, maxRaw)
        : _firmSamples.map((sample) => sample.normalized).toList();
    final supportsPressure =
        !allGenericTouch &&
        PressureInputService.calibrationSamplesSupportPressure(
          normalSamples: normalNormalized,
          firmSamples: firmNormalized,
        );

    if (!supportsPressure) {
      final fallback = PressureCalibration.fallbackCalibration(
        selectedDifficulty: _difficulty,
      ).copyWith(sensitivityMultiplier: _sensitivityMultiplier);
      await PressureInputService.saveCalibration(fallback);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _phase = _CalibrationPhase.fallbackReady;
      });
      return;
    }

    final normalRaw = _normalSamples.map((sample) => sample.raw).toList();
    final normalAvg = _average(normalRaw);
    final spread = math.max(maxRaw - minRaw, 0.06);
    final calibratedMin = math.max(0.0, minRaw - spread * 0.15);
    final calibratedMax = math.max(
      maxRaw + spread * 0.10,
      calibratedMin + 0.08,
    );

    final calibration = PressureCalibration(
      calibratedMinPressure: calibratedMin,
      calibratedNormalPressure: normalAvg,
      calibratedMaxPressure: calibratedMax,
      supportsPressure: true,
      isCalibrated: true,
      sensitivityMultiplier: _sensitivityMultiplier,
      selectedDifficulty: _difficulty,
    ).normalized();

    await PressureInputService.saveCalibration(calibration);
    if (!mounted) return;
    _continueToGame();
  }

  Future<void> _skipCalibration() async {
    setState(() => _saving = true);
    final fallback = PressureCalibration.fallbackCalibration(
      selectedDifficulty: _difficulty,
    ).copyWith(sensitivityMultiplier: _sensitivityMultiplier);
    await PressureInputService.saveCalibration(fallback);
    if (!mounted) return;
    _continueToGame();
  }

  void _continueToGame() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(customTrail: widget.customTrail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final samplesForPhase = _phase == _CalibrationPhase.normal
        ? _normalSamples.length
        : _firmSamples.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Pressure Setup')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, AppColors.surface],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              children: [
                _DifficultySelector(
                  selected: _difficulty,
                  onChanged: (difficulty) {
                    if (_saving) return;
                    setState(() => _difficulty = difficulty);
                  },
                ),
                const SizedBox(height: 16),
                _SensitivitySlider(
                  value: _sensitivityMultiplier,
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() => _sensitivityMultiplier = value);
                        },
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: Listener(
                      key: const Key('calibrationSampleArea'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _recordSample,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.card.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _phase == _CalibrationPhase.fallbackReady
                                ? AppColors.warning.withValues(alpha: 0.7)
                                : AppColors.accent.withValues(alpha: 0.36),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _phase == _CalibrationPhase.fallbackReady
                                  ? Icons.touch_app_rounded
                                  : Icons.fingerprint_rounded,
                              size: 42,
                              color: _phase == _CalibrationPhase.fallbackReady
                                  ? AppColors.warning
                                  : AppColors.accent,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _instruction,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _phase == _CalibrationPhase.fallbackReady
                                  ? 'A safe touch mode will be used for this device.'
                                  : 'Tap inside this panel only.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                            if (_phase != _CalibrationPhase.fallbackReady) ...[
                              const SizedBox(height: 18),
                              _SampleDots(
                                count: samplesForPhase,
                                total: _requiredSamples,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _skipCalibration,
                        child: Text(
                          _phase == _CalibrationPhase.fallbackReady
                              ? 'Use Safe Mode'
                              : 'Skip',
                        ),
                      ),
                    ),
                    if (_phase == _CalibrationPhase.fallbackReady) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _continueToGame,
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _instruction {
    if (_phase == _CalibrationPhase.fallbackReady) {
      return 'Your device does not support real pressure detection.';
    }
    if (_phase == _CalibrationPhase.normal) {
      return 'Press normally on the screen 3 times.';
    }
    return 'Press a little harder 3 times.';
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  List<double> _normalizeRawSamples(
    List<_PressureSample> samples,
    double minRaw,
    double maxRaw,
  ) {
    final range = maxRaw - minRaw;
    if (range <= 0.0) return List<double>.filled(samples.length, 0.0);
    return samples
        .map((sample) => ((sample.raw - minRaw) / range).clamp(0.0, 1.0))
        .map((value) => value.toDouble())
        .toList();
  }
}

class _PressureSample {
  final double raw;
  final double normalized;
  final bool rawOutsideEventRange;
  final bool isGenericTouch;

  const _PressureSample({
    required this.raw,
    required this.normalized,
    required this.rawOutsideEventRange,
    required this.isGenericTouch,
  });

  factory _PressureSample.fromEvent(PointerDownEvent event) {
    final raw = _finiteOr(event.pressure, 0.0);
    final minPressure = _finiteOr(event.pressureMin, 0.0);
    final maxPressure = _finiteOr(event.pressureMax, 1.0);
    final normalized = maxPressure > minPressure
        ? _clamp((raw - minPressure) / (maxPressure - minPressure), 0.0, 1.0)
        : _clamp(raw, 0.0, 1.0);
    final rawOutsideEventRange =
        raw < minPressure - 0.001 || raw > maxPressure + 0.001;
    final isGenericTouch =
        event.kind == PointerDeviceKind.touch &&
        (minPressure - 0.0).abs() <= 0.001 &&
        (maxPressure - 1.0).abs() <= 0.001 &&
        !rawOutsideEventRange;
    return _PressureSample(
      raw: raw,
      normalized: normalized,
      rawOutsideEventRange: rawOutsideEventRange,
      isGenericTouch: isGenericTouch,
    );
  }

  static double _finiteOr(double value, double fallback) {
    return value.isFinite ? value : fallback;
  }

  static double _clamp(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }
}

class _DifficultySelector extends StatelessWidget {
  final PressureDifficulty selected;
  final ValueChanged<PressureDifficulty> onChanged;

  const _DifficultySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PressureDifficulty.values.map((difficulty) {
        final active = difficulty == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: active ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => onChanged(difficulty),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        difficulty.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        difficulty.description,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: active
                              ? Colors.white.withValues(alpha: 0.78)
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SensitivitySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _SensitivitySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pressure sensitivity',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0.55,
          max: 1.0,
          divisions: 9,
          activeColor: AppColors.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SampleDots extends StatelessWidget {
  final int count;
  final int total;

  const _SampleDots({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final active = index < count;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.success : AppColors.bg,
            border: Border.all(
              color: active ? AppColors.success : AppColors.muted,
            ),
          ),
        );
      }),
    );
  }
}
