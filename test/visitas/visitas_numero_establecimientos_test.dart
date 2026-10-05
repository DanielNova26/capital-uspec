import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/task_numeracion_card.dart';
import 'package:todo/admin/visitas_establecimientos_panel.dart';
import 'package:todo/services/task_service.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

import '../support/memory_firestore.dart';

/// 5 oct 2026, documento "Visitas - octubre 03": "Guardar ID de VISITA"
/// ("Visita No 00001" junto al establecimiento). Y el pedido del usuario:
/// "agregarle ciertos establecimientos que no son necesariamente iguales a
/// los de Interventoría, pero sí hacen falta para visitas. Lo podemos poner
/// en el admin".
class _StorageFalso extends Fake implements FirebaseStorage {}

class _TareasFalsas extends Fake implements TaskService {}

VisitaProfesional _visita({int? numero, String establecimiento = 'Picota'}) =>
    VisitaProfesional(
      empresaId: 'A',
      numero: numero,
      formatoId: '',
      formatoNombre: 'Revisión de equipos',
      areaId: 'A_desarrollo',
      areaNombre: 'Desarrollo',
      centroId: 'C1',
      centroNombre: establecimiento,
      profesionalId: 'prof',
      profesionalNombre: 'Daniel',
      asignadoPorId: 'jefe',
      asignadoPorNombre: 'Jefe',
      fechaProgramada: DateTime(2026, 10, 1),
    );

