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

pw.Widget membreteMantenimiento(
  String titulo, {
  String nombre = '',
  Uint8List? logo,
}) => pw.Container(
  padding: const pw.EdgeInsets.all(14),
  decoration: const pw.BoxDecoration(color: _fondo),
  child: pw.Row(
    children: [
      if (logo != null) ...[
        pw.Image(
          pw.MemoryImage(logo),
          width: 72,
          height: 48,
          fit: pw.BoxFit.contain,
        ),
        pw.SizedBox(width: 14),
      ],
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (nombre.isNotEmpty)
              pw.Text(nombre, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 4),
            pw.Text(
              titulo,
              style: const pw.TextStyle(fontSize: 20, color: _tinta),
            ),
          ],
        ),
      ),
    ],
  ),
);

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
  );
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
      header: (_) => membrete,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
      ),
      build: (_) => [
        pw.SizedBox(height: 14),
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
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            padding: const pw.EdgeInsets.all(9),
            color: _fondo,
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
