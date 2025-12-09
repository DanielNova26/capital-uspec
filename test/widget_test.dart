// test/widget_test.dart
import 'package:todo/main.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ToDoApp());
    // La pantalla inicial muestra el formulario de inicio de sesión.
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
    expect(find.text('Usuario o Cédula'), findsOneWidget);
  });
}
