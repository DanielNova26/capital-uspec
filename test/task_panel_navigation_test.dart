import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/task_responsive_layout.dart';

void main() {
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
