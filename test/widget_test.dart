// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capital_uspec/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Capital Uspec'), findsNothing); // Título es del MaterialApp
    // Ajusta tu expectativa real si tienes algún texto inicial visible:
    // expect(find.text('¡Capital Uspec listo!'), findsOneWidget);
  });
}
