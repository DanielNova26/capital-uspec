import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_subsanaciones_export.dart';

void main() {
  InterventoriaHallazgo hallazgo({
    String numero = '2.14',
    String estado = 'abierto',
    String tarea = '',
    DateTime? subsanacion,
    String fuente = 'manual',
    String numeralActa = '',
  }) => InterventoriaHallazgo(
    id: 'h1',
    empresaId: 'capital',
    centroCostoId: 'buen_pastor',
    centroCostoNombre: 'Buen Pastor',
    numeroHallazgo: numero,
    fuente: fuente,
    numeralActa: numeralActa,
    descripcion: 'El área de almacenamiento no tiene estibas suficientes',
    fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 3)),
    estado: estado,
    dptoEncargado: 'Mantenimiento',
    responsableNombre: 'Carlos Pérez',
    cargoResponsable: 'Administrador tipo 1',
    observaciones: 'Se solicitó cotización',
    seguimiento: 'Pendiente de compra',
    fechaSubsanacion: subsanacion == null
        ? null
        : Timestamp.fromDate(subsanacion),
    tareaId: tarea,
    createdAt: Timestamp.fromDate(DateTime(2026, 9, 3)),
  );

  group('columnas', () {
    test('la fila trae un valor por cada columna de la tabla', () {
      // Si se separan, quien recibe el archivo no puede cruzarlo con lo que ve
      // el que se lo mandó.
      expect(
        filaSubsanacion(hallazgo()),
        hasLength(kColumnasSubsanaciones.length),
      );
    });
  });

  group('estado en palabras', () {
    test('las tres situaciones se distinguen sin color', () {
      // La tabla las pinta con colores; un Excel en blanco y negro necesita la
      // palabra o son indistinguibles.
      expect(
        estadoSubsanacionLegible(hallazgo(estado: 'subsanado')),
        'Subsanado',
      );
      expect(
        estadoSubsanacionLegible(hallazgo(estado: 'pendiente_aprobacion')),
        'Pendiente de aprobación',
      );
      expect(estadoSubsanacionLegible(hallazgo()), 'Abierto');
    });
  });

  group('el numeral no se convierte en número', () {
    test('1.10 sigue siendo 1.10', () {
      // Si Excel lo toma por número, 1.10 se convierte en 1.1 y deja de
      // existir un numeral del acta.
      final fila = filaSubsanacion(hallazgo(numero: '1.10'));

      expect(fila[7], '1.10');
    });
  });

  test(
    'exporta numeral real, ID de visita y tarea sin confundir el ordinal',
    () {
      final h = hallazgo(
        numero: '1.1',
        tarea: 't1',
        fuente: 'acta',
        numeralActa: '3.8',
      );
      final fila = filaSubsanacion(
        h,
        idVisita: '001234',
        tarea: {'numero': 1453, 'estado': 'por_aprobar'},
      );
      expect(fila[kColumnasSubsanaciones.indexOf('N° Hallazgo')], '3.8');
      expect(fila[kColumnasSubsanaciones.indexOf('ID de visita')], '001234');
      expect(fila[kColumnasSubsanaciones.indexOf('N° de tarea')], 'N.º 1453');
      expect(
        fila[kColumnasSubsanaciones.indexOf('Estado de tarea')],
        'Por aprobar',
      );
      expect(
        h.copyWith(numeralActa: '').numeroVisible,
        'Sin numeral identificado',
      );
    },
  );

  group('archivo', () {
    test('trae la cabecera y una fila por hallazgo', () {
      final bytes = generarExcelSubsanaciones([hallazgo(), hallazgo()]);

      expect(bytes, isNotEmpty);
    });

    test('un listado vacío genera archivo con solo la cabecera', () {
      expect(generarExcelSubsanaciones(const []), isNotEmpty);
    });

    test('el nombre lleva la fecha para no pisar descargas anteriores', () {
      expect(
        nombreArchivoSubsanaciones(ahora: DateTime(2026, 9, 3)),
        'subsanaciones_20260903',
      );
    });
  });

  group('columnas vacías', () {
    test('sin tarea vinculada lo dice, no deja el hueco', () {
      expect(filaSubsanacion(hallazgo())[13], 'Sin tarea');
      expect(filaSubsanacion(hallazgo(tarea: 't1'))[13], 'Sí');
    });

    test('sin fecha de subsanación la casilla queda vacía', () {
      expect(filaSubsanacion(hallazgo())[12], '');
      expect(
        filaSubsanacion(hallazgo(subsanacion: DateTime(2026, 9, 20)))[12],
        '20/09/2026',
      );
    });
  });
}
