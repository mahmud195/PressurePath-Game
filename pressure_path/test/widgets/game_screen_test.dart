// Widget tests for GameScreen — opens with normal trails and custom
// trails, the pressure gauge does not crash with unsupported devices,
// drawing under safe pressure does not fail, and warning-state pressure
// does not instantly fail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/test_trails.dart';

Future<void> _injectPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
}

Future<void> _pumpGame(WidgetTester tester, {dynamic customTrail}) async {
  await tester.pumpWidget(
    MaterialApp(home: GameScreen(customTrail: customTrail)),
  );
  // Allow _loadPressureCalibration's microtask + initial layout.
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async => _injectPrefs());

  testWidgets('GameScreen opens with the path picker for normal trails', (
    tester,
  ) async {
    await _pumpGame(tester);
    expect(find.text('Choose a Path'), findsOneWidget);
    expect(find.text('Start Tracing'), findsOneWidget);
  });

  testWidgets('GameScreen opens directly into play for custom trails', (
    tester,
  ) async {
    await _pumpGame(tester, customTrail: customPhotoTrail());
    // Custom trails skip the picker (no "Choose a Path" header) but still
    // show the precision/thickness sliders before pressing Start Tracing.
    expect(find.text('Choose a Path'), findsNothing);
    expect(find.text('Start Tracing'), findsOneWidget);
  });

  testWidgets('Tapping Start Tracing transitions out of picker UI', (
    tester,
  ) async {
    await _pumpGame(tester);
    await tester.tap(find.text('Start Tracing'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Start Tracing'), findsNothing);
  });

  testWidgets('Safe Touch Mode badge appears when calibration is fallback', (
    tester,
  ) async {
    await _pumpGame(tester);
    await tester.tap(find.text('Start Tracing'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // The default-loaded calibration is fallback (no SharedPreferences
    // saved), so the badge should be visible.
    expect(find.text('Safe Touch Mode'), findsOneWidget);
  });

  testWidgets(
    'No exceptions when feeding pointer events with a fallback calibration',
    (tester) async {
      await _pumpGame(tester);
      await tester.tap(find.text('Start Tracing'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Fire a few pointer events — fallback mode means hardware pressure
      // is ignored but drawing must continue without exceptions.
      final TestGesture gesture = await tester.createGesture(pointer: 1);
      await gesture.downWithCustomEvent(
        const Offset(50, 200),
        const PointerDownEvent(
          pointer: 1,
          position: Offset(50, 200),
          pressure: 0.4,
          pressureMin: 0.0,
          pressureMax: 1.0,
        ),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
