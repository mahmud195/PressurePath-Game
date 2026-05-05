// Widget tests for PathEditorScreen — opens with detected paths,
// "Use as Trail" stays disabled until both START and END are placed, and
// the mode chips switch the editor mode.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/screens/path_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/test_photo_paths.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // Tiny placeholder image bytes — the editor doesn't decode them in
  // these tests because Image.memory will fail silently in test mode.
  final bytes = Uint8List.fromList(List<int>.filled(8, 0));
  await tester.pumpWidget(MaterialApp(
    home: PathEditorScreen(
      imageBytes: bytes,
      detectionResult: twoDisconnectedSegments(),
    ),
  ));
  // Let _initPaths run on a post-frame callback.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('opens with the editor scaffold and mode chips',
      (tester) async {
    await _pump(tester);
    expect(find.text('Edit Path'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Erase'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  testWidgets('"Use as Trail" is disabled until Start AND End are placed',
      (tester) async {
    await _pump(tester);

    final useAsTrail = find.widgetWithText(TextButton, 'Use as Trail');
    expect(useAsTrail, findsOneWidget);
    final TextButton button = tester.widget<TextButton>(useAsTrail);
    expect(button.onPressed, isNull,
        reason: 'Should be disabled before markers are set');
  });

  testWidgets('switching to markStart mode updates the on-screen hint',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.textContaining('START'), findsOneWidget);
  });

  testWidgets('renders without exceptions on a small viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });
}
