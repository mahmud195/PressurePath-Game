// Top-level smoke test — confirms the app launches and renders the
// HomeScreen's primary CTA without throwing. Detailed coverage lives in
// test/services, test/models, test/widgets, and integration_test/.

import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App launches and shows the Play Now CTA',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PressurePathApp());
    await tester.pump();
    expect(find.text('PressurePath'), findsOneWidget);
    expect(find.text('Play Now'), findsOneWidget);
  });
}
