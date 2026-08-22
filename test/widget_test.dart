// test/widget_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/main.dart';

void main() {
  setUp(() {
    // Sin sesión guardada -> el AuthGate debe llevar al LoginScreen.
    SharedPreferences.setMockInitialValues({});

    // flutter_secure_storage no tiene plugin en el entorno de test:
    // mockeamos su canal para que las lecturas devuelvan null (no hay sesión).
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ToDoApp());

    // AuthGate decide de forma asíncrona y navega al LoginScreen.
    await tester.pump(); // microtasks + postFrameCallback
    await tester.pump(const Duration(seconds: 1)); // navegación + transición

    // La pantalla inicial muestra el formulario de inicio de sesión.
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
    expect(find.text('Usuario o Cédula'), findsOneWidget);
  });
}