void main() {
  group('número de visita', () {
    test('se muestra con cinco cifras y vacío si aún no tiene', () {
      expect(numeroVisitaTexto(1), 'Visita No 00001');
      expect(numeroVisitaTexto(123456), 'Visita No 123456');
      expect(numeroVisitaTexto(null), '');
      expect(numeroVisitaCorto(42), '00042');
      expect(numeroVisitaCorto(null), '');
    });

    test('se lee del servidor y la app nunca lo escribe', () {
      Map<String, dynamic> base(Object? numero) => {
        ..._visita().toMap(),
        'numero': numero,
      };
      expect(VisitaProfesional.fromMap('v', base(7)).numero, 7);
      expect(VisitaProfesional.fromMap('v', base('12')).numero, 12);
      expect(VisitaProfesional.fromMap('v', base(0)).numero, isNull);
      expect(VisitaProfesional.fromMap('v', base(2.5)).numero, isNull);
      expect(VisitaProfesional.fromMap('v', base(null)).numero, isNull);
      expect(
        VisitaProfesional.fromMap('v', base(3)).numeroTexto,
        'Visita No 00003',
      );
      // Las reglas rechazan una visita nueva que traiga `numero`.
      expect(_visita(numero: 9).toMap().containsKey('numero'), isFalse);
    });

    test('se busca por número en las listas', () {
      final visitas = [
        _visita(numero: 12, establecimiento: 'Picota'),
        _visita(numero: 3, establecimiento: 'Cómbita'),
        _visita(establecimiento: 'Modelo'),
      ];
      expect(
        filtrarVisitas(visitas, texto: '00012').map((v) => v.establecimiento),
        ['Picota'],
      );
      expect(
        filtrarVisitas(
          visitas,
          texto: 'visita no 00003',
        ).map((v) => v.establecimiento),
        ['Cómbita'],
      );
    });

    test('la tarea del hallazgo nombra la visita', () {
      const h = VisitaHallazgo(
        clave: 'i1',
        elemento: 'Extintor vencido',
        novedad: 'Sin recarga',
      );
      expect(
        descripcionTareaHallazgo(_visita(numero: 5), h),
        contains('Visita No 00005'),
      );
      expect(
        descripcionTareaHallazgo(_visita(), h),
        isNot(contains('Visita No')),
      );
    });
  });

  group('establecimientos propios de Visitas', () {
    test('id con la empresa y el nombre, reconocible en la visita', () {
      expect(
        idEstablecimientoPropio('A', 'Cárcel El Buen Pastor'),
        'A_est_carcel_el_buen_pastor',
      );
      expect(idEstablecimientoPropio('A', '  ¿? '), '');
      expect(esEstablecimientoPropioVisitas('A', 'A_est_picota'), isTrue);
      expect(esEstablecimientoPropioVisitas('A', 'B_est_picota'), isFalse);
      expect(esEstablecimientoPropioVisitas('A', 'C1'), isFalse);
    });

    test('valida nombre y no repite un propio ni un centro de costo', () {
      VisitaEstablecimientoPropio e(String nombre, [String ciudad = '']) =>
          VisitaEstablecimientoPropio(
            id: '',
            empresaId: 'A',
            nombre: nombre,
            ciudad: ciudad,
          );
      expect(validarEstablecimientoPropio(e('Bodega Norte')), isEmpty);
      expect(validarEstablecimientoPropio(e(' ')).single, contains('nombre'));
      expect(validarEstablecimientoPropio(e('¿?')).single, contains('letras'));
      expect(
        validarEstablecimientoPropio(e('Bodega', 'x' * 81)).single,
        contains('ciudad'),
      );
      expect(
        validarEstablecimientoPropio(e('PICOTA'), centros: ['Picota']).single,
        contains('centro de costo'),
      );
      expect(
        validarEstablecimientoPropio(
          e('bodega  norte'),
          propios: ['Bodega Norte'],
        ).single,
        contains('Ya existe'),
      );
    });

    test('se unen a los centros, por nombre; inactivos y choques no', () {
      final lista = unirEstablecimientos(
        const [
          VisitaCentro(id: 'C2', nombre: 'Picota'),
          VisitaCentro(id: 'C1', nombre: 'Cómbita'),
        ],
        const [
          VisitaEstablecimientoPropio(
            id: 'A_est_bodega',
            empresaId: 'A',
            nombre: 'Bodega',
            ciudad: 'Bogotá',
          ),
          VisitaEstablecimientoPropio(
            id: 'A_est_viejo',
            empresaId: 'A',
            nombre: 'Viejo',
            activo: false,
          ),
          VisitaEstablecimientoPropio(id: 'C2', empresaId: 'A', nombre: 'X'),
        ],
      );
      expect(lista.map((c) => c.nombre), ['Bodega', 'Cómbita', 'Picota']);
      expect(lista.first.propio, isTrue);
      expect(lista.first.ciudad, 'Bogotá');
      expect(lista.first.subcentrosActivos, isEmpty);
      expect(lista.where((c) => c.propio).length, 1);
    });

    late MemoryFirestore db;
    late VisitasService svc;
    setUp(() {
      db = MemoryFirestore();
      svc = VisitasService(
        db: db,
        storage: _StorageFalso(),
        tasks: _TareasFalsas(),
      );
      db.documents['TBL_CENTROS_COSTOS/A_picota'] = {
        'empresaId': 'A',
        'centroId': 'A_picota',
        'nombre': 'Picota',
      };
      db.documents['TBL_CENTROS_COSTOS/B_otra'] = {
        'empresaId': 'B',
        'nombre': 'Bodega Norte',
      };
    });
    tearDown(() => db.close());

    VisitaEstablecimientoPropio nuevo(String nombre, {String empresa = 'A'}) =>
        VisitaEstablecimientoPropio(id: '', empresaId: empresa, nombre: nombre);

    test('se crean por empresa y salen en Visitas con los centros', () async {
      final id = await svc.guardarEstablecimientoPropio(
        nuevo('Bodega Norte').copyWith(ciudad: 'Bogotá'),
        actorId: 'admin',
      );
      expect(id, 'A_est_bodega_norte');
      final doc = db.documents['TBL_VISITAS_ESTABLECIMIENTOS/$id']!;
      expect(doc['empresaId'], 'A');
      expect(doc['centroId'], id);
      expect(doc['nombre'], 'Bodega Norte');
      expect(doc['ciudad'], 'Bogotá');
      expect(doc['enabled'], isTrue);
      expect(doc['creadoPor'], 'admin');

      final centros = await svc.centrosDeEmpresa('A');
      expect(centros.map((c) => c.nombre), ['Bodega Norte', 'Picota']);
      expect(centros.first.propio, isTrue);
      // Otra empresa no lo ve (y el centro "Bodega Norte" de B no choca).
      expect(await svc.centrosDeEmpresa('B'), hasLength(1));
      final enVivo = await svc.streamCentros('A').first;
      expect(enVivo.map((c) => c.id), [id, 'A_picota']);
    });

    test('no repite nombres; renombrar conserva el id', () async {
      await expectLater(
        svc.guardarEstablecimientoPropio(nuevo('picota'), actorId: 'admin'),
        throwsA(isA<VisitasException>()),
      );
      final id = await svc.guardarEstablecimientoPropio(
        nuevo('Bodega'),
        actorId: 'admin',
      );
      await expectLater(
        svc.guardarEstablecimientoPropio(nuevo('BODEGA'), actorId: 'admin'),
        throwsA(isA<VisitasException>()),
      );
      final renombrado = (await svc.establecimientosPropiosDeEmpresa(
        'A',
      )).single.copyWith(nombre: 'Bodega Sur');
      expect(
        await svc.guardarEstablecimientoPropio(renombrado, actorId: 'otro'),
        id,
      );
      expect(
        db.documents['TBL_VISITAS_ESTABLECIMIENTOS/$id']!['nombre'],
        'Bodega Sur',
      );
      // El nombre viejo queda libre, con otro id.
      expect(
        await svc.guardarEstablecimientoPropio(nuevo('Bodega'), actorId: 'a'),
        '${id}_2',
      );
    });

    test('inactivo no se programa y no admite subcentros', () async {
      final id = await svc.guardarEstablecimientoPropio(
        nuevo('Bodega'),
        actorId: 'admin',
      );
      await svc.activarEstablecimientoPropio(
        id,
        activo: false,
        actorId: 'admin',
      );
      expect((await svc.centrosDeEmpresa('A')).map((c) => c.id), ['A_picota']);
      expect(
        (await svc.establecimientosPropiosDeEmpresa('A')).single.activo,
        isFalse,
      );
      await expectLater(
        svc.agregarSubcentro(
          const VisitaCentro(id: 'A_est_x', nombre: 'X', propio: true),
          'Patio 1',
        ),
        throwsA(isA<VisitasException>()),
      );
    });

    Future<void> panel(WidgetTester tester, double ancho) async {
      tester.view.physicalSize = Size(ancho, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisitasEstablecimientosPanel(
              userId: 'admin',
              empresaId: 'A',
              svc: svc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final ancho in [390.0, 1366.0]) {
      testWidgets('Admin agrega y edita (${ancho.round()} px)', (tester) async {
        await panel(tester, ancho);
        expect(find.textContaining('Todavía no hay'), findsOneWidget);

        await tester.tap(find.text('Agregar establecimiento'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(1), 'Bodega Norte');
        await tester.enterText(find.byType(TextField).at(2), 'Bogotá');
        await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
        await tester.pumpAndSettle();
        expect(
          db.documents['TBL_VISITAS_ESTABLECIMIENTOS/A_est_bodega_norte'],
          isNotNull,
        );
        expect(find.text('Bodega Norte'), findsOneWidget);
        expect(find.text('Activo'), findsOneWidget);

        // Repetir un centro de costo se avisa y no se guarda.
        await tester.tap(find.text('Agregar establecimiento'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(1), 'Picota');
        await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ya es un centro de costo'), findsWidgets);
        expect(
          db.documents.keys.where(
            (k) => k.startsWith('TBL_VISITAS_ESTABLECIMIENTOS/'),
          ),
          hasLength(1),
        );
        await tester.pump(const Duration(seconds: 5));

        // Inactivar desde la lista.
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(
          db.documents['TBL_VISITAS_ESTABLECIMIENTOS/A_est_bodega_norte']!['enabled'],
          isFalse,
        );
        expect(find.text('Bodega Norte'), findsNothing);
        await tester.tap(find.text('Ver inactivos (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Inactivo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Admin › Migraciones numera también las visitas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TaskNumeracionCard.visitas(empresaId: 'A')),
      ),
    );
    expect(find.text('Número de visitas'), findsOneWidget);
    expect(find.text('Numerar visitas existentes'), findsOneWidget);
    expect(
      find.textContaining('Las de prueba no llevan número'),
      findsOneWidget,
    );
  });
}
