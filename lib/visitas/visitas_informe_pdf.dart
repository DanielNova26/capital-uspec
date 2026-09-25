// lib/visitas/visitas_informe_pdf.dart
//
// Los dos informes que pidió la reunión: el de UNA visita, que sale solo al
// cerrarla, y el consolidado del mes por área, que reemplaza el informe que
// hoy se arma a mano juntando actas.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
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
            '${m.distanciaMetros == null ? '' : ' · a ${m.distanciaMetros!.round()} m del establecimiento'}'
            '${m.dentroDelRadio == false ? ' · FUERA DEL RADIO' : ''}'
      : ' · sin ubicación';
  return '${_dd(t)} ${_hhmm(t)}$ubi';
}

/// Bytes de una firma: el Blob del documento primero; si no, la URL.
Future<Uint8List?> _bytesFirma(VisitaFirma? f) async {
  if (f == null) return null;
  if (f.blob != null && f.blob!.isNotEmpty) return f.blob;
  if (f.url.isEmpty) return null;
  try {
    final r = await http.get(Uri.parse(f.url));
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
  } catch (_) {}
  return null;
}

const _kAzul = PdfColor.fromInt(0xFF1F3A5F);
const _kGris = PdfColors.grey300;
const _kTxt = pw.TextStyle(fontSize: 8);
final _kTxtB = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

pw.Widget _celda(
  String t, {
  bool negrita = false,
  PdfColor? fondo,
  pw.Alignment align = pw.Alignment.centerLeft,
  double fs = 8,
}) => pw.Container(
  color: fondo,
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  alignment: align,
  child: pw.Text(
    t,
    style: pw.TextStyle(
      fontSize: fs,
      fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

/// Encabezado de cada hoja, como el del Excel: título del SG-SST a la
/// izquierda y el bloque código / versión / página / elaboración a la
/// derecha.
pw.Widget _encabezadoHoja(
  String empresaNombre,
  VisitaFormatoParte parte,
  pw.Context ctx,
) => pw.Table(
  border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
  columnWidths: {
    0: const pw.FlexColumnWidth(5),
    1: const pw.FixedColumnWidth(60),
    2: const pw.FixedColumnWidth(70),
  },
  children: [
    pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'SISTEMA DE GESTIÓN DE SEGURIDAD Y SALUD EN EL TRABAJO',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                empresaNombre.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                parte.nombre,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _kAzul,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          children: [
            _celda('CÓDIGO', negrita: true, fondo: _kGris),
            _celda('VERSIÓN', negrita: true, fondo: _kGris),
            _celda('PÁGINA', negrita: true, fondo: _kGris),
            _celda('ELABORACIÓN', negrita: true, fondo: _kGris),
          ],
        ),
        pw.Column(
          children: [
            _celda(parte.codigo),
            _celda(parte.version),
            _celda('${ctx.pageNumber} de ${ctx.pagesCount}'),
            _celda(parte.elaboracion),
          ],
        ),
      ],
    ),
  ],
);

pw.Widget _datosVisita(VisitaProfesional v) {
  pw.Widget par(String k, String val, {int flex = 1}) => pw.Expanded(
    flex: flex,
    child: pw.Row(
      children: [
        _celda(k, negrita: true, fondo: _kGris),
        pw.Expanded(child: _celda(val)),
      ],
    ),
  );
  final t = v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada;
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: .6),
    ),
    child: pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          color: _kGris,
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(
            'DATOS',
            textAlign: pw.TextAlign.center,
            style: _kTxtB,
          ),
        ),
        pw.Row(
          children: [
            par('FECHA:', _dd(t)),
            par('ESTABLECIMIENTO:', v.establecimiento, flex: 2),
            par('CIUDAD:', v.ciudad),
          ],
        ),
        pw.Row(
          children: [
            par(
              'RESPONSABLE ESTABLECIMIENTO:',
              v.responsableEstablecimiento.nombre,
              flex: 2,
            ),
            par('CARGO:', v.responsableEstablecimiento.cargo),
          ],
        ),
        pw.Row(
          children: [
            par('RESPONSABLE INSPECCIÓN:', v.profesionalNombre, flex: 2),
            par('CARGO:', v.cargoProfesional),
          ],
        ),
      ],
    ),
  );
}

