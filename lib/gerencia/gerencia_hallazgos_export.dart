// lib/gerencia/gerencia_hallazgos_export.dart
//
// Exportación del informe de hallazgos de Gerencia (reunión del 18 sep 2026).
//
// Lo que se exporta es **lo que está en pantalla**: si Gerencia está viendo
// un establecimiento y dentro de él una sección del acta, el archivo trae
// esos hallazgos y no todos. Un archivo que no coincide con lo que se veía
// obliga a rehacer el filtro en Excel y a explicar la diferencia.
//
// El Excel sirve para cualquier nivel (todo lo filtrado, un grupo, una
// sección). El PDF se acordó solo para la vista de detalle, "para no enredar":
// trae el resumen por sección y la lista, en el orden de la pantalla.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_numerales_catalogo.dart';
import '../interventoria/interventoria_subsanaciones_export.dart';

/// Una visita corresponde a un acta guardada, aunque no tenga hallazgos.
class SemanaVisitas {
  final DateTime lunes;
  final int actas;
  const SemanaVisitas(this.lunes, this.actas);
}

List<SemanaVisitas> contarVisitasPorSemana(
  List<InterventoriaVisita> visitas, {
  DateTime? desde,
  DateTime? hasta,
}) {
  final conteo = <DateTime, int>{};
  for (final visita in visitas) {
    final fecha = visita.fechaVisita.toDate();
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    if (desde != null &&
        dia.isBefore(DateTime(desde.year, desde.month, desde.day))) {
      continue;
    }
    if (hasta != null &&
        dia.isAfter(DateTime(hasta.year, hasta.month, hasta.day))) {
      continue;
    }
    final lunes = dia.subtract(Duration(days: dia.weekday - DateTime.monday));
    conteo[lunes] = (conteo[lunes] ?? 0) + 1;
  }
  return [
    for (final lunes in (conteo.keys.toList()..sort((a, b) => b.compareTo(a))))
      SemanaVisitas(lunes, conteo[lunes]!),
  ];
}

String establecimientoReporte(InterventoriaHallazgo h) {
  final centro = h.centroCostoNombre.trim();
  final sub = h.subcentroNombre.trim();
  if (sub.isEmpty) return h.establecimiento;
  return '$centro / $sub';
}

Uint8List generarExcelVisitasGerencia(
  List<InterventoriaVisita> visitas,
  String periodo,
) {
  final excel = Excel.createExcel();
  final hoja = excel['Visitas'];
  for (final nombre in excel.tables.keys.toList()) {
    if (nombre != 'Visitas') excel.delete(nombre);
  }
  hoja.appendRow([TextCellValue('Período'), TextCellValue(periodo)]);
  hoja.appendRow([TextCellValue('Actas'), IntCellValue(visitas.length)]);
  hoja.appendRow(<CellValue>[]);
  hoja.appendRow([
    TextCellValue('Fecha del acta'),
    TextCellValue('Centro principal'),
    TextCellValue('Subcentro'),
    TextCellValue('Tipo de acta'),
  ]);
  final ordenadas = visitas.toList()
    ..sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
  for (final v in ordenadas) {
    hoja.appendRow([
      TextCellValue(DateFormat('dd/MM/yyyy').format(v.fechaVisita.toDate())),
      TextCellValue(v.centroCostoNombre),
      TextCellValue(v.subcentroNombre),
      TextCellValue(v.tipoActa ?? ''),
    ]);
  }
  final resumen = excel['Por semana'];
  resumen.appendRow([TextCellValue('Semana desde'), TextCellValue('Actas')]);
  for (final s in contarVisitasPorSemana(visitas)) {
    resumen.appendRow([
      TextCellValue(DateFormat('dd/MM/yyyy').format(s.lunes)),
      IntCellValue(s.actas),
    ]);
  }
  return Uint8List.fromList(excel.encode() ?? <int>[]);
}

