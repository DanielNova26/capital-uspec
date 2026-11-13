import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/subcentros_costo.dart';
import 'mantenimiento_service.dart';

Future<Uint8List> generarInformeMantenimiento({
  required String empresaId,
  required String alcance,
  required List<OrdenMantenimiento> ordenes,
  required Map<String, String> centros,
  required Map<String, EquipoMantenimiento> equipos,
  bool ordenIndividual = false,
  Future<Uint8List> Function(ArchivoOrden)? fotos,
}) async {
  final documento = pw.Document(title: 'Informe de mantenimiento');
  final fuente = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final evidencias = <ArchivoOrden, pw.MemoryImage>{};
  if (fotos != null) {
    for (final orden in ordenes) {
      for (final archivo in orden.archivos.where((a) => a.clase.soloFotos)) {
        evidencias[archivo] = pw.MemoryImage(await fotos(archivo));
      }
    }
  }
  final formato = DateFormat('dd/MM/yyyy');
  String fecha(DateTime? valor) => valor == null ? '—' : formato.format(valor);
  String texto(String valor) => valor.replaceAll(RegExp(r'\s+'), ' ').trim();
  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: ordenes.length * 6 + 4,
      theme: pw.ThemeData.withFont(base: fuente, bold: fuente),
      header: (_) => pw.Text('MANTENIMIENTO · $empresaId'),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
      ),
      build: (_) => [
        pw.SizedBox(height: 14),
        pw.Text(
          ordenIndividual
              ? 'Orden de trabajo'
              : 'Informe de órdenes de trabajo',
          style: pw.TextStyle(fontSize: 22),
        ),
        pw.Paragraph(text: alcance),
        if (!ordenIndividual)
          pw.Paragraph(
            text:
                'Generado el ${fecha(DateTime.now())} · ${ordenes.length} órdenes',
          ),
        if (!ordenIndividual)
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
            text:
                'Orden ${orden.referencia} · ${orden.tipo.label} · ${orden.estado.label}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(
            text:
                '${nombreEstablecimiento(centros[orden.centroDocId] ?? orden.centroDocId, orden.subcentroNombre)}'
                '${orden.equipoId.isEmpty ? '' : ' / ${equipos[orden.equipoId]?.nombre ?? orden.equipoId}'}'
                ' · Apertura ${fecha(orden.creada)}'
                '${orden.cerrada == null ? '' : ' · Cierre ${fecha(orden.cerrada)}'}',
          ),
          if (orden.titulo.isNotEmpty) pw.Paragraph(text: texto(orden.titulo)),
          if (orden.intervencion case final intervencion?)
            pw.Paragraph(text: 'Intervención: ${intervencion.label}'),
          pw.Paragraph(text: 'Diagnóstico: ${texto(orden.detalle)}'),
          if (orden.origenTarea case final origen?)
            pw.Paragraph(
              text:
                  'Tarea de origen: ${origen.label}'
                  '${orden.numeroTarea == null ? '' : ' · ${orden.numeroTarea}'}'
                  '${orden.responsableTarea.isEmpty ? '' : ' · ${orden.responsableTarea}'}'
                  '${orden.limiteTarea == null ? '' : ' · Fecha límite ${fecha(orden.limiteTarea)}'}',
            ),
          if (orden.hallazgoExterno.isNotEmpty)
            pw.Paragraph(
              text:
                  'Hallazgo de ${orden.hallazgoExterno['entidad']}. '
                  '${orden.hallazgoExterno['descripcion']}. '
                  'Reportado ${orden.hallazgoExterno['fecha']}. Fecha límite ${orden.hallazgoExterno['limite']}.',
            ),
          if (orden.resultado.isNotEmpty)
            pw.Paragraph(text: 'Trabajo realizado: ${texto(orden.resultado)}'),
          if (orden.factura.isNotEmpty)
            pw.Paragraph(text: 'Factura: ${texto(orden.factura)}'),
          if (orden.hallazgoId.isNotEmpty)
            pw.Paragraph(
              text: 'Hallazgo de Interventoría: ${orden.hallazgoId}',
            ),
          if (orden.cierre case final cierre?
              when orden.estado == EstadoOrden.cerrada) ...[
            if (cierre.materiales.isNotEmpty)
              pw.Paragraph(text: 'Materiales: ${texto(cierre.materiales)}'),
            if (cierre.sugerencias.isNotEmpty)
              pw.Paragraph(text: 'Sugerencias: ${texto(cierre.sugerencias)}'),
            pw.Paragraph(text: 'Técnico: ${texto(cierre.tecnico)}'),
            pw.Paragraph(
              text:
                  'Recibió: ${texto(cierre.receptor)} ${texto(cierre.cargoReceptor)}',
            ),
          ],
          if (ordenIndividual)
            for (final clase in ClaseArchivoOrden.values)
              if (orden.archivos.any((a) => a.clase == clase)) ...[
                pw.Paragraph(text: clase.label),
                for (final archivo in orden.archivos.where(
                  (a) => a.clase == clase,
                )) ...[
                  pw.Paragraph(text: archivo.nombre),
                  if (evidencias[archivo] case final foto?)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 12),
                      child: pw.Image(
                        foto,
                        width: 350,
                        height: 210,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                ],
              ],
        ],
      ],
    ),
  );
  return documento.save();
}
