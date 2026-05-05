// Widget tests for HomeScreen — verifies all CTA buttons exist, that
// "Create from Photo" is wired up, and that there are no overflow
// exceptions on small phone screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
}

void main() {
  testWidgets('HomeScreen shows all primary action buttons', (tester) async {
    await _pump(tester);
    expect(find.text('Play Now'), findsOneWidget);
    expect(find.text('Pressure Setup'), findsOneWidget);
    expect(find.text('Create from Photo'), findsOneWidget);
    expect(find.text('Doctor Mode'), findsOneWidget);
  });

  testWidgets('Create from Photo navigates to ImageCaptureScreen', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Create from Photo'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    // ImageCaptureScreen renders the Take Photo button.
    expect(find.text('Take Photo'), findsOneWidget);
  });

  testWidgets('Doctor Mode opens the PIN dialog (no leak)', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Doctor Mode'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Enter PIN'), findsOneWidget);
    // Close the dialog so widgets dispose cleanly.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
  });

  testWidgets('Renders without overflow on a 320x480 viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester);
    expect(tester.takeException(), isNull);
  });
}
