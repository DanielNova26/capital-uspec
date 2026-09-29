import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_users_workspace.dart';

void main() {
  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: const _Harness())),
    );
  }

  testWidgets('web permite navegar sin montar herramientas no elegidas', (
    tester,
  ) async {
    await mount(tester, const Size(1440, 900));
    expect(
      find.byType(DropdownButtonFormField<AdminUsersSection>),
      findsNothing,
    );
    expect(find.text('contenido personas'), findsOneWidget);
    expect(find.text('contenido crear'), findsNothing);
    await tester.tap(find.text('Salud cargos'));
    await tester.pump();
    expect(find.text('contenido saludCargos'), findsOneWidget);
    expect(find.text('contenido personas'), findsNothing);
    await tester.tap(find.text('Perfiles generales'));
    await tester.pump();
    expect(find.text('contenido perfiles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil cambia de tarea con un selector compacto', (tester) async {
    await mount(tester, const Size(390, 844));
    expect(find.byType(ListTile), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<AdminUsersSection>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roles y permisos').last);
    await tester.pumpAndSettle();
    expect(find.text('contenido accesos'), findsOneWidget);
    expect(find.text('contenido personas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escritorio estrecho mantiene todas las operaciones accesibles', (
    tester,
  ) async {
    await mount(tester, const Size(900, 600));
    for (final section in AdminUsersSection.values) {
      await tester.ensureVisible(find.text(section.label));
      await tester.tap(find.text(section.label));
      await tester.pump();
      expect(find.text('contenido ${section.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  AdminUsersSection section = AdminUsersSection.personas;

  @override
  Widget build(BuildContext context) => AdminUsersWorkspace(
    selected: section,
    onSelected: (next) => setState(() => section = next),
    sectionBuilder: (selected) =>
        Center(child: Text('contenido ${selected.name}')),
  );
}
