import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';

GdExpediente _expediente({
  String estado = 'terminado',
  DateTime? enviadoAt,
  bool respuestaExterna = false,
  String cierreMotivo = '',
  String cierreJustificacion = '',
  bool cierreSinRespuesta = false,
}) => GdExpediente(
  id: 'exp-1',
  empresaId: 'EMPRESA_001',
  cuentaId: 'cuenta',
  correoCuenta: 'correspondencia@example.com',
  proveedor: 'gmail',
  radicado: 'GD-2026-000001',
  origen: 'correo',
  asunto: 'Solicitud',
  remitente: 'eps@example.com',
  categoria: 'Otro',
  estado: estado,
  prioridad: 'media',
  responsableId: '1',
  responsableNombre: 'Daniel',
  creadorId: '2',
  tareaId: '',
  cuerpoEntrada: '',
  entradaEstado: 'disponible',
  entradaError: '',
  fechaRecepcion: DateTime(2026, 9, 1),
  fechaLimite: null,
  requiereAprobacion: false,
  revisorId: '',
  revisorNombre: '',
  aprobacionEstado: 'no_requerida',
  revisionComentario: '',
  respuestaDestinatario: '',
  respuestaAsunto: '',
  respuestaCuerpo: '',
  respuestaCc: const [],
  adjuntosEntrada: const [],
  adjuntosRespuesta: const [],
  enviadoAt: enviadoAt,
  respuestaExternaRegistrada: respuestaExterna,
  cierreMotivo: cierreMotivo,
  cierreJustificacion: cierreJustificacion,
  cierreSinRespuesta: cierreSinRespuesta,
);

void main() {
  group('motivo de cierre', () {
    test('resuelve el valor guardado sin importar mayúsculas ni espacios', () {
      expect(GdMotivoCierre.desde(' NO_CORRESPONDE '), GdMotivoCierre.noCorresponde);
      expect(GdMotivoCierre.desde('inventado'), isNull);
      expect(GdMotivoCierre.desde(null), isNull);
    });

    test('un valor desconocido se muestra tal cual y no rompe', () {
      expect(GdMotivoCierre.etiquetaDe('duplicado'), 'Duplicado de otro expediente');
      expect(GdMotivoCierre.etiquetaDe('otro_viejo'), 'otro_viejo');
      expect(GdMotivoCierre.etiquetaDe(''), '');
    });

    test('la justificación es obligatoria sin respuesta o con motivo distinto a gestión completa', () {
      expect(
        gdCierreExigeJustificacion(
          motivo: GdMotivoCierre.gestionCompleta,
          tieneRespuesta: true,
        ),
        isFalse,
      );
      expect(
        gdCierreExigeJustificacion(
          motivo: GdMotivoCierre.gestionCompleta,
          tieneRespuesta: false,
        ),
        isTrue,
      );
      for (final motivo in GdMotivoCierre.values.where(
        (m) => m != GdMotivoCierre.gestionCompleta,
      )) {
        expect(
          gdCierreExigeJustificacion(motivo: motivo, tieneRespuesta: true),
          isTrue,
          reason: motivo.valor,
        );
      }
    });
  });

  group('cierre en el expediente', () {
    test('un terminado con respuesta no es "sin respuesta"', () {
      final row = _expediente(
        enviadoAt: DateTime(2026, 9, 2),
        cierreMotivo: 'gestion_completa',
      );
      expect(row.cerradoSinRespuesta, isFalse);
      expect(row.resumenCierre, 'Terminado · Gestión completa');
    });

    test('un cierre histórico sin motivo ni respuesta se lee como sin respuesta', () {
      final row = _expediente();
      expect(row.motivoCierre, isNull);
      expect(row.cerradoSinRespuesta, isTrue);
      expect(row.resumenCierre, 'Terminado · sin respuesta');
    });

    test('la marca del backend manda aunque después aparezca una respuesta', () {
      final row = _expediente(
        enviadoAt: DateTime(2026, 9, 2),
        cierreMotivo: 'no_corresponde',
        cierreJustificacion: 'Es de otra EPS.',
        cierreSinRespuesta: true,
      );
      expect(row.cerradoSinRespuesta, isTrue);
      expect(
        row.resumenCierre,
        'Terminado · No corresponde a la entidad · sin respuesta',
      );
    });

    test('un expediente abierto no tiene resumen de cierre', () {
      final row = _expediente(estado: 'asignado', cierreMotivo: 'otro');
      expect(row.cerradoSinRespuesta, isFalse);
      expect(row.resumenCierre, '');
    });
  });
}
