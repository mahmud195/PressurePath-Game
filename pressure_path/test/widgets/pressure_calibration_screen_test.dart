// Widget tests for PressureCalibrationScreen — instructions per phase,
// sample dot progress, fallback-after-flat-samples, and the Skip button
// landing on a calibrated fallback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/pressure_calibration.dart';
import 'package:pressure_path/screens/pressure_calibration_screen.dart';
import 'package:pressure_path/services/pressure_input_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _injectPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
}

Future<void> _tapWithPressure(
  WidgetTester tester,
  Finder target, {
  required double pressure,
}) async {
  // Pump a synthetic pointer-down event with a controlled pressure so
  // PressureCalibrationScreen records it as a sample.
  final center = tester.getCenter(target);
  final TestGesture gesture = await tester.createGesture(pointer: 1);
  await gesture.downWithCustomEvent(
    center,
    PointerDownEvent(
      pointer: 1,
      position: center,
      pressure: pressure,
      pressureMin: 0.0,
      pressureMax: 1.0,
    ),
  );
  await gesture.up();
  await tester.pump();
}

void main() {
  setUp(() async {
    await _injectPrefs({});
  });

  testWidgets('shows the "press normally" instruction first', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PressureCalibrationScreen()),
    );
    expect(find.text('Press normally on the screen 3 times.'), findsOneWidget);
  });

  testWidgets('after 3 normal samples, switches to firm-press instruction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PressureCalibrationScreen()),
    );
    final panel = find.byKey(const Key('calibrationSampleArea'));
    for (var i = 0; i < 3; i++) {
      await _tapWithPressure(tester, panel, pressure: 0.20 + i * 0.02);
    }
    await tester.pump();
    expect(find.text('Press a little harder 3 times.'), findsOneWidget);
  });

  testWidgets(
    'after 3 normal + 3 flat firm samples, lands on the fallback panel',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PressureCalibrationScreen()),
      );
      final panel = find.byKey(const Key('calibrationSampleArea'));
      // Six identical samples — calibrationSamplesSupportPressure returns
      // false because firmAvg ~= normalAvg, so we expect the fallback path.
      for (var i = 0; i < 6; i++) {
        await _tapWithPressure(tester, panel, pressure: 0.40);
      }
      // Allow the async _completeCalibration save to settle.
      await tester.pumpAndSettle();
      expect(
        find.text('Your device does not support real pressure detection.'),
        findsOneWidget,
      );
      // The Continue button is now available.
      expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget);
    },
  );

  testWidgets('Skip button saves a calibrated fallback and pops the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PressureCalibrationScreen()),
    );
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // After skipping, the loaded calibration should be the fallback —
    // unsupported but isCalibrated == true.
    final saved = await PressureInputService.loadCalibration();
    expect(saved.isCalibrated, isTrue);
    expect(saved.supportsPressure, isFalse);
  });

  testWidgets('difficulty selector exposes Easy / Normal / Hard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PressureCalibrationScreen()),
    );
    expect(find.text('Easy'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Hard'), findsOneWidget);
  });

  testWidgets('changing difficulty before saving propagates into the save', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PressureCalibrationScreen()),
    );
    await tester.tap(find.text('Hard'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final saved = await PressureInputService.loadCalibration();
    expect(saved.selectedDifficulty, PressureDifficulty.hard);
  });
}
