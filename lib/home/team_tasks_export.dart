// lib/home/team_tasks_export.dart
//
// Excel y PDF de "Tareas de mi equipo" (3 oct 2026: "poder generar Excel y
// PDF de las tareas según filtro, igual como funciona el módulo de
// Interventoría").
//
// Igual que en Interventoría, se exporta lo que está en pantalla, con los
// filtros aplicados, y las columnas siguen el orden de la matriz: un archivo
// que no coincide con lo que se veía obliga a rehacer el filtro.

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Una fila de la matriz, ya en texto.
class TareaEquipoFila {
  final String numero;
  final String responsable;
  final String titulo;
  final String descripcion;
  final String asignadaPor;
  final DateTime? fechaAsignacion;
  final DateTime? fechaLimite;
  final String estado;
  final int? dias;
  final String modulo;
  final String area;

  const TareaEquipoFila({
    required this.numero,
    required this.responsable,
    required this.titulo,
    this.descripcion = '',
    required this.asignadaPor,
    this.fechaAsignacion,
    this.fechaLimite,
    required this.estado,
    this.dias,
    this.modulo = '',
    this.area = '',
  });
}

/// Cabeceras, en el orden de la matriz y con los datos de apoyo al final.
const List<String> kColumnasTareasEquipo = [
  'N.º tarea',
  'Responsable',
  'Descripción',
  'Asignada por',
  'Fecha asignación',
  'Estado',
  'Días',
  'Detalle',
  'Fecha límite',
  'Área',
  'Origen',
];

String _fecha(DateTime? d) =>
    d == null ? '' : DateFormat('dd/MM/yyyy').format(d);

/// Todo como texto: el número de tarea y las fechas no deben cambiar de
/// formato según la configuración regional de quien abra el archivo.
List<String> filaTareaEquipo(TareaEquipoFila f) => [
  f.numero,
  f.responsable,
  f.titulo,
  f.asignadaPor,
  _fecha(f.fechaAsignacion),
  f.estado,
  f.dias == null ? '' : '${f.dias}',
  f.descripcion,
  _fecha(f.fechaLimite),
  f.area,
  f.modulo,
];

Uint8List generarExcelTareasEquipo(List<TareaEquipoFila> filas) {
  final excel = Excel.createExcel();
  const nombreHoja = 'Tareas del equipo';
  final hoja = excel[nombreHoja];
  // Excel crea una hoja "Sheet1" vacía que queda de primera y confunde.
  for (final nombre in excel.tables.keys.toList()) {
    if (nombre != nombreHoja) excel.delete(nombre);
  }
  hoja.appendRow([for (final c in kColumnasTareasEquipo) TextCellValue(c)]);
  for (final f in filas) {
    hoja.appendRow([for (final v in filaTareaEquipo(f)) TextCellValue(v)]);
  }
  return Uint8List.fromList(excel.encode() ?? <int>[]);
}

/// El PDF lleva las siete columnas de la matriz (el detalle no cabe).
const List<String> kColumnasPdfTareasEquipo = [
  'N.º',
  'Responsable',
  'Descripción',
  'Asignada por',
  'Asignación',
  'Estado',
  'Días',
];

/// Helvetica, la fuente por defecto, no trae guiones largos ni comillas
/// tipográficas: se cambian por equivalentes para no romper el archivo
/// cuando no se pudo cargar Arial.
String _textoPdf(String s) => s
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'[^\u0000-ÿ]'), '');

Future<Uint8List> generarPdfTareasEquipo(
  List<TareaEquipoFila> filas, {
  required String empresa,
  required String filtro,
  pw.ThemeData? tema,
  DateTime? generado,
}) async {
  final fecha = DateFormat(
    'dd/MM/yyyy HH:mm',
  ).format(generado ?? DateTime.now());
  final texto = tema == null ? _textoPdf : (String s) => s;
  final doc = pw.Document(theme: tema);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Tareas de mi equipo',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            texto('$empresa · Generado el $fecha · ${filas.length} tareas'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          if (filtro.trim().isNotEmpty)
            pw.Text(
              texto('Filtro: $filtro'),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: kColumnasPdfTareasEquipo,
          data: [
            for (final f in filas)
              [
                f.numero,
                texto(f.responsable),
                texto(f.titulo),
                texto(f.asignadaPor),
                _fecha(f.fechaAsignacion),
                texto(f.estado),
                f.dias == null ? '' : '${f.dias}',
              ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF145DA0),
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            4: pw.Alignment.center,
            5: pw.Alignment.center,
            6: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(42),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(4),
            3: const pw.FlexColumnWidth(2.2),
            4: const pw.FixedColumnWidth(60),
            5: const pw.FixedColumnWidth(68),
            6: const pw.FixedColumnWidth(32),
          },
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Nombre del archivo, con la fecha para no pisar descargas anteriores.
String nombreArchivoTareasEquipo({DateTime? ahora}) {
  final f = ahora ?? DateTime.now();
  return 'tareas_equipo_${DateFormat('yyyyMMdd_HHmm').format(f)}';
}
