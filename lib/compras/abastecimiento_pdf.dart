// PDF de Abastecimiento con lo que se está viendo (30 sep 2026).
//
// El reporte debe corresponder a los filtros aplicados en la pantalla y
// mostrar el nombre de la empresa, nunca su id. Se arma en el dispositivo
// con las mismas entregas visibles, así Web y móvil sacan el mismo archivo.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'abastecimiento_models.dart';

const _azul = PdfColor.fromInt(0xFF0F4C81);
const _gris = PdfColor.fromInt(0xFF475569);
const _cabecera = PdfColor.fromInt(0xFFEAF1F8);

/// Arial del proyecto para que tildes y ñ salgan completas. En web un asset
/// inexistente devuelve index.html, así que se revisa la firma del archivo.
Future<pw.Font?> cargarFuentePdfAbastecimiento() async {
  try {
    final data = await rootBundle.load('assets/arial.ttf');
    if (data.lengthInBytes < 4) return null;
    const firmas = {0x00010000, 0x4F54544F, 0x74727565, 0x74746366};
    if (!firmas.contains(data.getUint32(0))) return null;
    return pw.Font.ttf(data);
  } catch (_) {
    return null;
  }
}

Future<Uint8List> construirPdfAbastecimiento({
  required String empresaNombre,
  required List<String> filtros,
  required List<AbastecimientoDoc> entregas,
  required DateTime generado,
  pw.Font? fuente,
}) {
  final fecha = DateFormat('dd/MM/yyyy');
  String dia(DateTime? value) =>
      value == null ? 'Sin fecha' : fecha.format(value);
  String texto(String value) => value.trim().isEmpty ? '—' : value.trim();

  final doc = pw.Document(
    title: 'Programación de abastecimiento',
    theme: fuente == null
        ? null
        : pw.ThemeData.withFont(base: fuente, bold: fuente),
  );
  final headerStyle = pw.TextStyle(
    fontSize: 7.5,
    fontWeight: pw.FontWeight.bold,
    color: _azul,
  );
  const cellStyle = pw.TextStyle(fontSize: 7);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PROGRAMACIÓN DE ABASTECIMIENTO',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: _azul,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Empresa: ${texto(empresaNombre)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            filtros.isEmpty
                ? 'Filtros: ninguno (todas las entregas)'
                : 'Filtros: ${filtros.join(' · ')}',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
          pw.Text(
            '${entregas.length} registro${entregas.length == 1 ? '' : 's'} · '
            'Generado el ${DateFormat('dd/MM/yyyy HH:mm').format(generado)}',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: _gris),
        ),
      ),
      build: (context) => [
        if (entregas.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Text('No hay entregas con estos filtros.'),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: const [
              'Fecha',
              'Consumo',
              'Proveedor',
              'Producto',
              'Grupo',
              'Destino',
              'OC',
              'Estado',
              'Entrada',
            ],
            data: [
              for (final row in entregas)
                [
                  dia(row.fechaProgramada),
                  row.periodo == null
                      ? '—'
                      : '${fecha.format(row.periodo!.desde)} a '
                            '${fecha.format(row.periodo!.hasta)}',
                  texto(row.proveedor),
                  texto(row.producto),
                  texto(row.grupo),
                  texto(row.destino),
                  texto(row.ordenCompra),
                  row.estado.label,
                  texto(row.numeroEntrada),
                ],
            ],
            headerStyle: headerStyle,
            headerDecoration: const pw.BoxDecoration(color: _cabecera),
            cellStyle: cellStyle,
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.1),
              1: pw.FlexColumnWidth(1.7),
              2: pw.FlexColumnWidth(2.6),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.5),
              6: pw.FlexColumnWidth(1.3),
              7: pw.FlexColumnWidth(1.2),
              8: pw.FlexColumnWidth(1.2),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColor.fromInt(0xFFD7DFEA),
                width: 0.5,
              ),
              bottom: pw.BorderSide(
                color: PdfColor.fromInt(0xFFD7DFEA),
                width: 0.5,
              ),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
