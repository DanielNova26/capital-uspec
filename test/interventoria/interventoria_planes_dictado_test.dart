import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_dictado.dart';

void main() {
  testWidgets(
    'dictar en dos hallazgos actualiza su borrador y recupera los controles de voz',
    (tester) async {
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'initialize' || call.method == 'listen'
            ? true
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final primero = TextEditingController(text: 'Vamos a');
      final segundo = TextEditingController(text: 'Se debe');
      addTearDown(primero.dispose);
      addTearDown(segundo.dispose);
      Future<void> native(String method, dynamic args) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
        await tester.pump();
      }

      Future<void> words(String value) => native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': value, 'confidence': 1.0},
          ],
          'finalResult': false,
        }),
      );
      Future<void> mostrar(String id, TextEditingController controller) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlanDictado(key: ValueKey(id), controller: controller),
              ),
            ),
          );

      await mostrar('h1', primero);
      await tester.tap(find.text('Dictar compromiso'));
      await tester.pumpAndSettle();
      await native('notifyStatus', 'listening');
      expect(find.text('Detener dictado'), findsOneWidget);
      await words('corregir el rotulado');
      expect(primero.text, 'Vamos a corregir el rotulado');

      await mostrar('h2', segundo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dictar compromiso'));
      await tester.pumpAndSettle();
      await native('notifyStatus', 'listening');
      expect(find.text('Detener dictado'), findsOneWidget);
      await words('ajustar las fechas');
      expect(segundo.text, 'Se debe ajustar las fechas');
      expect(primero.text, 'Vamos a corregir el rotulado');
      await native('notifyStatus', 'notListening');
      expect(find.text('Dictar compromiso'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