Future<Uint8List> generarPdfVisitasGerencia(
  List<InterventoriaVisita> visitas,
  String periodo,
) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final semanas = contarVisitasPorSemana(visitas);
  final fmt = DateFormat('dd/MM/yyyy');
  final ordenadas = visitas.toList()
    ..sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}'),
      ),
      build: (_) => [
        pw.Text(
          'Visitas de interventoría',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('$periodo · ${visitas.length} actas'),
        pw.SizedBox(height: 12),
        pw.Text(
          'Resumen por semana',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.TableHelper.fromTextArray(
          headers: ['Semana desde', 'Actas'],
          data: [
            for (final s in semanas) [fmt.format(s.lunes), '${s.actas}'],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Actas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Fecha', 'Centro principal', 'Subcentro', 'Tipo de acta'],
          data: [
            for (final v in ordenadas)
              [
                fmt.format(v.fechaVisita.toDate()),
                v.centroCostoNombre,
                v.subcentroNombre,
                v.tipoActa ?? '',
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Sección del acta (1..11) a la que pertenece un hallazgo, o 0 si no se
/// puede saber. Sale del numeral ("3.2" → 3); los hallazgos manuales sin
/// numeral y las observaciones generales (90.x) no pertenecen a ninguna.
int seccionDelHallazgo(InterventoriaHallazgo h) {
  final numeral = h.numeralParaMatriz;
  if (numeral.isEmpty) return 0;
  final s = int.tryParse(numeral.split('.').first) ?? 0;
  return kInterventoriaSeccionNombres.containsKey(s) ? s : 0;
}

/// Título corto de la sección para chips y encabezados: "3 · Almacenamiento…".
String etiquetaSeccion(int seccion) {
  if (seccion == 0) return 'Sin numeral';
  final nombre = kInterventoriaSeccionNombres[seccion] ?? '';
  return nombre.isEmpty ? 'Numeral $seccion' : '$seccion · ${_titulo(nombre)}';
}

String _titulo(String mayusculas) {
  final limpio = mayusculas.replaceAll(RegExp(r'\s+'), ' ').trim();
  return limpio
      .split(' ')
      .map((w) {
        if (w.isEmpty) return w;
        if (w == '-' || w == 'Y' || w == 'E' || w == 'DE' || w == 'DEL') {
          return w.toLowerCase();
        }
        return w[0] + w.substring(1).toLowerCase();
      })
      .join(' ');
}

/// Conteo por sección, ordenado 1..11 y "sin numeral" al final.
///
/// Es lo que Gerencia quiere ver primero al abrir un establecimiento: en qué
/// numerales se concentra el problema, sin leer los hallazgos uno por uno.
List<MapEntry<int, int>> conteoPorSeccion(List<InterventoriaHallazgo> hs) {
  final conteo = <int, int>{};
  for (final h in hs) {
    final s = seccionDelHallazgo(h);
    conteo[s] = (conteo[s] ?? 0) + 1;
  }
  final claves = conteo.keys.toList()
    ..sort((a, b) {
      if (a == 0) return 1;
      if (b == 0) return -1;
      return a.compareTo(b);
    });
  return [for (final k in claves) MapEntry(k, conteo[k]!)];
}

/// Orden de lectura dentro de un grupo: por numeral del acta y luego por
/// fecha, de la más reciente a la más antigua.
int compararPorNumeral(InterventoriaHallazgo a, InterventoriaHallazgo b) {
  final sa = seccionDelHallazgo(a);
  final sb = seccionDelHallazgo(b);
  if (sa != sb) {
    if (sa == 0) return 1;
    if (sb == 0) return -1;
    return sa.compareTo(sb);
  }
  final na = _sub(a.numeralParaMatriz);
  final nb = _sub(b.numeralParaMatriz);
  if (na != nb) return na.compareTo(nb);
  return b.fechaHallazgo.compareTo(a.fechaHallazgo);
}

int _sub(String numeral) {
  final partes = numeral.split('.');
  if (partes.length < 2) return 0;
  return int.tryParse(partes[1]) ?? 0;
}

/// Qué se está exportando, para el nombre del archivo y la primera fila.
class AlcanceExportacion {
  /// "Todos los hallazgos filtrados", "Buen Pastor — Alta", etc.
  final String titulo;

  /// Filtros vigentes en palabras ("Últimos 30 días · Área: Nutrición").
  final String filtros;

  const AlcanceExportacion({required this.titulo, this.filtros = ''});
}

/// Excel con las mismas columnas de Subsanaciones, más "Sección del acta",
/// precedido de dos filas con el alcance y los filtros. Quien recibe el
/// archivo sabe de qué recorte salió sin abrir la app.
Uint8List generarExcelHallazgosGerencia(
  List<InterventoriaHallazgo> hallazgos,
  AlcanceExportacion alcance, {
  String Function(InterventoriaHallazgo)? nombreArea,
}) {
  final excel = Excel.createExcel();
  const nombreHoja = 'Hallazgos';
  final hoja = excel[nombreHoja];
  for (final nombre in excel.tables.keys.toList()) {
    if (nombre != nombreHoja) excel.delete(nombre);
  }
  hoja.appendRow([TextCellValue('Alcance'), TextCellValue(alcance.titulo)]);
  hoja.appendRow([
    TextCellValue('Filtros'),
    TextCellValue(alcance.filtros.isEmpty ? 'Ninguno' : alcance.filtros),
  ]);
  hoja.appendRow([
    TextCellValue('Generado'),
    TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
  ]);
  hoja.appendRow(<CellValue>[]);
  hoja.appendRow([
    TextCellValue('Sección del acta'),
    TextCellValue('Área responsable'),
    TextCellValue('Centro principal'),
    TextCellValue('Subcentro'),
    for (final c in kColumnasSubsanaciones) TextCellValue(c),
  ]);
  final ordenados = hallazgos.toList()..sort(compararPorNumeral);
  for (final h in ordenados) {
    hoja.appendRow([
      TextCellValue(etiquetaSeccion(seccionDelHallazgo(h))),
      TextCellValue(nombreArea?.call(h) ?? h.dptoEncargado),
      TextCellValue(h.centroCostoNombre),
      TextCellValue(h.subcentroNombre),
      for (final v in filaSubsanacion(h)) TextCellValue(v),
    ]);
  }
  return Uint8List.fromList(excel.encode() ?? <int>[]);
}

/// PDF de la vista de detalle: encabezado con alcance y filtros, resumen por
/// sección y la tabla de hallazgos en apaisado.
Future<Uint8List> generarPdfHallazgosGerencia(
  List<InterventoriaHallazgo> hallazgos,
  AlcanceExportacion alcance, {
  String empresaNombre = '',
  String Function(InterventoriaHallazgo)? nombreArea,
}) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final fmt = DateFormat('dd/MM/yyyy');
  final ordenados = hallazgos.toList()..sort(compararPorNumeral);
  final resumen = conteoPorSeccion(ordenados);
  const azul = PdfColor.fromInt(0xFF0F172A);
  const gris = PdfColors.grey300;

  pw.Widget celda(String t, {bool negrita = false, PdfColor? fondo}) =>
      pw.Container(
        color: fondo,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  String estado(InterventoriaHallazgo h) => estadoSubsanacionLegible(h);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        pw.Text(
          'Informe de hallazgos de Interventoría',
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: azul,
          ),
        ),
        if (empresaNombre.trim().isNotEmpty)
          pw.Text(empresaNombre, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 4),
        pw.Text(
          alcance.titulo,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Filtros: ${alcance.filtros.isEmpty ? 'ninguno' : alcance.filtros}'
          '   ·   Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'
          '   ·   ${ordenados.length} hallazgo${ordenados.length == 1 ? '' : 's'}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Resumen por sección del acta',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: gris, width: .5),
          columnWidths: {
            0: const pw.FlexColumnWidth(6),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FixedColumnWidth(60),
            3: const pw.FixedColumnWidth(60),
          },
          children: [
            pw.TableRow(
              children: [
                celda('Sección', negrita: true, fondo: gris),
                celda('Hallazgos', negrita: true, fondo: gris),
                celda('Abiertos', negrita: true, fondo: gris),
                celda('Subsanados', negrita: true, fondo: gris),
              ],
            ),
            for (final e in resumen)
              pw.TableRow(
                children: [
                  celda(etiquetaSeccion(e.key)),
                  celda('${e.value}'),
                  celda(
                    '${ordenados.where((h) => seccionDelHallazgo(h) == e.key && !h.isSubsanado).length}',
                  ),
                  celda(
                    '${ordenados.where((h) => seccionDelHallazgo(h) == e.key && h.isSubsanado).length}',
                  ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Hallazgos',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: gris, width: .5),
          columnWidths: {
            0: const pw.FixedColumnWidth(34),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(5),
            4: const pw.FlexColumnWidth(3),
            5: const pw.FixedColumnWidth(52),
            6: const pw.FixedColumnWidth(48),
            7: const pw.FixedColumnWidth(48),
          },
          children: [
            pw.TableRow(
              repeat: true,
              children: [
                celda('Numeral', negrita: true, fondo: gris),
                celda('Establecimiento', negrita: true, fondo: gris),
                celda('Área responsable', negrita: true, fondo: gris),
                celda('Hallazgo', negrita: true, fondo: gris),
                celda('Responsable', negrita: true, fondo: gris),
                celda('Estado', negrita: true, fondo: gris),
                celda('Acta', negrita: true, fondo: gris),
                celda('Vence', negrita: true, fondo: gris),
              ],
            ),
            for (final h in ordenados)
              pw.TableRow(
                children: [
                  celda(
                    h.numeralParaMatriz.isEmpty
                        ? h.numeroHallazgo.trim()
                        : h.numeralParaMatriz,
                  ),
                  celda(establecimientoReporte(h)),
                  celda(nombreArea?.call(h) ?? h.dptoEncargado),
                  celda(
                    h.observaciones.trim().isEmpty
                        ? h.descripcion.trim()
                        : '${h.descripcion.trim()}\n${h.observaciones.trim()}',
                  ),
                  celda(
                    h.responsableNombre.trim().isEmpty
                        ? 'Sin responsable'
                        : '${h.responsableNombre.trim()}'
                              '${h.cargoResponsable.trim().isEmpty ? '' : '\n${h.cargoResponsable.trim()}'}',
                  ),
                  celda(estado(h)),
                  celda(fmt.format(h.fechaHallazgo.toDate())),
                  celda(
                    h.fechaLimite == null
                        ? ''
                        : fmt.format(h.fechaLimite!.toDate()),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Nombre de archivo sin extensión: "hallazgos_gerencia_buen_pastor_20260921".
String nombreArchivoHallazgosGerencia(String titulo, {DateTime? ahora}) {
  final f = ahora ?? DateTime.now();
  final y = f.year.toString().padLeft(4, '0');
  final m = f.month.toString().padLeft(2, '0');
  final d = f.day.toString().padLeft(2, '0');
  final slug = titulo
      .toLowerCase()
      .replaceAll(RegExp(r'[áà]'), 'a')
      .replaceAll(RegExp(r'[éè]'), 'e')
      .replaceAll(RegExp(r'[íì]'), 'i')
      .replaceAll(RegExp(r'[óò]'), 'o')
      .replaceAll(RegExp(r'[úù]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final base = slug.isEmpty ? 'hallazgos_gerencia' : 'hallazgos_$slug';
  return '${base.length > 60 ? base.substring(0, 60) : base}_$y$m$d';
}
