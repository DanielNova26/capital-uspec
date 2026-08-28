import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'personnel_requisition_models.dart';
import 'personnel_requisition_service.dart';

/// Informe de procesos de selección para entregar a la interventoría.
///
/// Va aparte del Excel a propósito: el Excel es la hoja de trabajo (se filtra,
/// se suma, se pega en otro lado) y este PDF es el entregable, así que está
/// **agrupado por establecimiento** —como se lee el informe, sede por sede— y
/// abre cada grupo con su propio subtotal. El Excel conserva una fila por
/// vacante porque ahí sí hace falta el detalle plano.
///
/// Cada vacante lista a sus aspirantes con la etapa individual: es el cambio
/// que pidió la interventoría, poder ver quién está en entrevistas y quién en
/// exámenes en vez de un único estado de la vacante.

const _kPrimary = PdfColor.fromInt(0xFFC28942);
const _kNavy = PdfColor.fromInt(0xFF173B5E);
const _kInk = PdfColor.fromInt(0xFF17212B);
const _kMuted = PdfColor.fromInt(0xFF64748B);
const _kBorder = PdfColor.fromInt(0xFFDCE5EC);
const _kBandBg = PdfColor.fromInt(0xFFEAF4FB);
const _kZebra = PdfColor.fromInt(0xFFF7F9FB);

final _money = NumberFormat.currency(
  locale: 'es_CO',
  symbol: r'$',
  decimalDigits: 0,
);
final _dayFormat = DateFormat('dd/MM/yyyy');

Future<Uint8List> buildPersonnelRequisitionPdf({
  required List<PersonnelRequisition> rows,
  required String empresaId,
  String empresaNombre = '',
  DateTime? generatedAt,
}) async {
  final now = generatedAt ?? DateTime.now();
  final empresa = empresaNombre.trim().isEmpty
      ? empresaId
      : empresaNombre.trim();

  // Mismo comparador que la tabla y el Excel: las tres salidas se leen igual.
  final ordered = [...rows]
    ..sort(PersonnelRequisitionService.comparePersonnelRequisitions);

  // El orden ya deja juntos los de cada establecimiento, así que agrupar es
  // recorrer una vez y cortar cuando cambia el nombre.
  final groups = <String, List<PersonnelRequisition>>{};
  for (final row in ordered) {
    final key = row.establishment.trim().isEmpty
        ? 'Sin establecimiento'
        : row.establishment.trim();
    groups.putIfAbsent(key, () => []).add(row);
  }

  final doc = pw.Document(compress: true);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 30),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : _runningHeader(empresa),
      footer: _footer,
      build: (context) => [
        _cover(empresa: empresa, now: now, rows: ordered),
        pw.SizedBox(height: 14),
        for (final entry in groups.entries) ...[
          _establishmentBand(entry.key, entry.value, now),
          pw.SizedBox(height: 6),
          _requisitionTable(entry.value, now),
          pw.SizedBox(height: 16),
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _cover({
  required String empresa,
  required DateTime now,
  required List<PersonnelRequisition> rows,
}) {
  final open = rows.where((row) => !row.isClosed).length;
  final hired = rows.fold<int>(0, (total, row) => total + row.hiredCount);
  final candidates = rows.fold<int>(
    0,
    (total, row) => total + row.activeCandidates.length,
  );
  final overdue = rows
      .where((row) => row.trafficAt(now) == PersonnelRequisitionTraffic.red)
      .length;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const pw.BoxDecoration(color: _kNavy),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'INFORME DE PROCESOS DE SELECCIÓN',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    empresa,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Generado ${_dayFormat.format(now)}',
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Organizado por establecimiento',
                  style: const pw.TextStyle(color: _kBandBg, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          _kpi('Requerimientos', '${rows.length}'),
          _kpi('Abiertos', '$open'),
          _kpi('Aspirantes en proceso', '$candidates'),
          _kpi('Contratados', '$hired'),
          _kpi('Atención prioritaria', '$overdue', highlight: overdue > 0),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Los tiempos se calculan en días hábiles desde la fecha de solicitud. '
        'Próxima a vencer desde 8 días hábiles; atención prioritaria desde 15.',
        style: const pw.TextStyle(color: _kMuted, fontSize: 8),
      ),
    ],
  );
}

pw.Widget _kpi(String label, String value, {bool highlight = false}) =>
    pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: highlight ? const PdfColor.fromInt(0xFFFDECEC) : _kZebra,
          border: pw.Border.all(
            color: highlight ? const PdfColor.fromInt(0xFFE57373) : _kBorder,
          ),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                color: highlight ? const PdfColor.fromInt(0xFFB3261E) : _kNavy,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(label, style: const pw.TextStyle(color: _kMuted, fontSize: 7)),
          ],
        ),
      ),
    );

