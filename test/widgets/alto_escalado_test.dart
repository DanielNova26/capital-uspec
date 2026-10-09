import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/alto_escalado.dart';

Future<double> _alto(WidgetTester tester, double escala, double base) async {
  late double resultado;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escala)),
        child: Builder(
          builder: (context) {
            resultado = altoEscalado(context, base);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return resultado;
}

void main() {
  testWidgets('con texto al 100 % conserva el alto base', (tester) async {
    expect(await _alto(tester, 1.0, 92), 92);
  });

  testWidgets('crece en proporción a la escala de texto', (tester) async {
    expect(await _alto(tester, 1.5, 100), closeTo(150, 0.5));
  });

  testWidgets('no pasa de 1,8× aunque el texto sea mayor', (tester) async {
    expect(await _alto(tester, 3.0, 100), closeTo(180, 0.5));
  });

  testWidgets('texto menor que 1 no encoge la tarjeta', (tester) async {
    expect(await _alto(tester, 0.8, 100), 100);
  });
}
