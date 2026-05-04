import 'package:flutter_test/flutter_test.dart';
import 'package:pressure_path/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const PressurePathApp());
    expect(find.text('PressurePath'), findsOneWidget);
  });
}