pw.Widget _establishmentBand(
  String name,
  List<PersonnelRequisition> rows,
  DateTime now,
) {
  final vacantes = rows.fold<int>(0, (total, row) => total + row.quantity);
  final contratados = rows.fold<int>(
    0,
    (total, row) => total + row.hiredCount,
  );
  final pendientes = rows.fold<int>(
    0,
    (total, row) => total + row.pendingCount,
  );
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: const pw.BoxDecoration(color: _kBandBg),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            name.toUpperCase(),
            style: pw.TextStyle(
              color: _kNavy,
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          '${rows.length} requerimiento(s) · $vacantes vacante(s) · '
          '$contratados contratado(s) · $pendientes pendiente(s)',
          style: const pw.TextStyle(color: _kMuted, fontSize: 8),
        ),
      ],
    ),
  );
}

pw.Widget _requisitionTable(List<PersonnelRequisition> rows, DateTime now) {
  const headers = [
    'Cargo',
    'Solicitud',
    'Días',
    'Cant.',
    'Salario',
    'Etapa',
    'Aspirantes y avance individual',
  ];
  const widths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(2.6),
    1: pw.FlexColumnWidth(1.15),
    2: pw.FlexColumnWidth(.7),
    3: pw.FlexColumnWidth(.7),
    4: pw.FlexColumnWidth(1.35),
    5: pw.FlexColumnWidth(1.5),
    6: pw.FlexColumnWidth(5.2),
  };
  return pw.Table(
    border: pw.TableBorder.all(color: _kBorder, width: .5),
    columnWidths: widths,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kPrimary),
        children: headers
            .map(
              (header) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 5,
                ),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            )
            .toList(),
      ),
      for (var index = 0; index < rows.length; index++)
        _requisitionRow(rows[index], now, zebra: index.isOdd),
    ],
  );
}

pw.TableRow _requisitionRow(
  PersonnelRequisition row,
  DateTime now, {
  required bool zebra,
}) {
  final traffic = row.trafficAt(now);
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: zebra ? _kZebra : PdfColors.white),
    children: [
      _cell(
        row.position,
        bold: true,
        extra: row.annex ? 'Anexo' : null,
      ),
      _cell(_dayFormat.format(row.requestDate)),
      _cell('${row.daysAt(now)}', color: _trafficColor(traffic), bold: true),
      _cell('${row.hiredCount}/${row.quantity}'),
      _cell(row.salary == null ? '—' : _money.format(row.salary)),
      _cell(row.stage.label),
      _candidatesCell(row),
    ],
  );
}

/// El corazón del informe: una línea por persona.
///
/// Cuando la vacante todavía no tiene aspirantes cargados se cae al texto del
/// último avance, para no dejar la celda vacía en los procesos viejos que se
/// manejaron solo con el estado global.
pw.Widget _candidatesCell(PersonnelRequisition row) {
  if (row.candidates.isEmpty) {
    final fallback = row.processNote.trim().isEmpty
        ? 'Sin aspirantes registrados'
        : row.processNote.trim();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        fallback,
        style: const pw.TextStyle(color: _kMuted, fontSize: 7.5),
      ),
    );
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: row.candidates
          .map(
            (candidate) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: candidate.fullName,
                      style: pw.TextStyle(
                        color: _kInk,
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.TextSpan(
                      text: '  ${candidate.stage.label}',
                      style: pw.TextStyle(
                        color: _candidateColor(candidate.stage),
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (candidate.note.isNotEmpty)
                      pw.TextSpan(
                        text: '  ${candidate.note}',
                        style: const pw.TextStyle(color: _kMuted, fontSize: 7),
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}

pw.Widget _cell(
  String value, {
  bool bold = false,
  PdfColor color = _kInk,
  String? extra,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        value.isEmpty ? '—' : value,
        style: pw.TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
      if (extra != null)
        pw.Text(extra, style: const pw.TextStyle(color: _kMuted, fontSize: 7)),
    ],
  ),
);

PdfColor _trafficColor(PersonnelRequisitionTraffic traffic) =>
    switch (traffic) {
      PersonnelRequisitionTraffic.green => const PdfColor.fromInt(0xFF166534),
      PersonnelRequisitionTraffic.yellow => const PdfColor.fromInt(0xFF92400E),
      PersonnelRequisitionTraffic.red => const PdfColor.fromInt(0xFFB3261E),
      PersonnelRequisitionTraffic.closed => _kMuted,
    };

PdfColor _candidateColor(PersonnelCandidateStage stage) => switch (stage) {
  PersonnelCandidateStage.hired => const PdfColor.fromInt(0xFF166534),
  PersonnelCandidateStage.discarded => const PdfColor.fromInt(0xFF991B1B),
  PersonnelCandidateStage.documents => const PdfColor.fromInt(0xFF92400E),
  _ => _kNavy,
};

pw.Widget _runningHeader(String empresa) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 8),
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _kBorder, width: .5)),
  ),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          'Informe de procesos de selección · $empresa',
          style: pw.TextStyle(
            color: _kNavy,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    ],
  ),
);

pw.Widget _footer(pw.Context context) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: 6),
  child: pw.Text(
    'Página ${context.pageNumber} de ${context.pagesCount}',
    style: const pw.TextStyle(color: _kMuted, fontSize: 7.5),
  ),
);