/// Bloque de firmas al pie: responsable del establecimiento a la
/// izquierda, responsable de inspección a la derecha, como en el Excel.
pw.Widget _firmas(
  VisitaProfesional v,
  Uint8List? firmaEst,
  Uint8List? firmaPro,
) {
  pw.Widget bloque(
    String titulo,
    VisitaFirma? f,
    Uint8List? png,
    String nombreDef,
    String cargoDef,
  ) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: _kGris,
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(titulo, textAlign: pw.TextAlign.center, style: _kTxtB),
        ),
        pw.Container(
          height: 54,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600, width: .6),
          ),
          child: png == null
              ? pw.Text(
                  'Sin firma',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey),
                )
              : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
        ),
        pw.Row(
          children: [
            _celda('NOMBRE', negrita: true, fondo: _kGris),
            pw.Expanded(child: _celda(f?.nombre ?? nombreDef)),
          ],
        ),
        pw.Row(
          children: [
            _celda('CARGO', negrita: true, fondo: _kGris),
            pw.Expanded(child: _celda(f?.cargo ?? cargoDef)),
          ],
        ),
        if (f != null)
          pw.Text(
            [
              f.modo == kFirmaModoGuardada
                  ? 'Firma guardada del perfil'
                  : 'Dibujada en pantalla',
              if (f.at != null)
                '${_dd(f.at!.toDate().toLocal())} ${_hhmm(f.at!.toDate().toLocal())}',
              // Desde qué equipo se firmó (25 sep 2026).
              if (f.dispositivo.isNotEmpty) f.dispositivo,
            ].join(' · '),
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
          ),
      ],
    ),
  );
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      bloque(
        'RESPONSABLE DEL ESTABLECIMIENTO',
        v.firmaEstablecimiento,
        firmaEst,
        v.responsableEstablecimiento.nombre,
        v.responsableEstablecimiento.cargo,
      ),
      pw.SizedBox(width: 12),
      bloque(
        'RESPONSABLE DE INSPECCIÓN',
        v.firmaProfesional,
        firmaPro,
        v.profesionalNombre,
        v.cargoProfesional,
      ),
    ],
  );
}

String _calif(VisitaFormatoItem it, VisitaRespuesta? r) {
  final res = r?.resultado ?? '';
  if (it.tipo == kItemTipoCalificacion) {
    return switch (res) {
      kItemCumple => '1',
      kItemNoCumple => '0',
      kItemNoAplica => 'NA',
      _ => '',
    };
  }
  return switch (res) {
    kItemCumple => 'SÍ',
    kItemNoCumple => 'NO',
    _ => '',
  };
}

