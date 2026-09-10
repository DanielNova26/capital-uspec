import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'interventoria_models.dart';

/// Exporta la tabla de subsanaciones a Excel.
///
/// Se pidió en la reunión del 9 sep 2026 para poder manejar los datos fuera de
/// la aplicación. Lo que se exporta es **lo que está en pantalla**, con los
/// filtros ya aplicados: descargar siempre todo obliga a rehacer el filtro en
/// Excel y a explicar por qué el archivo no coincide con lo que se veía.
///
/// Las columnas son las mismas de la tabla y en el mismo orden. Si se separan,
/// quien recibe el archivo no puede cruzarlo con lo que ve el que se lo mandó.

/// Cabeceras, en el orden de la tabla.
const List<String> kColumnasSubsanaciones = [
  'Departamento',
  'Responsable',
  'Cargo',
  'Fecha límite',
  'Establecimiento',
  'Estado',
  'Tipo acta',
  'N° Hallazgo',
  'Hallazgo',
  'Fecha del acta',
  'Observaciones',
  'Seguimiento',
  'F. Subsanación',
  'Tarea vinculada',
];

/// Estado del hallazgo en palabras.
///
/// La tabla lo pinta con colores y una etiqueta; un Excel en blanco y negro
/// necesita la palabra, o las tres situaciones se vuelven indistinguibles.
String estadoSubsanacionLegible(InterventoriaHallazgo h) {
  if (h.isSubsanado) return 'Subsanado';
  if (h.isPendienteAprobacion) return 'Pendiente de aprobación';
  return 'Abierto';
}

/// Una fila del archivo, ya en texto.
///
/// Todo sale como texto a propósito. Los numerales del acta son "1.1", "10.20"
/// y similares: si Excel los toma por números, "1.10" se convierte en "1.1" y
/// deja de existir un numeral. Lo mismo con las fechas, que cambian de formato
/// según la configuración regional de quien abra el archivo.
List<String> filaSubsanacion(InterventoriaHallazgo h) {
  final fmt = DateFormat('dd/MM/yyyy');
  String fecha(DateTime? t) => t == null ? '' : fmt.format(t);

  return [
    h.dptoEncargado.trim(),
    h.responsableNombre.trim(),
    h.cargoResponsable.trim(),
    fecha(h.fechaLimite?.toDate()),
    h.establecimiento.trim(),
    estadoSubsanacionLegible(h),
    (h.tipoActa ?? '').trim(),
    h.numeroHallazgo.trim(),
    h.descripcion.trim(),
    fecha(h.fechaHallazgo.toDate()),
    h.observaciones.trim(),
    h.seguimiento.trim(),
    fecha(h.fechaSubsanacion?.toDate()),
    h.tareaId.trim().isEmpty ? 'Sin tarea' : 'Sí',
  ];
}

/// Construye el archivo.
Uint8List generarExcelSubsanaciones(List<InterventoriaHallazgo> hallazgos) {
  final excel = Excel.createExcel();
  final hoja = excel['Subsanaciones'];

  // Excel crea una hoja "Sheet1" vacía que queda de primera y confunde.
  for (final nombre in excel.tables.keys.toList()) {
    if (nombre != 'Subsanaciones') excel.delete(nombre);
  }

  hoja.appendRow([for (final c in kColumnasSubsanaciones) TextCellValue(c)]);
  for (final h in hallazgos) {
    hoja.appendRow([for (final v in filaSubsanacion(h)) TextCellValue(v)]);
  }

  final bytes = excel.encode();
  return Uint8List.fromList(bytes ?? <int>[]);
}

/// Nombre del archivo, con la fecha para no pisar descargas anteriores.
String nombreArchivoSubsanaciones({DateTime? ahora}) {
  final f = ahora ?? DateTime.now();
  final y = f.year.toString().padLeft(4, '0');
  final m = f.month.toString().padLeft(2, '0');
  final d = f.day.toString().padLeft(2, '0');
  return 'subsanaciones_$y$m$d';
}
