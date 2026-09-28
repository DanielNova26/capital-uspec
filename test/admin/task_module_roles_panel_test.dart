import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/task_module_role.dart';
import 'package:todo/admin/task_module_roles_panel.dart';
import 'package:todo/admin/admin_access_workspace.dart';

const role = TaskModuleRole(
  id: 'A_equipo',
  empresaId: 'A',
  name: 'Líder de equipo',
  permissions: TaskRolePermissions(allAreas: false, viewTeam: true),
);

void main() {
  Future<void> panel(
    WidgetTester tester, {
    List<TaskModuleRole> roles = const [],
    Future<void> Function(
      String,
      String,
      TaskRolePermissions,
      bool,
      TaskModuleRole?,
    )?
    onSave,
    Future<void> Function(TaskModuleRole)? onSync,
    int pending = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            TaskModuleRolesPanel(
              roles: roles,
              onSave: onSave ?? (_, _, _, _, _) async {},
              onSynchronize: onSync ?? (_) async {},
              onCreateDefaults: () async {},
              pendingSyncCount: (_) => pending,
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('crear rol exige nombre y entrega permisos elegidos', (
    tester,
  ) async {
    TaskRolePermissions? saved;
    await panel(
      tester,
      onSave: (name, _, permissions, enabled, previous) async {
        expect(name, 'Seguimiento');
        expect(enabled, isTrue);
        expect(previous, isNull);
        saved = permissions;
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol').last);
    await tester.pump();
    expect(find.text('Escribe el nombre del rol'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Seguimiento');
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Ver tareas del equipo'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear rol').last);
    await tester.pumpAndSettle();
    expect(saved?.allAreas, isFalse);
    expect(saved?.viewTeam, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar conserva referencia y permite desactivar un rol', (
    tester,
  ) async {
    bool? enabled;
    await panel(
      tester,
      roles: [role],
      onSave: (_, _, permissions, active, previous) async {
        enabled = active;
        expect(previous, role);
        expect(permissions.viewTeam, isTrue);
      },
    );
    await tester.tap(find.byTooltip('Editar Líder de equipo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Rol activo'));
    await tester.pump();
    await tester.tap(find.text('Guardar y sincronizar'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sincronización pendiente se puede reintentar y bloquea doble envío',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await panel(
        tester,
        roles: [role],
        pending: 2,
        onSync: (_) async {
          calls++;
          await gate.future;
        },
      );
      expect(
        find.textContaining('2 persona(s) por sincronizar'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sincronizar asignados'));
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Sincronizar asignados'),
      );
      expect(button.onPressed, isNull);
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('móvil usa navegación compacta y formulario sin desbordes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminAccessWorkspace(
            selected: AdminAccessSection.modulos,
            onSelected: (_) {},
            sectionBuilder: (_) => ListView(
              children: [
                TaskModuleRolesPanel(
                  roles: [role],
                  onSave: (_, _, _, _, _) async {},
                  onSynchronize: (_) async {},
                  onCreateDefaults: () async {},
                  pendingSyncCount: (_) => 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.byType(DropdownButtonFormField<AdminAccessSection>),
      findsOneWidget,
    );
    await tester.tap(find.text('Crear rol'));
    await tester.pumpAndSettle();
    expect(find.text('Crear rol de Tareas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('web ofrece panel lateral y la sección elegida', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AdminAccessSection? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminAccessWorkspace(
            selected: AdminAccessSection.modulos,
            onSelected: (section) => picked = section,
            sectionBuilder: (_) => const Text('Inventario'),
          ),
        ),
      ),
    );
    expect(
      find.byType(DropdownButtonFormField<AdminAccessSection>),
      findsNothing,
    );
    await tester.tap(find.text('Configuración de apps'));
    expect(picked, AdminAccessSection.apps);
    expect(tester.takeException(), isNull);
  });
}
