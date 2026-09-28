import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_users_directory.dart';

void main() {
  Future<void> mount(WidgetTester tester, Size size, {int count = 2}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AdminUsersDirectory(
              people: [
                for (var i = 1; i <= count; i++)
                  AdminPersonSummary(
                    id: '$i',
                    name: 'Persona $i',
                    cargo: 'Profesional',
                    departamento: 'Talento Humano',
                    enabled: i != 2,
                  ),
              ],
              selectedId: selected,
              onSelected: (id) => setState(() => selected = id),
              avatarBuilder: (_) => const Icon(Icons.person_outline),
              detailBuilder: (id, {onNavigate}) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ficha $id'),
                  if (onNavigate != null)
                    TextButton(
                      onPressed: onNavigate,
                      child: const Text('Abrir permisos'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('web muestra tabla y la ficha de la persona seleccionada', (
    tester,
  ) async {
    await mount(tester, const Size(1440, 800));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('ficha 1'), findsNothing);
    await tester.tap(find.text('Persona 2'));
    await tester.pump();
    expect(find.text('ficha 2'), findsOneWidget);
    expect(find.text('ficha 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web estrecha abre la ficha sin desbordar la tabla', (
    tester,
  ) async {
    await mount(tester, const Size(900, 600));
    await tester.tap(find.text('Persona 1'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('ficha 1'), findsOneWidget);
    await tester.tap(find.text('Abrir permisos'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil conserva fichas compactas sin tabla', (tester) async {
    await mount(tester, const Size(390, 844));
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('ficha 1'), findsOneWidget);
    expect(find.text('ficha 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabla de personal pagina los listados largos', (tester) async {
    await mount(tester, const Size(1440, 1800), count: 21);
    expect(find.text('Persona 21'), findsNothing);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pump();
    expect(find.text('Persona 21'), findsOneWidget);
    expect(find.text('Persona 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