/// Hoja de ítems con calificación por sección y subtotal, como el
/// F-UT-SST-02 (y sirve para cualquier formato de lista).
List<pw.Widget> _hojaItems(
  VisitaProfesional v,
  VisitaFormato f,
  String parte, {
  bool criterios = true,
  bool conElementos = false,
}) {
  final items = f.itemsDeParte(parte);
  final secciones = <String, List<VisitaFormatoItem>>{};
  for (final it in items) {
    secciones.putIfAbsent(it.seccion, () => []).add(it);
  }
  final resumen = resumenDeVisita(f, v.respuestas, parte: parte);
  final filas = <pw.TableRow>[];
  for (final s in secciones.entries) {
    var sub = 0;
    var first = true;
    for (final it in s.value) {
      final r = v.respuestas[it.id];
      if (r?.resultado == kItemCumple) sub++;
      filas.add(
        pw.TableRow(
          children: [
            _celda(first ? s.key : '', negrita: true, fs: 7),
            _celda(it.texto, fs: 7),
            if (conElementos) _celda(it.unidad, fs: 7),
            _celda(_calif(it, r), align: pw.Alignment.center, negrita: true),
            if (conElementos) _celda(r?.cantidad ?? '', fs: 7),
            if (conElementos) _celda(r?.vencimiento ?? '', fs: 7),
            _celda(r?.observacion ?? '', fs: 7),
          ],
        ),
      );
      first = false;
    }
    if (!conElementos) {
      filas.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _celda(''),
            _celda('Subtotal', negrita: true, align: pw.Alignment.centerRight),
            _celda('$sub', negrita: true, align: pw.Alignment.center),
            _celda(''),
          ],
        ),
      );
    }
  }
  final maxima = resumen.total - resumen.noAplica;
  return [
    if (criterios) ...[
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
        columnWidths: {0: const pw.FixedColumnWidth(30)},
        children: [
          pw.TableRow(
            children: [
              pw.Container(
                color: _kGris,
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text('CRITERIOS DE CALIFICACIÓN', style: _kTxtB),
              ),
              pw.Container(color: _kGris),
            ],
          ),
          pw.TableRow(
            children: [
              _celda('1', negrita: true, align: pw.Alignment.center),
              _celda(
                'Cumple a toda cabalidad el estándar. No hay presencia de desvíos. Se cumple con el requisito solicitado en la inspección',
                fs: 7,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _celda('0', negrita: true, align: pw.Alignment.center),
              _celda(
                'Existen desvíos que ponen en riesgo la integridad del colaborador, las instalaciones y equipos, el servicio y el medio',
                fs: 7,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _celda('NA', negrita: true, align: pw.Alignment.center),
              _celda(
                'El parámetro de evaluación no es aplicable a este tipo de operación, área, proceso u oficio.',
                fs: 7,
              ),
            ],
          ),
        ],
      ),
    ],
    pw.SizedBox(height: 4),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
      columnWidths: conElementos
          ? {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(30),
              4: const pw.FixedColumnWidth(40),
              5: const pw.FixedColumnWidth(48),
              6: const pw.FlexColumnWidth(2),
            }
          : {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FixedColumnWidth(44),
              3: const pw.FlexColumnWidth(2),
            },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kGris),
          children: [
            _celda('ITEMS A EVALUAR', negrita: true),
            _celda(
              conElementos ? 'ELEMENTO' : 'PARÁMETROS DE EVALUACIÓN',
              negrita: true,
            ),
            if (conElementos) _celda('UNIDAD', negrita: true),
            _celda(
              conElementos ? 'CUMPLE' : 'CALIF.',
              negrita: true,
              align: pw.Alignment.center,
            ),
            if (conElementos) _celda('CANT.', negrita: true),
            if (conElementos) _celda('VENCE', negrita: true),
            _celda('OBSERVACIONES', negrita: true),
          ],
        ),
        ...filas,
      ],
    ),
    if (!conElementos) ...[
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
        children: [
          pw.TableRow(
            children: [
              _celda(
                'CALIFICACIÓN MÁXIMA: (${resumen.total} − NA)',
                negrita: true,
                fondo: _kGris,
              ),
              _celda('$maxima', align: pw.Alignment.center),
              _celda('% TOTAL:', negrita: true, fondo: _kGris),
              _celda(
                resumen.porcentaje == null ? '—' : '${resumen.porcentaje}%',
                align: pw.Alignment.center,
                negrita: true,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _celda('CALIFICACIÓN REAL:', negrita: true, fondo: _kGris),
              _celda('${resumen.cumple}', align: pw.Alignment.center),
              _celda('NO CUMPLE:', negrita: true, fondo: _kGris),
              _celda('${resumen.noCumple}', align: pw.Alignment.center),
            ],
          ),
        ],
      ),
    ],
  ];
}

