// Widget tests for PressureIndicator — verifies color states, the
// "Safe Touch Mode" label, and that it lays out cleanly inside small
// screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/models/pressure_calibration.dart';
import 'package:pressure_path/models/pressure_reading.dart';
import 'package:pressure_path/theme/app_theme.dart';
import 'package:pressure_path/widgets/pressure_indicator.dart';

Widget _wrap(Widget child, {Size size = const Size(360, 640)}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox.fromSize(
        size: size,
        child: Row(children: [const Spacer(), child]),
      ),
    ),
  );
}

PressureReading _reading({
  required double adjusted,
  required PressureState state,
  bool isFallback = false,
}) {
  return PressureReading(
    raw: adjusted,
    rawMin: 0.0,
    rawMax: 1.0,
    normalized: adjusted,
    adjusted: adjusted,
    isSupported: !isFallback,
    isFallback: isFallback,
    state: state,
  );
}

void main() {
  testWidgets('safe state paints with the green trail color',
      (tester) async {
    final cal = PressureCalibration.defaultCalibration().copyWith(
      isCalibrated: true,
    );
    await tester.pumpWidget(_wrap(PressureIndicator(
      reading: _reading(adjusted: 0.20, state: PressureState.safe),
      calibration: cal,
    )));

    final fillFinder = find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        (w.decoration is BoxDecoration) &&
        (w.decoration as BoxDecoration).color == AppColors.trailGreen);
    expect(fillFinder, findsOneWidget);
  });

  testWidgets('warning state paints with the yellow trail color',
      (tester) async {
    final cal = PressureCalibration.defaultCalibration().copyWith(
      isCalibrated: true,
    );
    await tester.pumpWidget(_wrap(PressureIndicator(
      reading: _reading(adjusted: 0.70, state: PressureState.warning),
      calibration: cal,
    )));

    final fillFinder = find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        (w.decoration is BoxDecoration) &&
        (w.decoration as BoxDecoration).color == AppColors.trailYellow);
    expect(fillFinder, findsOneWidget);
  });

  testWidgets('tooStrong state paints with the red trail color',
      (tester) async {
    final cal = PressureCalibration.defaultCalibration().copyWith(
      isCalibrated: true,
    );
    await tester.pumpWidget(_wrap(PressureIndicator(
      reading: _reading(adjusted: 0.95, state: PressureState.tooStrong),
      calibration: cal,
    )));

    final fillFinder = find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        (w.decoration is BoxDecoration) &&
        (w.decoration as BoxDecoration).color == AppColors.trailRed);
    expect(fillFinder, findsOneWidget);
  });

  testWidgets('fallback reading shows the Safe Touch Mode label',
      (tester) async {
    final cal = PressureCalibration.fallbackCalibration();
    await tester.pumpWidget(_wrap(PressureIndicator(
      reading: _reading(
        adjusted: 0.40,
        state: PressureState.safe,
        isFallback: true,
      ),
      calibration: cal,
    )));

    expect(find.text('Safe\nTouch\nMode'), findsOneWidget);
  });

  testWidgets('non-fallback reading does NOT show the Safe Touch Mode label',
      (tester) async {
    final cal = PressureCalibration.defaultCalibration().copyWith(
      isCalibrated: true,
    );
    await tester.pumpWidget(_wrap(PressureIndicator(
      reading: _reading(adjusted: 0.40, state: PressureState.safe),
      calibration: cal,
    )));

    expect(find.text('Safe\nTouch\nMode'), findsNothing);
  });

  testWidgets('lays out cleanly on a small phone screen', (tester) async {
    // 320x480 — about as small as a real device gets these days.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cal = PressureCalibration.defaultCalibration().copyWith(
      isCalibrated: true,
    );

    await tester.pumpWidget(_wrap(
      PressureIndicator(
        reading: _reading(adjusted: 0.5, state: PressureState.warning),
        calibration: cal,
      ),
      size: const Size(320, 480),
    ));

    // No "RenderFlex overflowed" exceptions surfaced.
    expect(tester.takeException(), isNull);
  });
}
