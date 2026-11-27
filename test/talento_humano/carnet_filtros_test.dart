import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/carnet_filtros.dart';
import 'package:todo/talento_humano/carnet_service.dart';

void main() {
  final personas = List.generate(
    70,
    (i) => CarnetCandidato(
      userId: '$i',
      cedula: '100$i',
      nombres: 'Persona $i',
      apellidos: 'Prueba',
      cargo: i.isEven ? 'Auxiliar' : 'Coordinador',
      fotoUrl: i % 3 == 0 ? 'https://foto' : '',
      activo: i % 5 != 0,
      hojaAprobada: i.isEven,
      tieneCarnet: i % 4 == 0,
    ),
  );
  test('combina foto, carnet, estado y búsqueda sobre el padrón completo', () {
    const filtros = CarnetFiltros(
      foto: CarnetFiltroEstado.con,
      carnet: CarnetFiltroEstado.sin,
      soloAprobados: true,
      consulta: 'Auxiliar',
    );
    expect(personas.where(filtros.incluye).map((c) => c.userId), [
      '6',
      '18',
      '42',
      '54',
      '66',
    ]);
    expect(
      personas.where(
        const CarnetFiltros(
          foto: CarnetFiltroEstado.sin,
          soloActivos: false,
        ).incluye,
      ),
      hasLength(46),
    );
    expect(
      personas.where(
        const CarnetFiltros(
          carnet: CarnetFiltroEstado.con,
          soloActivos: false,
        ).incluye,
      ),
      hasLength(18),
    );
    expect(
      personas
          .where(const CarnetFiltros(consulta: '10066').incluye)
          .single
          .userId,
      '66',
    );
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('filtros a $width, texto 200 %, $platform', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var foto = CarnetFiltroEstado.todos;
        var carnet = CarnetFiltroEstado.todos;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: StatefulBuilder(
                    builder: (context, setState) => CarnetFiltrosBar(
                      foto: foto,
                      carnet: carnet,
                      onFotoChanged: (v) => setState(() => foto = v),
                      onCarnetChanged: (v) => setState(() => carnet = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byType(DropdownButtonFormField<CarnetFiltroEstado>).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Con foto').last);
        await tester.pumpAndSettle();
        expect(foto, CarnetFiltroEstado.con);
        await tester.tap(
          find.byType(DropdownButtonFormField<CarnetFiltroEstado>).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sin carnet').last);
        await tester.pumpAndSettle();
        expect(carnet, CarnetFiltroEstado.sin);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
