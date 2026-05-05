// Developer-only screen for simulating pressure inputs without real
// hardware. Gated behind kDebugMode — in release builds it shows a
// not-available notice instead of any controls.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/pressure_calibration.dart';
import '../models/pressure_reading.dart';
import '../services/pressure_input_service.dart';
import '../theme/app_theme.dart';

enum DebugDeviceProfile {
  iPhoneUnsupported,
  androidSensitive,
  normalDevice,
  invalidInput,
}

extension DebugDeviceProfileLabel on DebugDeviceProfile {
  String get label {
    switch (this) {
      case DebugDeviceProfile.iPhoneUnsupported:
        return 'iPhone (no pressure)';
      case DebugDeviceProfile.androidSensitive:
        return 'Android (sensitive)';
      case DebugDeviceProfile.normalDevice:
        return 'Normal device';
      case DebugDeviceProfile.invalidInput:
        return 'Invalid input';
    }
  }
}

class DebugPressureSimulationScreen extends StatefulWidget {
  const DebugPressureSimulationScreen({super.key});

  @override
  State<DebugPressureSimulationScreen> createState() =>
      _DebugPressureSimulationScreenState();
}

class _DebugPressureSimulationScreenState
    extends State<DebugPressureSimulationScreen> {
  late PressureInputService _service;
  PressureReading _reading = PressureReading.zero();
  DebugDeviceProfile _profile = DebugDeviceProfile.normalDevice;
  double _rawSlider = 0.4;
  Timer? _timer;
  int _ticker = 0;

  // Mirrored fail-grace state from GameScreen.
  DateTime? _overSince;
  static const _failGraceMs = 320;
  double _failProgress = 0.0;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _service = PressureInputService(
      calibration: PressureCalibration.defaultCalibration().copyWith(
        isCalibrated: true,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _resetSimulation() {
    _stop();
    setState(() {
      _ticker = 0;
      _overSince = null;
      _failProgress = 0.0;
      _isFailed = false;
      _service.reset();
      _reading = PressureReading.zero(_service.calibration);
    });
  }

  void _applyEvent(double pressure, {double pMin = 0.0, double pMax = 1.0}) {
    final event = PointerMoveEvent(
      timeStamp: Duration(milliseconds: _ticker * 16),
      pointer: 1,
      position: Offset(50.0 + (_ticker % 80) * 4, 200),
      delta: const Offset(4, 0),
      pressure: pressure,
      pressureMin: pMin,
      pressureMax: pMax,
    );
    final reading = _service.read(event);

    final now = DateTime.now();
    if (reading.state == PressureState.tooStrong) {
      _overSince ??= now;
      final elapsed = now.difference(_overSince!).inMilliseconds;
      _failProgress = (elapsed / _failGraceMs).clamp(0.0, 1.0);
      if (elapsed >= _failGraceMs) {
        _isFailed = true;
        _stop();
      }
    } else {
      _overSince = null;
      _failProgress = 0.0;
    }

    setState(() {
      _reading = reading;
      _ticker++;
    });
  }

  void _emitOnce() {
    final values = _valuesForProfile();
    _applyEvent(values.pressure, pMin: values.pMin, pMax: values.pMax);
  }

  ({double pressure, double pMin, double pMax}) _valuesForProfile() {
    switch (_profile) {
      case DebugDeviceProfile.iPhoneUnsupported:
        return (pressure: 1.0, pMin: 1.0, pMax: 1.0);
      case DebugDeviceProfile.androidSensitive:
        // Map slider [0,1] onto raw [0.8, 2.5] but clamp the
        // event-reported max to 1.0 (typical Android quirk).
        final raw = 0.8 + _rawSlider * 1.7;
        return (pressure: raw, pMin: 0.0, pMax: 1.0);
      case DebugDeviceProfile.normalDevice:
        return (pressure: _rawSlider, pMin: 0.0, pMax: 1.0);
      case DebugDeviceProfile.invalidInput:
        const choices = <double>[
          double.nan,
          double.infinity,
          double.negativeInfinity,
          -1.0,
        ];
        return (
          pressure: choices[_ticker % choices.length],
          pMin: 0.0,
          pMax: 1.0,
        );
    }
  }

  void _runStream(
    double pressure, {
    Duration period = const Duration(milliseconds: 16),
  }) {
    _stop();
    _timer = Timer.periodic(period, (_) {
      _applyEvent(pressure);
    });
  }

  void _simulateSafe() {
    _resetSimulation();
    _runStream(0.30);
  }

  void _simulateBriefSpike() {
    _resetSimulation();
    // A spike whose total duration is well under the fail-grace window.
    var ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      ticks++;
      _applyEvent(0.95);
      if (ticks >= 5) {
        t.cancel();
        // Drop back to safe so the player doesn't fail.
        _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
          _applyEvent(0.30);
        });
      }
    });
  }

  void _simulateLongHigh() {
    _resetSimulation();
    _runStream(0.95);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pressure Simulation')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Pressure simulation is only available in debug builds.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pressure Simulation (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Device profile',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DebugDeviceProfile.values.map((p) {
                final selected = p == _profile;
                return ChoiceChip(
                  label: Text(p.label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _profile = p);
                    _resetSimulation();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Raw'),
                Expanded(
                  child: Slider(
                    value: _rawSlider,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => setState(() => _rawSlider = v),
                    onChangeEnd: (_) => _emitOnce(),
                  ),
                ),
                Text(_rawSlider.toStringAsFixed(2)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _simulateSafe,
                  child: const Text('Simulate safe drawing'),
                ),
                ElevatedButton(
                  onPressed: _simulateBriefSpike,
                  child: const Text('Simulate pressure spike'),
                ),
                ElevatedButton(
                  onPressed: _simulateLongHigh,
                  child: const Text('Simulate long high pressure'),
                ),
                OutlinedButton(
                  onPressed: _resetSimulation,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Raw', _reading.raw.toStringAsFixed(3)),
                  _row('Normalized', _reading.normalized.toStringAsFixed(3)),
                  _row('Adjusted', _reading.adjusted.toStringAsFixed(3)),
                  _row('State', _reading.state.name),
                  _row('Fallback', _reading.isFallback.toString()),
                  _row(
                    'Fail timer',
                    '${(_failProgress * 100).round()}% of grace',
                  ),
                  _row('Failed', _isFailed.toString()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
