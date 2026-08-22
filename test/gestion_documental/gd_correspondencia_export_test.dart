import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_export.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';

GdExpediente _row() => GdExpediente(
  id: 'exp-1',
  empresaId: 'EMPRESA_001',
  cuentaId: 'correo-1',
  correoCuenta: 'correspondencia@empresa.com',
  proveedor: 'microsoft',
  radicado: 'GD-2026-000001',
  origen: 'correo',
  asunto: 'Solicitud de información',
  alias: 'Solicitud contrato',
  remitente: 'entidad@gov.co',
  categoria: 'Requerimiento',
  tipoDocumental: 'Requerimiento',
  codigoInterno: 'REQ150826-001',
  estado: 'asignado',
  prioridad: 'alta',
  responsableId: 'usr-1',
  responsableNombre: 'Andrea Reales',
  areaId: 'juridica',
  areaNombre: 'Jurídica',
  creadorId: 'usr-2',
  tareaId: 'task-1',
  cuerpoEntrada: 'Contenido',
  entradaEstado: 'disponible',
  entradaError: '',
  fechaRecepcion: DateTime(2026, 8, 15, 8, 30),
  fechaLimite: DateTime(2026, 8, 20, 17),
  requiereAprobacion: false,
  revisorId: '',
  revisorNombre: '',
  aprobacionEstado: 'no_requerida',
  revisionComentario: '',
  respuestaDestinatario: '',
  respuestaAsunto: '',
  respuestaCuerpo: '',
  respuestaCc: const [],
  adjuntosEntrada: const [
    GdCorrespondenciaAdjunto(
      nombre: 'oficio.pdf',
      mimeType: 'application/pdf',
      storagePath: 'entrada/oficio.pdf',
      downloadUrl: 'https://archivo',
      size: 100,
    ),
  ],
  adjuntosRespuesta: const [],
  enviadoAt: null,
);

void main() {
  test('genera un XLSX legible con fechas tipadas y columnas operativas', () {
    final bytes = construirExcelCorrespondencia(
      expedientes: [_row()],
      empresaId: 'EMPRESA_001',
      alcance: 'Histórico completo',
    );

    expect(bytes, isNotEmpty);
    final workbook = xl.Excel.decodeBytes(bytes);
    final sheet = workbook['Correspondencia'];
    expect(
      sheet.cell(xl.CellIndex.indexByString('A1')).value.toString(),
      contains('HISTÓRICO'),
    );
    expect(
      sheet.cell(xl.CellIndex.indexByString('A5')).value.toString(),
      contains('REQ150826-001'),
    );
    expect(
      sheet.cell(xl.CellIndex.indexByString('D5')).value,
      isA<xl.DateTimeCellValue>(),
    );
    expect(
      sheet.cell(xl.CellIndex.indexByString('J5')).value.toString(),
      contains('Jurídica'),
    );
    expect(
      sheet.cell(xl.CellIndex.indexByString('N5')).value.toString(),
      contains('Asignado'),
    );
  });
}
