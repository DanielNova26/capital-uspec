// lib/talento_humano/personnel_recruitment_summary_pdf.dart
//
// Informe de AVANCE del reclutamiento, para entregar a gerencia.
//
// Va aparte del informe de procesos de selección (personnel_requisition_pdf)
// a propósito: aquel lista una línea por aspirante porque la interventoría
// necesita ver quién está en entrevistas y quién en exámenes. Gerencia no
// necesita nombres; necesita saber cuánto falta, dónde está trancado y desde
// cuándo. Meter las dos cosas en un solo documento haría que ninguna de las
// dos se lea.
//
// Por eso aquí no aparece ningún dato personal: ni nombres de aspirantes ni
// documentos. Un informe que circula por correo no tiene por qué llevarlos.

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'personnel_requisition_models.dart';

const PdfColor _kNavy = PdfColor.fromInt(0xFF1E3A8A);
const PdfColor _kBrown = PdfColor.fromInt(0xFFC28942);
const PdfColor _kInk = PdfColor.fromInt(0xFF1E293B);
const PdfColor _kMuted = PdfColor.fromInt(0xFF64748B);
const PdfColor _kLine = PdfColor.fromInt(0xFFE2E8F0);
const PdfColor _kBand = PdfColor.fromInt(0xFFF1F5F9);
const PdfColor _kAlert = PdfColor.fromInt(0xFFB45309);

/// Avance de un establecimiento: lo pedido, lo cubierto y lo que falta.
class AvanceEstablecimiento {
  final String establecimiento;
  final int solicitadas;
  final int contratadas;
  final int vacantesAbiertas;
  final int procesosAbiertos;

  /// Días del proceso abierto más antiguo. Es el dato que dispara la
  /// conversación: un promedio bonito puede esconder una vacante de 90 días.
  final int diasMasAntiguo;

  const AvanceEstablecimiento({
    required this.establecimiento,
    required this.solicitadas,
    required this.contratadas,
    required this.vacantesAbiertas,
    required this.procesosAbiertos,
    required this.diasMasAntiguo,
  });

  double get cobertura => solicitadas == 0 ? 0 : contratadas / solicitadas;
}

/// Resumen completo, calculado aparte del PDF para poder probarlo.
class AvanceReclutamiento {
  final int procesos;
  final int procesosAbiertos;
  final int procesosCancelados;
  final int solicitadas;
  final int contratadas;
  final int vacantesAbiertas;

  /// Cuántas vacantes abiertas hay en cada etapa del proceso.
  final Map<PersonnelRequisitionStage, int> vacantesPorEtapa;

  final List<AvanceEstablecimiento> porEstablecimiento;
  final int diasPromedioAbiertos;
  final int diasMasAntiguo;

  const AvanceReclutamiento({
    required this.procesos,
    required this.procesosAbiertos,
    required this.procesosCancelados,
    required this.solicitadas,
    required this.contratadas,
    required this.vacantesAbiertas,
    required this.vacantesPorEtapa,
    required this.porEstablecimiento,
    required this.diasPromedioAbiertos,
    required this.diasMasAntiguo,
  });

  double get cobertura => solicitadas == 0 ? 0 : contratadas / solicitadas;
}

