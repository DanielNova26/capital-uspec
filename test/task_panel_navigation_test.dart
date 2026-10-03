import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/task_responsive_layout.dart';

void main() {
  mainPanelCentrado();

  testWidgets('los paneles de tareas siempre ofrecen cierre visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  constraints: taskPanelConstraints(context),
                  builder: (_) => const SafeArea(
                    child: TaskPanelHeader(title: 'Novedades de la tarea'),
                  ),
                ),
                child: const Text('Abrir panel'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir panel'));
    await tester.pumpAndSettle();

    expect(find.text('Novedades de la tarea'), findsOneWidget);
    expect(find.byTooltip('Cerrar panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar panel'));
    await tester.pumpAndSettle();

    expect(find.text('Novedades de la tarea'), findsNothing);
    expect(find.text('Abrir panel'), findsOneWidget);
  });

  testWidgets('volver conserva el panel anterior de la tarea', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (parentContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TaskPanelHeader(title: 'Acciones de tarea'),
                      TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: parentContext,
                          builder: (detailContext) => TaskPanelHeader(
                            title: 'Novedades de la tarea',
                            onBack: () => Navigator.of(detailContext).pop(),
                          ),
                        ),
                        child: const Text('Ver novedades'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Abrir acciones'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver novedades'));
    await tester.pumpAndSettle();

    expect(find.text('Novedades de la tarea'), findsOneWidget);
    expect(find.byTooltip('Volver al panel anterior'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver al panel anterior'));
    await tester.pumpAndSettle();

    expect(find.text('Novedades de la tarea'), findsNothing);
    expect(find.text('Acciones de tarea'), findsOneWidget);
    expect(find.text('Ver novedades'), findsOneWidget);
  });
}

void _panelEn(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _appConPanel() => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showTaskPanel<void>(
            context: context,
            builder: (_) => const SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TaskPanelHandle(),
                  TaskPanelHeader(title: 'Acciones de tarea'),
                ],
              ),
            ),
          ),
          child: const Text('Abrir panel'),
        ),
      ),
    ),
  ),
);

// 3 oct 2026: "centrar la ventana de acciones". En pantallas amplias el panel
// es un diálogo centrado; en el teléfono sigue siendo la hoja inferior.
void mainPanelCentrado() {
  testWidgets('en Web amplia el panel sale centrado', (tester) async {
    _panelEn(tester, const Size(1366, 900));
    await tester.pumpWidget(_appConPanel());
    await tester.tap(find.text('Abrir panel'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    final centro = tester.getCenter(find.text('Acciones de tarea'));
    expect((centro.dy - 450).abs(), lessThan(200));

    await tester.tap(find.byTooltip('Cerrar panel'));
    await tester.pumpAndSettle();
    expect(find.text('Acciones de tarea'), findsNothing);
  });

  testWidgets('en el teléfono el panel es una hoja inferior', (tester) async {
    _panelEn(tester, const Size(390, 844));
    await tester.pumpWidget(_appConPanel());
    await tester.tap(find.text('Abrir panel'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
