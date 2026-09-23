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
  }) => InterventoriaHallazgo(
    id: 'h-$numeral-$numero',
    empresaId: 'capital',
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
      final bytes = generarExcelHallazgosGerencia([
        hallazgo(numeral: '3.2'),
        hallazgo(numero: '90.1'),
      ], const AlcanceExportacion(titulo: 'Prueba', filtros: 'Todo'),
          nombreArea: (_) => 'Nutrición');
      final filas = Excel.decodeBytes(bytes)['Hallazgos'].rows;
      expect(filas[3][1]?.value.toString(), 'Área responsable');
      expect(filas[4][1]?.value.toString(), 'Nutrición');
      expect(filas[4][2]?.value.toString(), 'Buen Pastor');
    });
  });
}
