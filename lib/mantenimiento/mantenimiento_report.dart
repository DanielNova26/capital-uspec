import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/subcentros_costo.dart';
import '../services/company_branding_service.dart';
import 'mantenimiento_service.dart';

const _tinta = PdfColor.fromInt(0xff173c4a);
const _fondo = PdfColor.fromInt(0xffedf4f5);
const _gris = PdfColor.fromInt(0xff5f6f75);
const _linea = PdfColor.fromInt(0xffcdd9dc);

Future<({String nombre, Uint8List? logo})> marcaMantenimiento(
  String empresaId,
) async {
  final empresa = await FirebaseFirestore.instance
      .collection('TBL_EMPRESAS')
      .doc(empresaId)
      .get();
  final nombre = (empresa.data()?['nombre'] ?? '').toString().trim();
  final logo = await CompanyBrandingService().loadLogoBytes(empresaId);
  return (nombre: nombre, logo: logo);
}

/// Imagen del logo, o null si los bytes no son PNG/JPEG decodificables
/// (SVG, WebP, archivo dañado): un logo malo nunca debe tumbar el PDF.
pw.MemoryImage? _imagenSegura(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    return pw.MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}

pw.Widget membreteMantenimiento(
  String titulo, {
  String nombre = '',
  Uint8List? logo,
  String subtitulo = '',
}) {
  final imagen = _imagenSegura(logo);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 10),
    decoration: const pw.BoxDecoration(
      color: _fondo,
      border: pw.Border(bottom: pw.BorderSide(color: _tinta, width: 2)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (imagen != null) ...[
          pw.SizedBox(
            width: 84,
            height: 54,
            child: pw.Image(imagen, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 14),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (nombre.isNotEmpty)
                pw.Text(
                  nombre.toUpperCase(),
                  style: const pw.TextStyle(fontSize: 10, color: _tinta),
                ),
              pw.SizedBox(height: 3),
              pw.Text(
                titulo,
                style: const pw.TextStyle(fontSize: 19, color: _tinta),
              ),
              if (subtitulo.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitulo,
                  style: const pw.TextStyle(fontSize: 9, color: _gris),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Future<Uint8List> generarInformeMantenimiento({
  required String empresaId,
  required String alcance,
  required List<OrdenMantenimiento> ordenes,
  required Map<String, String> centros,
  required Map<String, EquipoMantenimiento> equipos,
  bool ordenIndividual = false,
  String empresaNombre = '',
  Uint8List? empresaLogo,
  Future<Uint8List> Function(ArchivoOrden)? fotos,
}) async {
  final documento = pw.Document(title: 'Informe de mantenimiento');
  final membrete = membreteMantenimiento(
    ordenIndividual ? 'Orden de trabajo' : 'Informe de órdenes de trabajo',
    nombre: empresaNombre.isEmpty ? empresaId : empresaNombre,
    logo: empresaLogo,
    subtitulo: alcance,
  );
  final fuente = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final evidencias = <ArchivoOrden, pw.MemoryImage>{};
  if (fotos != null) {
    for (final orden in ordenes) {
      for (final archivo in orden.archivos.where((a) => a.clase.soloFotos)) {
        final foto = _imagenSegura(await fotos(archivo));
        if (foto != null) evidencias[archivo] = foto;
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
      header: (_) => membrete,
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _linea, width: 0.5)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                '${empresaNombre.isEmpty ? empresaId : empresaNombre}'
                ' · Generado el ${fecha(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _gris),
            ),
          ],
        ),
      ),
      build: (_) => [
        pw.SizedBox(height: 14),
        if (!ordenIndividual)
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Resumen · ${ordenes.length} '
                  '${ordenes.length == 1 ? 'orden' : 'órdenes'}',
                  style: const pw.TextStyle(fontSize: 12, color: _tinta),
                ),
                pw.SizedBox(height: 5),
                pw.TableHelper.fromTextArray(
                  headers: [
                    for (final estado in EstadoOrden.values) estado.label,
                  ],
                  data: [
                    [
                      for (final estado in EstadoOrden.values)
                        '${ordenes.where((o) => o.estado == estado).length}',
                    ],
                  ],
                  headerStyle: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(color: _tinta),
                  cellStyle: const pw.TextStyle(fontSize: 11),
                  cellAlignment: pw.Alignment.center,
                  cellPadding: const pw.EdgeInsets.all(5),
                  border: pw.TableBorder.all(color: _linea, width: 0.5),
                ),
                pw.SizedBox(height: 6),
              ],
            ),
          ),
        for (final orden in ordenes) ...[
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            padding: const pw.EdgeInsets.all(9),
            decoration: const pw.BoxDecoration(
              color: _fondo,
              border: pw.Border(left: pw.BorderSide(color: _tinta, width: 3)),
            ),
            child: pw.Text(
              'Orden ${orden.referencia} · ${orden.tipo.label} · ${orden.estado.label}',
              style: const pw.TextStyle(color: _tinta, fontSize: 12),
            ),
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
          if (orden.actividades.isNotEmpty)
            pw.Paragraph(
              text: 'Actividades a realizar: ${texto(orden.actividades)}',
            ),
          for (final tarea in orden.tareasOrigen)
            pw.Paragraph(
              text:
                  'Tarea ${tarea.numero ?? tarea.id} · ${tarea.origen.label} · ${tarea.titulo}'
                  '${tarea.responsable.isEmpty ? '' : ' · ${tarea.responsable}'}'
                  '${tarea.fechaLimite == null ? '' : ' · Plazo ${fecha(tarea.fechaLimite)}'}',
            ),
          if (orden.tareasOrigen.isEmpty && orden.origenTarea != null)
            pw.Paragraph(
              text:
                  'Tarea de origen: ${orden.origenTarea!.label}'
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
                        width:
                            clase == ClaseArchivoOrden.firmaTecnico ||
                                clase == ClaseArchivoOrden.firmaReceptor
                            ? 170
                            : 350,
                        height:
                            clase == ClaseArchivoOrden.firmaTecnico ||
                                clase == ClaseArchivoOrden.firmaReceptor
                            ? 72
                            : 210,
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
