import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/payment_module_role.dart';
import 'package:todo/admin/payment_module_roles_panel.dart';

const role = PaymentModuleRole(
  id: 'A_revisor',
  empresaId: 'A',
  name: 'Revisión de pagos',
  level: 'auditoria',
);

void main() {
  Future<void> panel(
    WidgetTester tester, {
    List<PaymentModuleRole> roles = const [],
    Future<void> Function(String, String, String, bool, PaymentModuleRole?)?
    save,
    Future<void> Function(PaymentModuleRole)? sync,
    int pending = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            PaymentModuleRolesPanel(
              roles: roles,
              onSave: save ?? (_, _, _, _, _) async {},
              onSynchronize: sync ?? (_) async {},
              onCreateDefaults: () async {},
              pendingSyncCount: (_) => pending,
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('crear exige nombre y muestra las acciones del nivel elegido', (
    tester,
  ) async {
    String? saved;
    await panel(
      tester,
      save: (name, _, level, enabled, previous) async {
        expect(name, 'Firma contractual');
        expect(enabled, isTrue);
        expect(previous, isNull);
        saved = level;
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol').last);
    await tester.pump();
    expect(find.text('Escribe el nombre del rol'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Firma contractual',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerencia').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Firmar en gerencia'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol').last);
    await tester.pumpAndSettle();
    expect(saved, 'gerencia');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar permite desactivar y conserva la referencia del rol', (
    tester,
  ) async {
    bool? enabled;
    await panel(
      tester,
      roles: [role],
      save: (_, _, level, active, previous) async {
        expect(previous, role);
        expect(level, 'auditoria');
        enabled = active;
      },
    );
    await tester.tap(find.byTooltip('Editar Revisión de pagos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, 'Rol activo'),
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Rol activo'));
    await tester.pump();
    await tester.tap(find.text('Guardar y sincronizar'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sincronización muestra pendientes y bloquea doble envío', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    await panel(
      tester,
      roles: [role],
      pending: 3,
      sync: (_) async {
        calls++;
        await gate.future;
      },
    );
    expect(find.textContaining('3 persona(s) por sincronizar'), findsOneWidget);
    await tester.tap(find.text('Sincronizar asignados'));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Sincronizar asignados'),
          )
          .onPressed,
      isNull,
    );
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('móvil permite abrir y cancelar el creador sin desbordes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await panel(tester, roles: [role]);
    await tester.tap(find.text('Crear rol'));
    await tester.pumpAndSettle();
    expect(find.text('Crear rol de Planillas'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
