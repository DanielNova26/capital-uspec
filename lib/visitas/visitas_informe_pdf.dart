// lib/visitas/visitas_informe_pdf.dart
//
// Los dos informes que pidió la reunión: el de UNA visita, que sale solo al
// cerrarla, y el consolidado del mes por área, que reemplaza el informe que
// hoy se arma a mano juntando actas.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'visitas_models.dart';

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _marca(VisitaMarca? m) {
  if (m == null) return '—';
  final t = m.at.toDate().toLocal();
  final ubi = m.tieneUbicacion
      ? ' · ${m.lat!.toStringAsFixed(5)}, ${m.lng!.toStringAsFixed(5)}'
            '${m.precisionMetros == null ? '' : ' (±${m.precisionMetros!.round()} m)'}'
      : ' · sin ubicación';
  return '${_dd(t)} ${_hhmm(t)}$ubi';
}

const _kMeses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String nombreMes(int mes) => _kMeses[mes - 1];

pw.Widget _titulo(String t) => pw.Text(
  t,
  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
);

pw.Widget _fila(String k, String v) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 2),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 130,
        child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700)),
      ),
      pw.Expanded(child: pw.Text(v)),
    ],
  ),
);

/// Informe de una visita cerrada. Con evidencias como enlaces: incrustar
/// fotos haría PDFs de decenas de MB que nadie va a mandar por WhatsApp.
Future<Uint8List> generarInformeVisita({
  required VisitaProfesional v,
  required VisitaFormato formato,
  required String empresaNombre,
}) async {
  final resumen = resumenDeVisita(formato, v.respuestas);
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        _titulo('Informe de visita · ${v.areaNombre}'),
        pw.Text(empresaNombre, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        _fila('Establecimiento', v.establecimiento),
        _fila('Formato', '${formato.nombre} (v${formato.version})'),
        _fila('Profesional', v.profesionalNombre),
        _fila('Programada por', v.asignadoPorNombre),
        _fila('Fecha programada', _dd(v.fechaProgramada)),
        _fila('Inicio', _marca(v.inicio)),
        _fila('Cierre', _marca(v.fin)),
        _fila(
          'Cumplimiento',
          resumen.porcentaje == null
              ? 'Sin ítems evaluados'
              : '${resumen.porcentaje}%  (${resumen.cumple} cumple · '
                    '${resumen.noCumple} no cumple · ${resumen.noAplica} no aplica)',
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 9),
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FixedColumnWidth(58),
            3: const pw.FlexColumnWidth(3),
            4: const pw.FixedColumnWidth(40),
          },
          headers: ['#', 'Ítem', 'Resultado', 'Observación', 'Fotos'],
          data: [
            for (final it in formato.itemsOrdenados)
              [
                '${it.orden}',
                it.seccion.isEmpty ? it.texto : '${it.seccion}: ${it.texto}',
                kItemResultadoLabel[v.respuestas[it.id]?.resultado ?? ''] ??
                    'Sin responder',
                v.respuestas[it.id]?.observacion ?? '',
                '${v.respuestas[it.id]?.evidencias.length ?? 0}',
              ],
          ],
        ),
        if (v.observacionGeneral.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Observación general',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(v.observacionGeneral),
        ],
        ...[
          for (final it in formato.itemsOrdenados)
            if ((v.respuestas[it.id]?.evidencias ?? const []).isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Evidencias ítem ${it.orden}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                    for (final e in v.respuestas[it.id]!.evidencias)
                      pw.UrlLink(
                        destination: e.url,
                        child: pw.Text(
                          e.nombre,
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.blue700,
                            decoration: pw.TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
        pw.SizedBox(height: 16),
        pw.Text(
          'Ubicación y hora registradas por el dispositivo al iniciar y cerrar la visita.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Consolidado del mes para un área. Lo que Oscar describió como "coger
/// todas esas actas al final del mes y generar el informe".
Future<Uint8List> generarConsolidadoMensual({
  required ConsolidadoMensual c,
  required String areaNombre,
  required int anio,
  required int mes,
  required String empresaNombre,
  required List<VisitaProfesional> visitas,
}) async {
  final doc = pw.Document();
  final terminadas = visitas.where((v) => v.estado == kVisitaTerminada).toList()
    ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        _titulo('Consolidado de visitas · $areaNombre'),
        pw.Text(
          '$empresaNombre · ${nombreMes(mes)} de $anio',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 10),
        _fila('Visitas terminadas', '${c.visitasTerminadas}'),
        _fila('Sin realizar', '${c.visitasProgramadas}'),
        _fila('Canceladas', '${c.visitasCanceladas}'),
        _fila(
          'Cumplimiento promedio',
          c.promedioGeneral == null ? '—' : '${c.promedioGeneral}%',
        ),
        _fila('Hallazgos', '${c.hallazgos}'),
        pw.SizedBox(height: 12),
        pw.Text(
          'Por establecimiento',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headers: ['Establecimiento', 'Visitas', 'Cumplimiento', 'Hallazgos'],
          data: [
            for (final e in c.porEstablecimiento)
              [
                e.nombre,
                '${e.visitas}',
                e.promedio == null ? '—' : '${e.promedio}%',
                '${e.hallazgos}',
              ],
          ],
        ),
        if (c.itemsCriticos.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Lo que más se incumple',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headers: ['Ítem', 'Veces'],
            data: [
              for (final i in c.itemsCriticos.take(15))
                [i.texto, '${i.incumplimientos}'],
            ],
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Text(
          'Detalle de visitas',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: ['Fecha', 'Establecimiento', 'Profesional', '%', 'Inicio'],
          data: [
            for (final v in terminadas)
              [
                _dd(v.fechaProgramada),
                v.establecimiento,
                v.profesionalNombre,
                v.cumplimiento == null ? '—' : '${v.cumplimiento}',
                v.inicio == null ? '—' : _hhmm(v.inicio!.at.toDate().toLocal()),
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Descarga en web, abre en móvil. Mismo comportamiento que las actas de
/// Interventoría.
Future<void> entregarPdf(Uint8List bytes, String nombreSinExtension) async {
  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: nombreSinExtension,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$nombreSinExtension.pdf');
  await file.writeAsBytes(bytes);
  await OpenFilex.open(file.path);
}