/// Calcula el avance a partir de las solicitudes.
///
/// Las canceladas se cuentan aparte y NO entran en lo solicitado: sumarlas
/// hundiría la cobertura por vacantes que nadie espera que se llenen.
AvanceReclutamiento calcularAvanceReclutamiento(
  List<PersonnelRequisition> rows, {
  DateTime? hoy,
}) {
  final ahora = hoy ?? DateTime.now();
  final vigentes = rows
      .where((r) => r.stage != PersonnelRequisitionStage.cancelled)
      .toList();

  var solicitadas = 0;
  var contratadas = 0;
  var abiertos = 0;
  final porEtapa = <PersonnelRequisitionStage, int>{};
  final diasAbiertos = <int>[];
  final grupos = <String, List<PersonnelRequisition>>{};

  for (final row in vigentes) {
    solicitadas += row.quantity;
    contratadas += row.hiredCount;
    final clave = row.establishment.trim().isEmpty
        ? 'Sin establecimiento'
        : row.establishment.trim();
    grupos.putIfAbsent(clave, () => []).add(row);

    if (row.isClosed) continue;
    abiertos++;
    porEtapa[row.stage] = (porEtapa[row.stage] ?? 0) + row.pendingCount;
    diasAbiertos.add(_diasDesde(row.requestDate, ahora));
  }

  final establecimientos = <AvanceEstablecimiento>[];
  for (final entrada in grupos.entries) {
    var pedidas = 0;
    var cubiertas = 0;
    var procesosAbiertos = 0;
    var masAntiguo = 0;
    for (final row in entrada.value) {
      pedidas += row.quantity;
      cubiertas += row.hiredCount;
      if (row.isClosed) continue;
      procesosAbiertos++;
      final dias = _diasDesde(row.requestDate, ahora);
      if (dias > masAntiguo) masAntiguo = dias;
    }
    establecimientos.add(
      AvanceEstablecimiento(
        establecimiento: entrada.key,
        solicitadas: pedidas,
        contratadas: cubiertas,
        vacantesAbiertas: (pedidas - cubiertas).clamp(0, pedidas),
        procesosAbiertos: procesosAbiertos,
        diasMasAntiguo: masAntiguo,
      ),
    );
  }

  // Primero lo que más falta: es el orden en que gerencia quiere leerlo.
  establecimientos.sort((a, b) {
    final porFaltante = b.vacantesAbiertas.compareTo(a.vacantesAbiertas);
    if (porFaltante != 0) return porFaltante;
    return a.establecimiento.toLowerCase().compareTo(
      b.establecimiento.toLowerCase(),
    );
  });

  return AvanceReclutamiento(
    procesos: rows.length,
    procesosAbiertos: abiertos,
    procesosCancelados: rows.length - vigentes.length,
    solicitadas: solicitadas,
    contratadas: contratadas,
    vacantesAbiertas: (solicitadas - contratadas).clamp(0, solicitadas),
    vacantesPorEtapa: Map.unmodifiable(porEtapa),
    porEstablecimiento: List.unmodifiable(establecimientos),
    diasPromedioAbiertos: diasAbiertos.isEmpty
        ? 0
        : (diasAbiertos.reduce((a, b) => a + b) / diasAbiertos.length).round(),
    diasMasAntiguo: diasAbiertos.isEmpty
        ? 0
        : diasAbiertos.reduce((a, b) => a > b ? a : b),
  );
}

int _diasDesde(DateTime desde, DateTime hasta) {
  final a = DateTime(desde.year, desde.month, desde.day);
  final b = DateTime(hasta.year, hasta.month, hasta.day);
  final dias = b.difference(a).inDays;
  return dias < 0 ? 0 : dias;
}

/// Etapas en el orden del proceso, para leer el embudo de arriba abajo.
const List<PersonnelRequisitionStage> _etapasDelProceso = [
  PersonnelRequisitionStage.requested,
  PersonnelRequisitionStage.recruitment,
  PersonnelRequisitionStage.preselection,
  PersonnelRequisitionStage.interview,
  PersonnelRequisitionStage.exams,
  PersonnelRequisitionStage.documents,
];