/// Hoja de la tabla de extintores (F-UT-SST-03): tabla por equipo, luego
/// "Mejora y seguimiento" con los hallazgos de toda la visita.
List<pw.Widget> _hojaTabla(
  VisitaProfesional v,
  VisitaFormato f,
  VisitaFormatoTabla t,
  List<VisitaHallazgo> hallazgos,
) {
  final filas = v.filasDe(t.id);
  final ini = v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada;
  return [
    pw.SizedBox(height: 4),
    pw.Row(
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Row(
            children: [
              _celda('SITIO O LUGAR DE TRABAJO:', negrita: true, fondo: _kGris),
              pw.Expanded(child: _celda(v.establecimiento)),
            ],
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Row(
            children: [
              _celda('FECHA DE INSPECCIÓN:', negrita: true, fondo: _kGris),
              pw.Expanded(child: _celda(_dd(ini))),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 2),
    pw.Text(
      'En los ítems a verificar marcar según corresponda:   B: Bueno     M: Malo     R: Regular     NC: No cuenta con el elemento',
      style: const pw.TextStyle(fontSize: 7),
    ),
    pw.SizedBox(height: 4),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
      columnWidths: {
        0: const pw.FixedColumnWidth(16),
        for (var i = 0; i < t.camposTexto.length; i++)
          i + 1: const pw.FlexColumnWidth(1.6),
        for (var i = 0; i < t.camposEstado.length; i++)
          i + 1 + t.camposTexto.length: const pw.FlexColumnWidth(1),
        t.camposTexto.length + t.camposEstado.length + 1:
            const pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kGris),
          children: [
            _celda('No.', negrita: true, fs: 6),
            for (final c in t.camposTexto)
              _celda(c.label.toUpperCase(), negrita: true, fs: 6),
            for (final c in t.camposEstado)
              _celda(c.label, negrita: true, fs: 5.5),
            _celda('OBSERVACIONES', negrita: true, fs: 6),
          ],
        ),
        for (var i = 0; i < filas.length; i++)
          pw.TableRow(
            children: [
              _celda('${i + 1}', align: pw.Alignment.center, fs: 7),
              for (final c in t.camposTexto)
                _celda(filas[i].campos[c.id] ?? '', fs: 6.5),
              for (final c in t.camposEstado)
                _celda(
                  filas[i].estados[c.id] ?? '',
                  align: pw.Alignment.center,
                  negrita: filaEstadoEsHallazgo(filas[i].estados[c.id] ?? ''),
                  fs: 7,
                ),
              _celda(filas[i].observacion, fs: 6.5),
            ],
          ),
        if (filas.isEmpty)
          pw.TableRow(
            children: [
              _celda(''),
              for (
                var i = 0;
                i < t.camposTexto.length + t.camposEstado.length;
                i++
              )
                _celda(''),
              _celda('Sin equipos registrados', fs: 7),
            ],
          ),
      ],
    ),
    pw.SizedBox(height: 8),
    pw.Container(
      width: double.infinity,
      color: _kGris,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        'MEJORA Y SEGUIMIENTO',
        textAlign: pw.TextAlign.center,
        style: _kTxtB,
      ),
    ),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(3),
        4: const pw.FlexColumnWidth(1.6),
        5: const pw.FixedColumnWidth(50),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _celda('ITEM', negrita: true, fs: 7),
            _celda('ELEMENTO', negrita: true, fs: 7),
            _celda('NOVEDAD ENCONTRADA', negrita: true, fs: 7),
            _celda('ACCIÓN', negrita: true, fs: 7),
            _celda('RESPONSABLE', negrita: true, fs: 7),
            _celda('FECHA', negrita: true, fs: 7),
          ],
        ),
        for (var i = 0; i < hallazgos.length; i++)
          pw.TableRow(
            children: [
              _celda('${i + 1}', align: pw.Alignment.center, fs: 7),
              _celda(hallazgos[i].elemento, fs: 6.5),
              _celda(hallazgos[i].novedad, fs: 6.5),
              _celda(
                hallazgos[i].accion.isEmpty
                    ? 'Corregir y reportar al área HSE'
                    : hallazgos[i].accion,
                fs: 6.5,
              ),
              // El responsable del plan de acción si lo eligieron; si no, el
              // del establecimiento, como antes.
              _celda(
                hallazgos[i].responsableNombre.trim().isNotEmpty
                    ? '${hallazgos[i].responsableNombre}'
                          '${hallazgos[i].areaNombre.trim().isEmpty ? '' : ' (${hallazgos[i].areaNombre})'}'
                    : v.responsableEstablecimiento.nombre,
                fs: 6.5,
              ),
              _celda(
                _dd(fechaLimiteHallazgo(v.fin?.at.toDate() ?? ini)),
                fs: 6.5,
              ),
            ],
          ),
        if (hallazgos.isEmpty)
          pw.TableRow(
            children: [
              _celda(''),
              _celda('Sin hallazgos', fs: 7),
              _celda(''),
              _celda(''),
              _celda(''),
              _celda(''),
            ],
          ),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Text(
      'NOTA: Si se presentan condiciones CRÍTICAS de seguridad que generen un inminente riesgo de incidente, debe comunicar la situación al jefe del área para tomar acciones inmediatas.',
      style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
    ),
  ];
}

