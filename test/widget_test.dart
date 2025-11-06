// test/widget_test.dart
import 'package:ToDo/main.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ToDoApp());
    expect(find.text('ToDo'), findsNothing); // Título es del MaterialApp
    // Ajusta tu expectativa real si tienes algún texto inicial visible:
    // expect(find.text('¡Capital Uspec listo!'), findsOneWidget);
  });
}
