import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gerencia/gerencia_hallazgos_export.dart';
import 'package:todo/interventoria/interventoria_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  InterventoriaVisita visita(int dia, {String subcentro = ''}) =>
      InterventoriaVisita(
        id: 'acta-$dia-$subcentro',
        empresaId: 'capital',
        centroCostoId: 'buen_pastor',
        centroCostoCodigo: '01',
        centroCostoNombre: 'Buen Pastor',
        subcentroNombre: subcentro,
        fechaVisita: Timestamp.fromDate(DateTime(2026, 9, dia)),
        fechaRegistro: Timestamp.fromDate(DateTime(2026, 9, dia)),
        creadoPor: 'test',
        porcentajeGeneral: 80,
        items: const {},
        createdAt: Timestamp.fromDate(DateTime(2026, 9, dia)),
      );

  test('cuenta actas por semana y respeta las fechas', () {
    final actas = [visita(7), visita(8), visita(14)];
    final semanas = contarVisitasPorSemana(actas);
    expect(semanas.map((e) => e.actas), [1, 2]);
    expect(semanas.first.lunes, DateTime(2026, 9, 14));
    expect(
      contarVisitasPorSemana(
        actas,
        desde: DateTime(2026, 9, 8),
      ).fold<int>(0, (n, e) => n + e.actas),
      2,
    );
  });

  test('Excel de visitas separa centro y subcentro', () {
    final bytes = generarExcelVisitasGerencia([
      visita(8, subcentro: 'Alta'),
    ], 'Todo el histórico');
    final libro = Excel.decodeBytes(bytes);
    final fila = libro['Visitas'].rows.last;
    expect(fila[1]?.value.toString(), 'Buen Pastor');
    expect(fila[2]?.value.toString(), 'Alta');
    expect(libro['Por semana'].rows.length, 2);
  });

  test('PDF de visitas incluye un acta', () async {
    final bytes = await generarPdfVisitasGerencia([
      visita(8, subcentro: 'Alta'),
    ], 'Septiembre 2026');
    expect(bytes.length, greaterThan(100));
  });

  InterventoriaHallazgo hallazgo({
    String numeral = '',
    String numero = '',
    String fuente = 'manual',
    DateTime? fecha,
    String visitaId = '',
    String estado = 'activo',
  }) => InterventoriaHallazgo(
    id: 'h-$numeral-$numero-$visitaId',
    empresaId: 'capital',
    visitaId: visitaId,
    estado: estado,
    centroCostoId: 'buen_pastor',
    centroCostoNombre: 'Buen Pastor',
    numeroHallazgo: numero,
    numeralActa: numeral,
    fuente: fuente,
    descripcion: 'Hallazgo',
    fechaHallazgo: Timestamp.fromDate(fecha ?? DateTime(2026, 9, 3)),
    createdAt: Timestamp.fromDate(DateTime(2026, 9, 3)),
  );

  group('seccionDelHallazgo', () {
    test('sale del numeral del acta', () {
      expect(seccionDelHallazgo(hallazgo(numeral: '3.2')), 3);
      expect(seccionDelHallazgo(hallazgo(numeral: '10.20')), 10);
    });

    test('un hallazgo manual con número usa ese número', () {
      expect(seccionDelHallazgo(hallazgo(numero: '7.1')), 7);
    });

    test('las observaciones generales (90.x) no pertenecen a ninguna', () {
      expect(seccionDelHallazgo(hallazgo(numero: '90.1')), 0);
    });

    test('el ordinal de un hallazgo del acta no se toma por numeral', () {
      // En los generados desde el formulario el número es categoría.observación
      // y apuntaría a otra sección.
      expect(seccionDelHallazgo(hallazgo(numero: '2.5', fuente: 'acta')), 0);
    });
  });

  group('conteoPorSeccion', () {
    test('cuenta por sección en orden 1..11 y deja "sin numeral" al final', () {
      final conteo = conteoPorSeccion([
        hallazgo(numeral: '11.1'),
        hallazgo(numeral: '3.2'),
        hallazgo(numeral: '3.4'),
        hallazgo(numero: '90.1'),
        hallazgo(numeral: '1.1'),
      ]);
      expect(conteo.map((e) => e.key), [1, 3, 11, 0]);
      expect(conteo.map((e) => e.value), [1, 2, 1, 1]);
    });
  });

  group('compararPorNumeral', () {
    test(
      'ordena por sección, luego por numeral y luego por fecha reciente',
      () {
        final lista = [
          hallazgo(numeral: '3.10', fecha: DateTime(2026, 9, 1)),
          hallazgo(numero: '90.1'),
          hallazgo(numeral: '3.2', fecha: DateTime(2026, 9, 1)),
          hallazgo(numeral: '3.2', fecha: DateTime(2026, 9, 9)),
          hallazgo(numeral: '1.5'),
        ]..sort(compararPorNumeral);
        expect(lista.map((h) => h.numeralParaMatriz), [
          '1.5',
          '3.2',
          '3.2',
          '3.10',
          // Las observaciones generales (90.x) no son sección: van al final.
          '90.1',
        ]);
        // Entre iguales, primero el más reciente.
        expect(lista[1].fechaHallazgo.toDate(), DateTime(2026, 9, 9));
      },
    );
  });

  group('etiquetaSeccion', () {
    test('lleva el número y el nombre en minúsculas legibles', () {
      expect(etiquetaSeccion(4), '4 · Equipos, Utensilios y Menaje');
      expect(etiquetaSeccion(0), 'Sin numeral');
    });
  });

  group('nombreArchivoHallazgosGerencia', () {
    test('sin tildes ni espacios y con la fecha al final', () {
      expect(
        nombreArchivoHallazgosGerencia(
          'Establecimiento: Cómbita · 3 · Almacenamiento',
          ahora: DateTime(2026, 9, 21),
        ),
        'hallazgos_establecimiento_combita_3_almacenamiento_20260921',
      );
    });
  });

  group('generarExcelHallazgosGerencia', () {
    test('incluye área responsable, centro y subcentro', () {
      final bytes = generarExcelHallazgosGerencia(
        [hallazgo(numeral: '3.2'), hallazgo(numero: '90.1')],
        const AlcanceExportacion(titulo: 'Prueba', filtros: 'Todo'),
        nombreArea: (_) => 'Nutrición',
      );
      final filas = Excel.decodeBytes(bytes)['Hallazgos'].rows;
      expect(filas[3][1]?.value.toString(), 'Área responsable');
      expect(filas[4][1]?.value.toString(), 'Nutrición');
      expect(filas[4][2]?.value.toString(), 'Buen Pastor');
    });
  });

  group('conteos con visitas', () {
    test('las visitas se cuentan por acta, no por hallazgo', () {
      final hs = [
        hallazgo(numeral: '1.1', visitaId: 'acta-1'),
        hallazgo(numeral: '1.2', visitaId: 'acta-1'),
        hallazgo(numeral: '2.1', visitaId: 'acta-2'),
      ];
      expect(visitasDeHallazgos(hs), 2);
    });

    test('un hallazgo manual sin acta se identifica por sede y fecha', () {
      final hs = [
        hallazgo(numero: '1.1', fecha: DateTime(2026, 9, 3)),
        hallazgo(numero: '1.2', fecha: DateTime(2026, 9, 3, 15)),
        hallazgo(numero: '1.3', fecha: DateTime(2026, 9, 4)),
      ];
      expect(visitasDeHallazgos(hs), 2);
    });

    test('se escriben "hallazgos (visitas)", nunca con punto', () {
      expect(conteoConVisitas(12, 3), '12 (3)');
      expect(conteoConVisitas(1, 5), '1 (5)');
      expect(etiquetaConConteo('3', 5), '3 (5)');
      expect(etiquetaConConteo('Todas', 23), 'Todas (23)');
    });
  });

  group('resumenPorArea', () {
    test('agrupa por el área que da la pantalla y ordena por hallazgos', () {
      final hs = [
        hallazgo(numeral: '1.1', visitaId: 'a1'),
        hallazgo(numeral: '1.2', visitaId: 'a1', estado: 'subsanado'),
        hallazgo(numeral: '3.1', visitaId: 'a2'),
        hallazgo(numeral: '4.1', visitaId: 'a2'),
      ];
      final areas = {
        hs[0].id: 'Nutrición',
        hs[1].id: 'Nutrición',
        hs[2].id: 'Nutrición',
        hs[3].id: '',
      };
      final resumen = resumenPorArea(hs, (h) => areas[h.id]!);
      expect(resumen.map((r) => r.area), ['Nutrición', 'Sin área']);
      expect(resumen.first.hallazgos, 3);
      expect(resumen.first.visitas, 2);
      expect(resumen.first.subsanados, 1);
      expect(resumen.first.abiertos, 2);
    });
  });

  group('encabezado de empresa en los PDF', () {
    final logo = Uint8List.fromList(File('assets/logo.png').readAsBytesSync());

    test('el PDF de hallazgos sale con nombre y logo de la empresa', () async {
      final sinEmpresa = await generarPdfHallazgosGerencia([
        hallazgo(numeral: '3.2', visitaId: 'a1'),
      ], const AlcanceExportacion(titulo: 'Prueba'));
      final conEmpresa = await generarPdfHallazgosGerencia(
        [hallazgo(numeral: '3.2', visitaId: 'a1')],
        const AlcanceExportacion(titulo: 'Prueba'),
        empresa: EmpresaPdf(nombre: 'Capital USPEC', logo: logo),
        nombreResponsable: (_) => 'Ana Pérez\n(sugerido por la matriz)',
      );
      // El logo va incrustado: el archivo crece al menos lo que pesa.
      expect(
        conEmpresa.length,
        greaterThan(sinEmpresa.length + logo.length ~/ 2),
      );
    });

    test('un logo que el PDF no sabe leer no impide generar el PDF', () async {
      final bytes = await generarPdfVisitasGerencia(
        [visita(8)],
        'Septiembre 2026',
        empresa: EmpresaPdf(
          nombre: 'Capital USPEC',
          logo: Uint8List.fromList(List.filled(64, 7)),
        ),
        porArea: const [
          ResumenArea(area: 'Nutrición', hallazgos: 4, visitas: 2),
        ],
      );
      expect(bytes.length, greaterThan(100));
    });
  });

  test('Excel de visitas trae la hoja por área con hallazgos y visitas', () {
    final bytes = generarExcelVisitasGerencia(
      [visita(8)],
      'Todo el histórico',
      porArea: const [ResumenArea(area: 'Nutrición', hallazgos: 4, visitas: 2)],
    );
    final filas = Excel.decodeBytes(bytes)['Por área'].rows;
    expect(filas[1][0]?.value.toString(), 'Nutrición');
    expect(filas[1][1]?.value.toString(), '4');
    expect(filas[1][2]?.value.toString(), '2');
  });
}