/// Enlaces a las fotos de toda la visita. Como enlaces, no incrustadas:
/// con fotos adentro el PDF pesaría decenas de MB.
List<pw.Widget> _evidencias(VisitaProfesional v, VisitaFormato f) {
  final bloques = <pw.Widget>[];
  void bloque(String titulo, List<VisitaEvidencia> evs) {
    if (evs.isEmpty) return;
    bloques.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            ),
            for (final e in evs)
              pw.UrlLink(
                destination: e.url,
                child: pw.Text(
                  e.nombre,
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.blue700,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  for (final it in f.itemsOrdenados) {
    bloque(
      'Evidencias ítem ${it.orden}',
      v.respuestas[it.id]?.evidencias ?? const [],
    );
  }
  for (final t in f.tablas) {
    final filas = v.filasDe(t.id);
    for (var i = 0; i < filas.length; i++) {
      bloque('Evidencias ${t.etiquetaFila} ${i + 1}', filas[i].evidencias);
    }
  }
  if (bloques.isEmpty) return const [];
  return [
    pw.SizedBox(height: 8),
    pw.Text(
      'Evidencias fotográficas (enlaces)',
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
    ),
    ...bloques,
  ];
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

/// Informe de una visita cerrada.
///
/// Si el formato tiene partes (el SST), sale una hoja por parte replicando
/// el Excel: encabezado con código/versión, datos, ítems con subtotales y
/// % total, tabla de extintores con "Mejora y seguimiento", botiquín con
/// cantidad y vencimiento, y las firmas al pie de cada hoja. Si no tiene
/// partes (los borradores de otras áreas), sale el informe sencillo de
/// siempre. Evidencias como enlaces: incrustar fotos haría PDFs de decenas
/// de MB que nadie va a mandar por WhatsApp.
Future<Uint8List> generarInformeVisita({
  required VisitaProfesional v,
  required VisitaFormato formato,
  required String empresaNombre,
}) async {
  final firmaEst = await _bytesFirma(v.firmaEstablecimiento);
  final firmaPro = await _bytesFirma(v.firmaProfesional);
  if (formato.partes.isNotEmpty) {
    return _informeConPartes(
      v: v,
      formato: formato,
      empresaNombre: empresaNombre,
      firmaEst: firmaEst,
      firmaPro: firmaPro,
    );
  }
  final resumen = resumenDeVisita(formato, v.respuestas);
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        if (v.esPrueba) _titulo('PRUEBA · SIN VALIDEZ OPERATIVA'),
        _titulo('Informe de visita · ${v.areaNombre}'),
        pw.Text(empresaNombre, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        _fila('Establecimiento', v.establecimiento),
        _fila('Formato', '${formato.nombre} (v${formato.version})'),
        _fila('Profesional', v.profesionalNombre),
        _fila('Programada por', v.asignadoPorNombre),
        _fila('Fecha programada', _dd(v.fechaProgramada)),
        if (v.responsableEstablecimiento.completo)
          _fila(
            'Responsable sitio',
            '${v.responsableEstablecimiento.nombre}'
                '${v.responsableEstablecimiento.cargo.isEmpty ? '' : ' · ${v.responsableEstablecimiento.cargo}'}',
          ),
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
        ..._evidencias(v, formato),
        pw.SizedBox(height: 16),
        _firmas(v, firmaEst, firmaPro),
        pw.SizedBox(height: 8),
        pw.Text(
          v.esPrueba
              ? 'Prueba: se registró la hora sin comprobar ubicación.'
              : 'Ubicación y hora registradas por el dispositivo al iniciar y cerrar la visita.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

Future<Uint8List> _informeConPartes({
  required VisitaProfesional v,
  required VisitaFormato formato,
  required String empresaNombre,
  required Uint8List? firmaEst,
  required Uint8List? firmaPro,
}) async {
  final doc = pw.Document();
  final hallazgos = hallazgosDeVisita(formato, v.respuestas, tablas: v.tablas);
  final pie = pw.Text(
    'Inicio: ${_marca(v.inicio)}   ·   Cierre: ${_marca(v.fin)}   ·   ${v.esPrueba ? 'PRUEBA · SIN VALIDEZ OPERATIVA · ubicación no comprobada.' : 'Ubicación y hora registradas por el dispositivo.'}',
    style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
  );
  for (var i = 0; i < formato.partes.length; i++) {
    final parte = formato.partes[i];
    final tablas = formato.tablasDeParte(parte.codigo);
    final items = formato.itemsDeParte(parte.codigo);
    final esTabla = tablas.isNotEmpty && items.isEmpty;
    final tieneElementos = items.any((it) => it.esElemento);
    final ultima = i == formato.partes.length - 1;
    doc.addPage(
      pw.MultiPage(
        pageFormat: esTabla
            ? PdfPageFormat.letter.landscape
            : PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: _encabezadoHoja(empresaNombre, parte, ctx),
        ),
        footer: (_) => pie,
        build: (ctx) => [
          if (v.esPrueba) _titulo('PRUEBA · SIN VALIDEZ OPERATIVA'),
          if (!esTabla) _datosVisita(v),
          if (!esTabla)
            ..._hojaItems(
              v,
              formato,
              parte.codigo,
              criterios: !tieneElementos,
              conElementos: tieneElementos,
            ),
          for (final t in tablas) ..._hojaTabla(v, formato, t, hallazgos),
          if (tieneElementos || esTabla) ...[
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                _celda(
                  'OBSERVACIONES GENERALES:',
                  negrita: true,
                  fondo: _kGris,
                ),
                pw.Expanded(
                  child: pw.Container(
                    constraints: const pw.BoxConstraints(minHeight: 24),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey600,
                        width: .6,
                      ),
                    ),
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(v.observacionGeneral, style: _kTxt),
                  ),
                ),
              ],
            ),
          ],
          if (ultima) ..._evidencias(v, formato),
          pw.SizedBox(height: 10),
          _firmas(v, firmaEst, firmaPro),
        ],
      ),
    );
  }
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
  final terminadas =
      visitas.where((v) => !v.esPrueba && v.estado == kVisitaTerminada).toList()
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
          headers: [
            'Fecha',
            'Establecimiento',
            'Profesional',
            '%',
            'Hallazgos',
            'Inicio',
            'En sitio',
            'Firmas',
          ],
          data: [
            for (final v in terminadas)
              [
                _dd(v.fechaProgramada),
                v.establecimiento,
                v.profesionalNombre,
                v.cumplimiento == null ? '—' : '${v.cumplimiento}',
                '${hallazgosDe(v)}',
                v.inicio == null ? '—' : _hhmm(v.inicio!.at.toDate().toLocal()),
                v.inicio?.distanciaMetros == null
                    ? '—'
                    : '${v.inicio!.distanciaMetros!.round()} m',
                v.firmada ? 'Sí' : 'No',
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
