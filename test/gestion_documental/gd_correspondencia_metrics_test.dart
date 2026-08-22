import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_metrics.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';

GdExpediente _expediente(
  String estado,
  String responsable, {
  String tipo = 'Tutela',
  String area = 'Jurídica',
  DateTime? fechaRecepcion,
}) => GdExpediente(
  id: '$estado-$responsable',
  empresaId: 'EMPRESA_001',
  cuentaId: 'correo-1',
  correoCuenta: 'correspondencia@empresa.com',
  proveedor: 'microsoft',
  radicado: 'GD-1',
  origen: 'correo',
  asunto: 'Solicitud',
  remitente: 'origen@entidad.gov.co',
  categoria: tipo,
  tipoDocumental: tipo,
  estado: estado,
  prioridad: 'media',
  responsableId: responsable.isEmpty ? '' : responsable,
  responsableNombre: responsable,
  areaId: area.toLowerCase(),
  areaNombre: area,
  creadorId: 'creador',
  tareaId: 'tarea',
  cuerpoEntrada: 'Contenido',
  entradaEstado: 'disponible',
  entradaError: '',
  fechaRecepcion: fechaRecepcion ?? DateTime(2026, 8, 12),
  fechaLimite: DateTime(2026, 8, 15),
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
  enviadoAt: null,
);

void main() {
  test('agrupa únicamente los procesos asignados por responsable', () {
    final result = gdAsignadosPorResponsable([
      _expediente('asignado', 'Andrea'),
      _expediente('asignado', 'Andrea'),
      _expediente('asignado', 'Carlos'),
      _expediente('recibido', ''),
      _expediente('terminado', 'Andrea'),
    ]);

    expect(result.map((row) => row.etiqueta), ['Andrea', 'Carlos']);
    expect(result.map((row) => row.cantidad), [2, 1]);
  });

  test('ordena empates por nombre y respeta el límite', () {
    final result = gdAsignadosPorResponsable([
      _expediente('asignado', 'Zully'),
      _expediente('asignado', 'Andrea'),
    ], limite: 1);

    expect(result.single.etiqueta, 'Andrea');
  });

  test('combina estado, tipo, responsable y rango de recepción', () {
    final filtro = GdFiltrosCorrespondencia(
      estado: 'asignado',
      tipoDocumental: 'Tutela',
      responsable: 'Andrea',
      recibidoDesde: DateTime(2026, 8, 10),
      recibidoHasta: DateTime(2026, 8, 12),
    );

    expect(
      filtro.coincide(
        _expediente(
          'asignado',
          'Andrea',
          fechaRecepcion: DateTime(2026, 8, 12, 23, 30),
        ),
      ),
      isTrue,
    );
    expect(filtro.coincide(_expediente('terminado', 'Andrea')), isFalse);
    expect(filtro.coincide(_expediente('asignado', 'Carlos')), isFalse);
    expect(
      filtro.coincide(_expediente('asignado', 'Andrea', tipo: 'Requerimiento')),
      isFalse,
    );
  });

  test('la búsqueda también encuentra el área', () {
    const filtro = GdFiltrosCorrespondencia(consulta: 'jurídica');
    expect(
      filtro.coincide(_expediente('recibido', '', area: 'Jurídica')),
      isTrue,
    );
  });

  test('genera opciones únicas y ordenadas para los desplegables', () {
    final rows = [
      _expediente('asignado', 'Zully', tipo: 'Tutela'),
      _expediente('asignado', 'Andrea', tipo: 'Requerimiento'),
      _expediente('terminado', 'Andrea', tipo: 'Tutela'),
    ];
    expect(gdTiposDisponibles(rows), ['Requerimiento', 'Tutela']);
    expect(gdResponsablesDisponibles(rows), ['Andrea', 'Zully']);
  });
}