Future<Uint8List> buildRecruitmentSummaryPdf({
  required List<PersonnelRequisition> rows,
  required String empresaId,
  String empresaNombre = '',
  DateTime? generatedAt,
}) async {
  final ahora = generatedAt ?? DateTime.now();
  final empresa = empresaNombre.trim().isEmpty
      ? empresaId
      : empresaNombre.trim();
  final avance = calcularAvanceReclutamiento(rows, hoy: ahora);
  final fecha = DateFormat('dd/MM/yyyy').format(ahora);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.copyWith(
        marginTop: 28,
        marginBottom: 28,
        marginLeft: 30,
        marginRight: 30,
      ),
      header: (context) =>
          context.pageNumber == 1 ? pw.SizedBox() : _encabezado(empresa),
      footer: (context) => _pie(context, fecha),
      build: (context) => [
        _portada(empresa, fecha, avance),
        pw.SizedBox(height: 18),
        _embudo(avance),
        pw.SizedBox(height: 18),
        _tablaEstablecimientos(avance),
        pw.SizedBox(height: 16),
        _notaMetodologica(avance),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _portada(String empresa, String fecha, AvanceReclutamiento a) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          empresa.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 10,
            color: _kMuted,
            letterSpacing: 1.2,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Avance de reclutamiento',
          style: pw.TextStyle(
            fontSize: 22,
            color: _kNavy,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Corte al $fecha',
          style: const pw.TextStyle(fontSize: 10, color: _kMuted),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            _tarjeta('Vacantes solicitadas', '${a.solicitadas}'),
            pw.SizedBox(width: 8),
            _tarjeta('Cubiertas', '${a.contratadas}'),
            pw.SizedBox(width: 8),
            _tarjeta(
              'Por cubrir',
              '${a.vacantesAbiertas}',
              resaltado: a.vacantesAbiertas > 0,
            ),
            pw.SizedBox(width: 8),
            _tarjeta(
              'Cobertura',
              '${(a.cobertura * 100).round()}%',
              resaltado: a.cobertura < 0.8,
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _tarjeta('Procesos abiertos', '${a.procesosAbiertos}'),
            pw.SizedBox(width: 8),
            _tarjeta('Días promedio abierto', '${a.diasPromedioAbiertos}'),
            pw.SizedBox(width: 8),
            _tarjeta(
              'El más antiguo',
              '${a.diasMasAntiguo} días',
              resaltado: a.diasMasAntiguo >= 30,
            ),
            pw.SizedBox(width: 8),
            _tarjeta('Cancelados', '${a.procesosCancelados}'),
          ],
        ),
      ],
    );

pw.Widget _tarjeta(String etiqueta, String valor, {bool resaltado = false}) =>
    pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: pw.BoxDecoration(
          color: resaltado ? PdfColor.fromInt(0xFFFEF3C7) : _kBand,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: resaltado ? _kAlert : _kLine),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              etiqueta,
              style: const pw.TextStyle(fontSize: 7.5, color: _kMuted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: resaltado ? _kAlert : _kNavy,
              ),
            ),
          ],
        ),
      ),
    );

/// Dónde están hoy las vacantes que faltan por cubrir.
pw.Widget _embudo(AvanceReclutamiento a) {
  final maximo = _etapasDelProceso
      .map((e) => a.vacantesPorEtapa[e] ?? 0)
      .fold<int>(0, (max, v) => v > max ? v : max);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _titulo('En qué etapa están las vacantes por cubrir'),
      pw.SizedBox(height: 8),
      if (maximo == 0)
        pw.Text(
          'No hay vacantes pendientes.',
          style: const pw.TextStyle(fontSize: 10, color: _kMuted),
        )
      else
        for (final etapa in _etapasDelProceso)
          _barra(
            etapa.label,
            a.vacantesPorEtapa[etapa] ?? 0,
            maximo,
            a.vacantesAbiertas,
          ),
    ],
  );
}

