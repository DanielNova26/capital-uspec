import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/widgets/task_card_grid.dart';
import 'package:todo/widgets/task_filters_panel.dart';

void main() {
  test('la grilla usa 3 columnas en 14", 2 en 10" y 1 en el teléfono', () {
    expect(taskGridColumnas(1300), 3);
    expect(taskGridColumnas(1100), 3);
    expect(taskGridColumnas(900), 2);
    expect(taskGridColumnas(720), 2);
    expect(taskGridColumnas(390), 1);
  });

  testWidgets('la grilla pagina de a 20 y agrupa con encabezado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = List.generate(25, (i) => i);
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TaskCardGrid<int>(
              items: items,
              page: page,
              onPageChanged: (p) => setState(() => page = p),
              grupoDe: (i) => i < 10 ? 'a' : 'b',
              nombreGrupo: (c) => c == 'a' ? 'Calidad' : 'Compras',
              itemBuilder: (context, i, compact) =>
                  SizedBox(height: 40, child: Text('T$i')),
            ),
          ),
        ),
      ),
    );
    expect(find.text('T0'), findsOneWidget);
    expect(find.text('T19'), findsOneWidget);
    expect(find.text('T20'), findsNothing);
    expect(find.text('CALIDAD'), findsOneWidget);
    expect(find.text('1-20 de 25 tareas'), findsOneWidget);

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('T20'), findsOneWidget);
    expect(find.text('T0'), findsNothing);
    // La página nueva repite el encabezado de su grupo.
    expect(find.text('COMPRAS'), findsOneWidget);
  });

  testWidgets('el contador de cada estado se ve en el filtro', (tester) async {
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskFiltersPanel(
            searchController: ctrl,
            onSearchChanged: (_) {},
            searchHint: 'Buscar',
            quickFilters: const [
              TaskQuickFilter(label: 'Todos', value: 'todas', count: 7),
              TaskQuickFilter(
                label: 'Retrasada',
                value: 'retrasada',
                count: 3,
                color: Colors.red,
              ),
            ],
            selectedQuickFilter: 'todas',
            onQuickFilterChanged: (_) {},
            // El valor elegido ya no está entre las opciones: no debe
            // romperse, vuelve a la primera.
            dropdowns: [
              TaskFilterDropdownData(
                label: 'Área',
                value: 'area_que_ya_no_esta',
                items: const [
                  DropdownMenuItem(value: 'todas', child: Text('Todas')),
                ],
                onChanged: (_) {},
              ),
            ],
            onClearFilters: () {},
            hasActiveFilters: false,
          ),
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('cargo de Analista de Compras', () {
    expect(esCargoAnalistaCompras('Analista de Compras'), isTrue);
    expect(esCargoAnalistaCompras('ANALISTA COMPRAS'), isTrue);
    expect(esCargoAnalistaCompras('analista de compras y suministros'), isTrue);
    expect(esCargoAnalistaCompras('Coordinador de Compras'), isFalse);
    expect(esCargoAnalistaCompras('Analista contable'), isFalse);
  });
}
