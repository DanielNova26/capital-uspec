import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'mantenimiento_service.dart';

Future<Uint8List> generarInformeMantenimiento({
  required String empresaId,
  required String alcance,
  required List<OrdenMantenimiento> ordenes,
  required Map<String, String> centros,
  required Map<String, EquipoMantenimiento> equipos,
}) async {
  final documento = pw.Document(title: 'Informe de mantenimiento');
  final fuente = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final formato = DateFormat('dd/MM/yyyy');
  String fecha(DateTime? valor) => valor == null ? '—' : formato.format(valor);
  String texto(String valor) => valor.replaceAll(RegExp(r'\s+'), ' ').trim();
  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: ordenes.length * 3 + 2,
      theme: pw.ThemeData.withFont(base: fuente, bold: fuente),
      header: (_) => pw.Text('MANTENIMIENTO · $empresaId'),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
      ),
      build: (_) => [
        pw.SizedBox(height: 14),
        pw.Text(
          'Informe de órdenes de trabajo',
          style: pw.TextStyle(fontSize: 22),
        ),
        pw.Paragraph(text: alcance),
        pw.Paragraph(
          text:
              'Generado el ${fecha(DateTime.now())} · ${ordenes.length} órdenes',
        ),
        pw.Paragraph(
          text: EstadoOrden.values
              .map(
                (estado) =>
                    '${estado.label}: '
                    '${ordenes.where((orden) => orden.estado == estado).length}',
              )
              .join('   |   '),
        ),
        for (final orden in ordenes) ...[
          pw.Divider(),
          pw.Paragraph(
            text: '${orden.tipo.label} · ${orden.estado.label} · ${orden.id}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(
            text:
                '${centros[orden.centroDocId] ?? orden.centroDocId}'
                '${orden.equipoId.isEmpty ? '' : ' / ${equipos[orden.equipoId]?.nombre ?? orden.equipoId}'}'
                ' · Apertura ${fecha(orden.creada)}'
                '${orden.cerrada == null ? '' : ' · Cierre ${fecha(orden.cerrada)}'}',
          ),
          pw.Paragraph(text: texto(orden.detalle)),
          if (orden.resultado.isNotEmpty)
            pw.Paragraph(text: 'Trabajo realizado: ${texto(orden.resultado)}'),
          if (orden.factura.isNotEmpty)
            pw.Paragraph(text: 'Factura: ${texto(orden.factura)}'),
          if (orden.hallazgoId.isNotEmpty)
            pw.Paragraph(
              text: 'Hallazgo de Interventoría: ${orden.hallazgoId}',
            ),
        ],
      ],
    ),
  );
  return documento.save();
}