pw.Widget _barra(String etiqueta, int valor, int maximo, int total) {
  final proporcion = maximo == 0 ? 0.0 : valor / maximo;
  final llena = (proporcion * 1000).round().clamp(0, 1000);
  final vacia = 1000 - llena;
  final porcentaje = total == 0 ? 0 : (valor * 100 / total).round();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 92,
          child: pw.Text(
            etiqueta,
            style: const pw.TextStyle(fontSize: 8.5, color: _kInk),
          ),
        ),
        // La barra se arma con dos partes proporcionales en vez de un ancho
        // fraccionado: el paquete `pdf` no tiene FractionallySizedBox.
        pw.Expanded(
          child: pw.Container(
            height: 13,
            decoration: pw.BoxDecoration(
              color: _kBand,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Row(
              children: [
                if (llena > 0)
                  pw.Expanded(
                    flex: llena,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: _kBrown,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                    ),
                  ),
                if (vacia > 0) pw.Expanded(flex: vacia, child: pw.SizedBox()),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            valor == 0 ? '—' : '$valor  ($porcentaje%)',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: valor == 0 ? _kMuted : _kInk,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _tablaEstablecimientos(AvanceReclutamiento a) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    _titulo('Avance por establecimiento'),
    pw.SizedBox(height: 6),
    pw.Text(
      'Ordenado por lo que falta, no alfabéticamente.',
      style: const pw.TextStyle(fontSize: 8, color: _kMuted),
    ),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: _kLine)),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kBand),
          children: [
            _celda('Establecimiento', encabezado: true),
            _celda('Pedidas', encabezado: true, derecha: true),
            _celda('Cubiertas', encabezado: true, derecha: true),
            _celda('Faltan', encabezado: true, derecha: true),
            _celda('Cobertura', encabezado: true, derecha: true),
            _celda('Más antiguo', encabezado: true, derecha: true),
          ],
        ),
        for (final e in a.porEstablecimiento)
          pw.TableRow(
            children: [
              _celda(e.establecimiento),
              _celda('${e.solicitadas}', derecha: true),
              _celda('${e.contratadas}', derecha: true),
              _celda(
                '${e.vacantesAbiertas}',
                derecha: true,
                alerta: e.vacantesAbiertas > 0,
              ),
              _celda('${(e.cobertura * 100).round()}%', derecha: true),
              _celda(
                e.procesosAbiertos == 0 ? '—' : '${e.diasMasAntiguo} d',
                derecha: true,
                alerta: e.diasMasAntiguo >= 30,
              ),
            ],
          ),
      ],
    ),
  ],
);

pw.Widget _notaMetodologica(AvanceReclutamiento a) => pw.Container(
  padding: const pw.EdgeInsets.all(9),
  decoration: pw.BoxDecoration(
    color: _kBand,
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Cómo leer este informe',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _kInk,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Las vacantes canceladas no se cuentan como solicitadas: sumarlas '
        'bajaría la cobertura por puestos que nadie espera que se llenen. '
        'En este corte hay ${a.procesosCancelados}.',
        style: const pw.TextStyle(fontSize: 8, color: _kMuted),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'Los días se cuentan desde la fecha de solicitud hasta hoy, solo para '
        'los procesos que siguen abiertos. Se muestra el más antiguo además '
        'del promedio, porque un promedio razonable puede esconder una '
        'vacante trancada.',
        style: const pw.TextStyle(fontSize: 8, color: _kMuted),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'Este informe no incluye nombres ni documentos de aspirantes. El '
        'detalle por persona está en el informe de procesos de selección.',
        style: const pw.TextStyle(fontSize: 8, color: _kMuted),
      ),
    ],
  ),
);

pw.Widget _titulo(String texto) => pw.Text(
  texto,
  style: pw.TextStyle(
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
    color: _kNavy,
  ),
);

pw.Widget _celda(
  String texto, {
  bool encabezado = false,
  bool derecha = false,
  bool alerta = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  child: pw.Text(
    texto,
    textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: encabezado ? 8 : 8.5,
      fontWeight: encabezado || alerta
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
      color: alerta ? _kAlert : _kInk,
    ),
  ),
);

pw.Widget _encabezado(String empresa) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 10),
  padding: const pw.EdgeInsets.only(bottom: 5),
  decoration: pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _kLine)),
  ),
  child: pw.Text(
    '$empresa · Avance de reclutamiento',
    style: const pw.TextStyle(fontSize: 8, color: _kMuted),
  ),
);

pw.Widget _pie(pw.Context context, String fecha) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Generado el $fecha',
        style: const pw.TextStyle(fontSize: 7.5, color: _kMuted),
      ),
      pw.Text(
        '${context.pageNumber} / ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 7.5, color: _kMuted),
      ),
    ],
  ),
);
