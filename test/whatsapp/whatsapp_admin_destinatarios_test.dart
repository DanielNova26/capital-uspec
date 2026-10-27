import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/whatsapp_admin_panel.dart';
import 'package:todo/admin/whatsapp_admin_service.dart';
import 'package:todo/whatsapp/whatsapp_recipient_models.dart';

class _Servicio implements WhatsAppAdminService {
  List<WhatsAppDestinatario>? guardados;
  static const lista = WhatsAppListado(
    id: 'tesoreria',
    empresaId: 'e',
    nombre: 'Tesorería',
    modulos: ['planillas_pago'],
    destinatarios: [
      WhatsAppDestinatario(nombre: 'Ana Tesorería', telefono: '3001234567'),
    ],
  );
  @override
  Future<Map<String, dynamic>> estado({
    required String empresaId,
    required String userId,
  }) async => {
    'defaultCountryCode': '57',
    'modules': {'planillas_pago': true},
    'routes': {'planillas_gerencia_tesoreria': 'tesoreria'},
  };
  @override
  Stream<List<WhatsAppListado>> streamListados(String empresaId) =>
      Stream.value([lista]);
  @override
  Stream<List<Map<String, dynamic>>> streamReglasCorreo(String empresaId) =>
      Stream.value([]);
  @override
  Stream<List<Map<String, dynamic>>> streamEnvios(String empresaId) =>
      Stream.value([]);
  @override
  Stream<List<Map<String, dynamic>>> streamAuditoria(String empresaId) =>
      Stream.value([]);
  @override
  Future<String> guardarListado({
    required String empresaId,
    required String userId,
    required String listadoId,
    required String nombre,
    required bool activo,
    required List<String> modulos,
    required List<WhatsAppDestinatario> destinatarios,
  }) async {
    expect(empresaId, 'e');
    guardados = destinatarios;
    return 'tesoreria';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('explica firma a Tesorería y valida cada número $ancho', (
      tester,
    ) async {
      tester.view.physicalSize = Size(ancho, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final servicio = _Servicio();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: AdminWhatsAppPanel(
              userId: 'u',
              empresaId: 'e',
              service: servicio,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Al firmar Gerencia, Tesorería recibe'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Destinatarios de la lista seleccionada: Ana Tesorería',
        ),
        findsOneWidget,
      );
      final editar = find.byTooltip('Editar lista y destinatarios');
      await tester.ensureVisible(editar);
      await tester.pumpAndSettle();
      await tester.tap(editar);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Ejemplo Colombia: +57'),
        ),
        findsOneWidget,
      );
      final campo = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Celular con código de país',
      );
      await tester.ensureVisible(campo);
      await tester.enterText(campo, '123');
      await tester.tap(find.text('Guardar lista'));
      await tester.pumpAndSettle();
      expect(servicio.guardados, isNull);
      expect(
        find.textContaining('Revisa el número y su código'),
        findsOneWidget,
      );
      await tester.enterText(campo, '+57 300 123 4567');
      await tester.tap(find.text('Guardar lista'));
      await tester.pumpAndSettle();
      expect(servicio.guardados!.single.telefono, '573001234567');
      expect(tester.takeException(), isNull);
    });
  }
}
