// lib/visitas/visitas_informe_pdf.dart
//
// Los informes de Visitas: el de UNA visita, que sale al cerrarla, y el
// consolidado de un periodo, que reemplaza el informe que hoy se arma a mano
// juntando actas.
//
// 26 sep 2026, lo que pidió la dirección:
//  - Todos los informes con el encabezado del formato SST: logo, sistema de
//    gestión, nombre del formato y el bloque código / versión / página /
//    elaboración. Antes solo el SST lo traía; los demás salían con un título
//    suelto.
//  - "Profesional" donde decía "Responsable de inspección".
//  - Observaciones generales resaltadas, no una línea gris perdida.
//  - Firma, nombre y cargo con aire: el bloque de antes se veía apeñuscado.
//  - Las fotos como ANEXOS del informe (registro fotográfico), ya con su
//    marca de agua, no como enlaces.
//  - Consolidado por fechas, combinando áreas con un color por área para
//    saber cuál es cuál, y si se quiere con las actas completas detrás.
//
// Las fuentes estándar del PDF solo tienen Latin-1: todo texto pasa por
// `_s`, que cambia comillas tipográficas, guiones largos y demás por su
// equivalente, para que no salgan huecos.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'visitas_models.dart';

/// Cómo se consiguen los bytes de una foto (Storage con el SDK, que en web
/// no pelea con CORS). Si no se pasa, se descarga por la URL.
typedef CargadorImagen = Future<Uint8List?> Function(VisitaEvidencia e);

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Solo Latin-1: las fuentes estándar del PDF no tienen más.
String _s(String t) {
  final b = StringBuffer();
  for (final r in t.runes) {
    if (r <= 0xFF) {
      b.writeCharCode(r);
      continue;
    }
    b.write(switch (r) {
      0x2018 || 0x2019 || 0x201A || 0x2032 => "'",
      0x201C || 0x201D || 0x201E || 0x2033 => '"',
      0x2013 || 0x2014 || 0x2212 => '-',
      0x2026 => '...',
      0x2022 || 0x2219 => '·',
      0x2192 => '->',
      0x2264 => '<=',
      0x2265 => '>=',
      0x2713 || 0x2714 => 'OK',
      _ => '',
    });
  }
  return b.toString();
}

String _marca(VisitaMarca? m) {
  if (m == null) return '-';
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
  return _descargar(f.url);
}

Future<Uint8List?> _descargar(String url) async {
  if (url.isEmpty) return null;
  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
  } catch (_) {}
  return null;
}

/// Una foto de más de ~450 KB se reduce a 1100 px: con 30 anexos a tamaño
/// original el PDF pasaba de 15 MB y no salía por WhatsApp.
Uint8List _reducir(Uint8List bytes) {
  if (bytes.length <= 450 * 1024) return bytes;
  try {
    final im = img.decodeImage(bytes);
    if (im == null) return bytes;
    final lado = im.width > im.height ? im.width : im.height;
    final r = lado <= 1100
        ? im
        : img.copyResize(
            im,
            width: im.width >= im.height ? 1100 : null,
            height: im.height > im.width ? 1100 : null,
          );
    return Uint8List.fromList(img.encodeJpg(r, quality: 72));
  } catch (_) {
    return bytes;
  }
}

const _kAzul = PdfColor.fromInt(0xFF1F3A5F);
const _kMorado = PdfColor.fromInt(0xFF7C3AED);
const _kGris = PdfColors.grey300;
const _kBorde = PdfColors.grey600;
final _kTxtB = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

pw.Widget _celda(
  String t, {
  bool negrita = false,
  PdfColor? fondo,
  PdfColor? color,
  pw.Alignment align = pw.Alignment.centerLeft,
  double fs = 8,
}) => pw.Container(
  color: fondo,
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  alignment: align,
  child: pw.Text(
    _s(t),
    style: pw.TextStyle(
      fontSize: fs,
      color: color,
      fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

// ── Encabezado común (el del SST) ───────────────────────────────────────────

/// Encabezado de cada hoja, como el del Excel de SST: logo a la izquierda,
/// sistema de gestión, empresa y nombre del formato al centro, y el bloque
/// código / versión / página / elaboración a la derecha. [acento] pinta una
/// franja arriba (el color del área en el consolidado combinado) y
/// [etiqueta] la rotula ("ACTA 3 DE 12 · CALIDAD").
pw.Widget _encabezadoHoja({
  required String empresaNombre,
  required String sistema,
  required VisitaFormatoParte parte,
  required pw.Context ctx,
  Uint8List? logo,
  PdfColor? acento,
  String etiqueta = '',
}) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    if (acento != null)
      pw.Container(
        color: acento,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(
          _s(etiqueta),
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    pw.Table(
      border: pw.TableBorder.all(color: _kBorde, width: .6),
      columnWidths: {
        0: const pw.FixedColumnWidth(78),
        1: const pw.FlexColumnWidth(5),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FixedColumnWidth(74),
      },
      children: [
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.Container(
              height: 58,
              padding: const pw.EdgeInsets.all(5),
              alignment: pw.Alignment.center,
              child: logo == null
                  ? pw.Text(
                      _s(empresaNombre.toUpperCase()),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    )
                  : pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    _s(sistema),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _s(empresaNombre.toUpperCase()),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    _s(parte.nombre),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: acento ?? _kAzul,
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
                _celda(parte.codigo.isEmpty ? '-' : parte.codigo),
                _celda(parte.version.isEmpty ? '1' : parte.version),
                _celda('${ctx.pageNumber} de ${ctx.pagesCount}'),
                _celda(parte.elaboracion.isEmpty ? '-' : parte.elaboracion),
              ],
            ),
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
  final fin = v.fin?.at.toDate().toLocal();
  final dist = v.inicio?.distanciaMetros;
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _kBorde, width: .6),
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
              'RESPONSABLE DEL ESTABLECIMIENTO:',
              v.responsableEstablecimiento.nombre,
              flex: 2,
            ),
            par('CARGO:', v.responsableEstablecimiento.cargo),
          ],
        ),
        pw.Row(
          children: [
            par('PROFESIONAL:', v.profesionalNombre, flex: 2),
            par('CARGO:', v.cargoProfesional),
          ],
        ),
        pw.Row(
          children: [
            par('INICIO:', v.inicio == null ? '-' : _hhmm(t)),
            par('CIERRE:', fin == null ? '-' : _hhmm(fin)),
            par(
              'EN EL SITIO:',
              v.esPrueba
                  ? 'Prueba (sin GPS)'
                  : dist == null
                  ? '-'
                  : 'A ${dist.round()} m'
                        '${v.inicio?.dentroDelRadio == false ? ' (fuera del radio)' : ''}',
              flex: 2,
            ),
          ],
        ),
      ],
    ),
  );
}

// ── Firmas ──────────────────────────────────────────────────────────────────

/// Firmas al pie: responsable del establecimiento a la izquierda y el
/// profesional a la derecha, como en el Excel, pero con espacio para la
/// firma, una línea debajo y el nombre y el cargo centrados (el bloque de
/// antes, con NOMBRE y CARGO en celdas grises, se veía apeñuscado).
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
  ) {
    final nombre = (f?.nombre ?? '').trim().isNotEmpty ? f!.nombre : nombreDef;
    final cargo = (f?.cargo ?? '').trim().isNotEmpty ? f!.cargo : cargoDef;
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: .6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              _s(titulo),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
                letterSpacing: .5,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              height: 64,
              alignment: pw.Alignment.bottomCenter,
              child: png == null
                  ? pw.Text(
                      'Sin firma',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey,
                      ),
                    )
                  : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 16),
              height: .8,
              color: PdfColors.grey800,
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              _s(nombre.isEmpty ? '-' : nombre.toUpperCase()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              _s(cargo.isEmpty ? 'Cargo no registrado' : cargo),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            if (f != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                _s(
                  [
                    f.modo == kFirmaModoGuardada
                        ? 'Firma guardada del perfil'
                        : 'Firmada en pantalla',
                    if (f.at != null)
                      '${_dd(f.at!.toDate().toLocal())} ${_hhmm(f.at!.toDate().toLocal())}',
                    if (f.dispositivo.isNotEmpty) f.dispositivo,
                  ].join(' · '),
                ),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        bloque(
          'RESPONSABLE DEL ESTABLECIMIENTO',
          v.firmaEstablecimiento,
          firmaEst,
          v.responsableEstablecimiento.nombre,
          v.responsableEstablecimiento.cargo,
        ),
        pw.SizedBox(width: 24),
        bloque(
          'PROFESIONAL QUE REALIZA LA VISITA',
          v.firmaProfesional,
          firmaPro,
          v.profesionalNombre,
          v.cargoProfesional,
        ),
      ],
    ),
  );
}

// ── Observaciones generales ─────────────────────────────────────────────────

/// Resaltadas: fondo ámbar, franja a la izquierda y letra más grande. Es lo
/// primero que lee el director después del porcentaje.
pw.Widget _observacionesGenerales(VisitaProfesional v) {
  final texto = v.observacionGeneral.trim();
  final bloque = _bloqueObservaciones(texto);
  // Una fila de tabla no se parte entre páginas: así el título no queda al
  // pie de una hoja y el texto en la siguiente. Un texto de más de una
  // página sí se deja partir (no cabría en una fila).
  if (texto.length > 1800) return bloque;
  return pw.Table(
    children: [
      pw.TableRow(children: [bloque]),
    ],
  );
}

pw.Widget _bloqueObservaciones(String texto) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    decoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFFEF3C7),
      border: pw.Border(
        left: pw.BorderSide(color: PdfColor.fromInt(0xFFF59E0B), width: 4),
        top: pw.BorderSide(color: PdfColor.fromInt(0xFFFCD34D), width: .6),
        right: pw.BorderSide(color: PdfColor.fromInt(0xFFFCD34D), width: .6),
        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFFCD34D), width: .6),
      ),
    ),
    padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'OBSERVACIONES GENERALES',
          style: pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF92400E),
            letterSpacing: .6,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _s(texto.isEmpty ? 'Sin observaciones generales.' : texto),
          style: pw.TextStyle(
            fontSize: 10,
            lineSpacing: 1.5,
            color: texto.isEmpty ? PdfColors.grey700 : PdfColors.black,
            fontStyle: texto.isEmpty
                ? pw.FontStyle.italic
                : pw.FontStyle.normal,
          ),
        ),
      ],
    ),
  );
}

// ── Contenido de una hoja ───────────────────────────────────────────────────

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

/// Las preguntas de formulario (texto, número, fecha, opción) de una hoja:
/// "INFORMACIÓN REGISTRADA", dos columnas.
List<pw.Widget> _informacionRegistrada(
  VisitaProfesional v,
  List<VisitaFormatoItem> items,
) {
  final datos = [
    for (final it in items)
      if (!it.califica) it,
  ];
  if (datos.isEmpty) return const [];
  return [
    pw.SizedBox(height: 6),
    pw.Table(
      border: pw.TableBorder.all(color: _kBorde, width: .6),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kGris),
          children: [
            _celda('INFORMACIÓN REGISTRADA', negrita: true),
            _celda('RESPUESTA', negrita: true),
          ],
        ),
        for (final it in datos)
          pw.TableRow(
            children: [
              _celda(
                it.seccion.isEmpty ? it.texto : '${it.seccion} · ${it.texto}',
                fs: 7.5,
              ),
              _celda(
                (v.respuestas[it.id]?.valor ?? '').trim().isEmpty
                    ? '-'
                    : v.respuestas[it.id]!.valor,
                fs: 7.5,
                negrita: true,
              ),
            ],
          ),
      ],
    ),
  ];
}

/// Hoja de ítems con calificación por sección y subtotal, como el
/// F-UT-SST-02 (y sirve para cualquier formato de lista).
List<pw.Widget> _hojaItems(
  VisitaProfesional v,
  VisitaFormato f,
  String parte, {
  bool conElementos = false,
}) {
  final items = [
    for (final it in f.itemsDeParte(parte))
      if (it.califica) it,
  ];
  if (items.isEmpty) return const [];
  final criterios =
      !conElementos && items.any((it) => it.tipo == kItemTipoCalificacion);
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
      final malo = r?.resultado == kItemNoCumple;
      filas.add(
        pw.TableRow(
          decoration: malo
              ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF2F2))
              : null,
          children: [
            _celda(first ? s.key : '', negrita: true, fs: 7),
            _celda(it.texto, fs: 7),
            if (conElementos) _celda(it.unidad, fs: 7),
            _celda(
              _calif(it, r),
              align: pw.Alignment.center,
              negrita: true,
              color: malo ? PdfColors.red800 : null,
            ),
            if (conElementos) _celda(r?.cantidad ?? '', fs: 7),
            if (conElementos) _celda(r?.vencimiento ?? '', fs: 7),
            _celda(
              [
                r?.observacion ?? '',
                if ((r?.evidencias.length ?? 0) > 0)
                  '(${r!.evidencias.length} foto${r.evidencias.length == 1 ? '' : 's'} en anexos)',
              ].where((t) => t.trim().isNotEmpty).join(' '),
              fs: 7,
            ),
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
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: _kGris,
          border: pw.Border.all(color: _kBorde, width: .6),
        ),
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text('CRITERIOS DE CALIFICACIÓN', style: _kTxtB),
      ),
      pw.Table(
        border: pw.TableBorder.all(color: _kBorde, width: .6),
        columnWidths: {0: const pw.FixedColumnWidth(30)},
        children: [
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
      border: pw.TableBorder.all(color: _kBorde, width: .6),
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
          repeat: true,
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
        border: pw.TableBorder.all(color: _kBorde, width: .6),
        children: [
          pw.TableRow(
            children: [
              _celda(
                'CALIFICACIÓN MÁXIMA: (${resumen.total} - NA)',
                negrita: true,
                fondo: _kGris,
              ),
              _celda('$maxima', align: pw.Alignment.center),
              _celda('% TOTAL:', negrita: true, fondo: _kGris),
              _celda(
                resumen.porcentaje == null ? '-' : '${resumen.porcentaje}%',
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

/// Una tabla del formato (extintores, áreas…): una fila por equipo o por
/// fila fija, con su escala.
List<pw.Widget> _hojaTabla(VisitaProfesional v, VisitaFormatoTabla t) {
  final filas = filasParaTabla(t, v.filasDe(t.id));
  final ini = v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada;
  final primera = t.conFilasFijas ? t.etiquetaFila.toUpperCase() : 'No.';
  return [
    pw.SizedBox(height: 8),
    pw.Container(
      width: double.infinity,
      color: _kGris,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        _s(t.nombre.toUpperCase()),
        textAlign: pw.TextAlign.center,
        style: _kTxtB,
      ),
    ),
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
      _s('Marcar según corresponda:   ${leyendaEscala(t.escala)}'),
      style: const pw.TextStyle(fontSize: 7),
    ),
    pw.SizedBox(height: 4),
    pw.Table(
      border: pw.TableBorder.all(color: _kBorde, width: .5),
      columnWidths: {
        0: t.conFilasFijas
            ? const pw.FlexColumnWidth(1.8)
            : const pw.FixedColumnWidth(22),
        for (var i = 0; i < t.camposTexto.length; i++)
          i + 1: const pw.FlexColumnWidth(1.6),
        for (var i = 0; i < t.camposEstado.length; i++)
          i + 1 + t.camposTexto.length: const pw.FlexColumnWidth(1),
        t.camposTexto.length + t.camposEstado.length + 1:
            const pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _kGris),
          children: [
            _celda(primera, negrita: true, fs: 6),
            for (final c in t.camposTexto)
              _celda(c.label.toUpperCase(), negrita: true, fs: 6),
            for (final c in t.camposEstado)
              _celda(c.label, negrita: true, fs: 5.5),
            _celda('OBSERVACIONES', negrita: true, fs: 6),
          ],
        ),
        for (var i = 0; i < filas.length; i++)
          pw.TableRow(
            decoration: filas[i].tieneHallazgo
                ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF2F2))
                : null,
            children: [
              _celda(
                t.conFilasFijas ? filas[i].titulo(t) : '${i + 1}',
                align: t.conFilasFijas
                    ? pw.Alignment.centerLeft
                    : pw.Alignment.center,
                negrita: t.conFilasFijas,
                fs: 7,
              ),
              for (final c in t.camposTexto)
                _celda(filas[i].campos[c.id] ?? '', fs: 6.5),
              for (final c in t.camposEstado)
                _celda(
                  estadoCorto(t.escala, filas[i].estados[c.id]),
                  align: pw.Alignment.center,
                  negrita: filaEstadoEsHallazgo(filas[i].estados[c.id] ?? ''),
                  color: filaEstadoEsHallazgo(filas[i].estados[c.id] ?? '')
                      ? PdfColors.red800
                      : null,
                  fs: 7,
                ),
              _celda(
                [
                  filas[i].observacion,
                  if (filas[i].evidencias.isNotEmpty)
                    '(${filas[i].evidencias.length} foto(s) en anexos)',
                ].where((x) => x.trim().isNotEmpty).join(' '),
                fs: 6.5,
              ),
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
              _celda('Sin registros', fs: 7),
            ],
          ),
      ],
    ),
  ];
}

/// "Mejora y seguimiento": los hallazgos de toda la visita con su plan de
/// acción, responsable y fecha límite.
List<pw.Widget> _mejoraYSeguimiento(
  VisitaProfesional v,
  List<VisitaHallazgo> hallazgos,
) {
  final ini = v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada;
  return [
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
      border: pw.TableBorder.all(color: _kBorde, width: .5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(3),
        4: const pw.FlexColumnWidth(1.6),
        5: const pw.FixedColumnWidth(50),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _celda('No.', negrita: true, fs: 7),
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
                    ? 'Corregir y reportar al área ${v.areaNombre}'
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
      'NOTA: Si se presentan condiciones CRÍTICAS que generen un inminente riesgo de incidente, se debe comunicar la situación al jefe del área para tomar acciones inmediatas.',
      style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
    ),
  ];
}

// ── Anexos fotográficos ─────────────────────────────────────────────────────

class _Anexo {
  final String titulo;
  final String detalle;
  final Uint8List bytes;
  const _Anexo(this.titulo, this.detalle, this.bytes);
}

/// Todas las fotos de la visita en el orden del formato: ítems, filas de
/// tabla y al final las evidencias adicionales. Una foto que no se pudo
/// descargar no tumba el informe: sale su enlace.
Future<({List<_Anexo> anexos, List<VisitaEvidencia> sinBajar})> _anexosDe(
  VisitaProfesional v,
  VisitaFormato f,
  CargadorImagen? cargar,
) async {
  final pendientes = <(String, VisitaEvidencia)>[];
  for (final it in f.itemsOrdenados) {
    for (final e
        in v.respuestas[it.id]?.evidencias ?? const <VisitaEvidencia>[]) {
      pendientes.add(('Ítem ${it.orden}: ${it.texto}', e));
    }
  }
  for (final t in f.tablas) {
    final filas = filasParaTabla(t, v.filasDe(t.id));
    for (var i = 0; i < filas.length; i++) {
      for (final e in filas[i].evidencias) {
        pendientes.add(('${t.nombre} · ${nombreFilaTabla(t, filas[i], i)}', e));
      }
    }
  }
  for (final e in v.evidenciasAdicionales) {
    pendientes.add(('Evidencia adicional', e));
  }
  final anexos = <_Anexo>[];
  final sinBajar = <VisitaEvidencia>[];
  for (final (titulo, e) in pendientes.take(80)) {
    Uint8List? bytes;
    try {
      bytes = cargar != null ? await cargar(e) : null;
      bytes ??= await _descargar(e.url);
    } catch (_) {}
    if (bytes == null || bytes.isEmpty) {
      sinBajar.add(e);
      continue;
    }
    final t = e.tomadaEn?.toDate().toLocal();
    anexos.add(
      _Anexo(
        titulo,
        [
          if (e.descripcion.trim().isNotEmpty) e.descripcion.trim(),
          if (t != null) 'Tomada el ${_dd(t)} a las ${_hhmm(t)}',
        ].join(' · '),
        _reducir(bytes),
      ),
    );
  }
  return (anexos: anexos, sinBajar: sinBajar);
}

List<pw.Widget> _paginasAnexos(
  List<_Anexo> anexos,
  List<VisitaEvidencia> sinBajar,
) {
  pw.Widget tarjeta(int n, _Anexo a) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: .6),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: 210,
          color: PdfColors.grey100,
          alignment: pw.Alignment.center,
          child: pw.Image(pw.MemoryImage(a.bytes), fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _s('Anexo $n · ${a.titulo}'),
          maxLines: 2,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        if (a.detalle.isNotEmpty)
          pw.Text(
            _s(a.detalle),
            maxLines: 3,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
          ),
      ],
    ),
  );
  final filas = <pw.Widget>[];
  for (var i = 0; i < anexos.length; i += 2) {
    filas.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: tarjeta(i + 1, anexos[i])),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: i + 1 < anexos.length
                  ? tarjeta(i + 2, anexos[i + 1])
                  : pw.SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
  return [
    pw.SizedBox(height: 6),
    pw.Container(
      width: double.infinity,
      color: _kGris,
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        'ANEXOS · REGISTRO FOTOGRÁFICO (${anexos.length})',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.SizedBox(height: 8),
    ...filas,
    if (sinBajar.isNotEmpty) ...[
      pw.Text(
        'Fotos que no se pudieron incluir (enlaces):',
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
      for (final e in sinBajar)
        pw.UrlLink(
          destination: e.url,
          child: pw.Text(
            _s(e.nombre),
            style: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.blue700,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
    ],
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
  _s(t),
  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
);

// ── Informe de una visita ───────────────────────────────────────────────────

/// Informe de una visita cerrada: una hoja por parte del formato (o una
/// sola con el encabezado del documento), todas con el encabezado del SST,
/// y al final los anexos fotográficos.
Future<Uint8List> generarInformeVisita({
  required VisitaProfesional v,
  required VisitaFormato formato,
  required String empresaNombre,
  Uint8List? logo,
  CargadorImagen? cargarImagen,
  bool conAnexos = true,
}) async {
  final doc = pw.Document(
    title: _s('Visita ${v.areaNombre} · ${v.establecimiento}'),
    author: _s(empresaNombre),
  );
  await _agregarVisita(
    doc,
    v: v,
    formato: formato,
    empresaNombre: empresaNombre,
    logo: logo,
    cargarImagen: cargarImagen,
    conAnexos: conAnexos,
  );
  return doc.save();
}

Future<void> _agregarVisita(
  pw.Document doc, {
  required VisitaProfesional v,
  required VisitaFormato formato,
  required String empresaNombre,
  Uint8List? logo,
  CargadorImagen? cargarImagen,
  bool conAnexos = true,
  PdfColor? acento,
  String etiqueta = '',
}) async {
  final firmaEst = await _bytesFirma(v.firmaEstablecimiento);
  final firmaPro = await _bytesFirma(v.firmaProfesional);
  final hallazgos = hallazgosDeVisita(formato, v.respuestas, tablas: v.tablas);
  final resumen = resumenDeVisita(formato, v.respuestas);
  final hojas = formato.hojasInforme;
  final sistema = formato.sistemaEncabezado;
  final pie = pw.Text(
    _s(
      'Inicio: ${_marca(v.inicio)}   ·   Cierre: ${_marca(v.fin)}   ·   '
      '${v.esPrueba ? 'PRUEBA · SIN VALIDEZ OPERATIVA · ubicación no comprobada.' : 'Ubicación y hora registradas por el dispositivo.'}',
    ),
    style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
  );
  var mejoraMostrada = false;
  for (var i = 0; i < hojas.length; i++) {
    final parte = hojas[i];
    // Sin partes, los ítems no tienen parte aunque la hoja lleve el código
    // del documento.
    final codigoItems = formato.partes.isEmpty ? '' : parte.codigo;
    final tablas = formato.tablasDeParte(codigoItems);
    final items = formato.itemsDeParte(codigoItems);
    final soloTablas = tablas.isNotEmpty && items.isEmpty;
    final tieneElementos = items.any((it) => it.esElemento);
    final columnasTabla = tablas.fold<int>(
      0,
      (m, t) => [
        m,
        t.camposTexto.length + t.camposEstado.length,
      ].reduce((a, b) => a > b ? a : b),
    );
    final ultima = i == hojas.length - 1;
    // Las tablas anchas (extintores: 19 columnas) van apaisadas.
    final apaisada = soloTablas && columnasTabla > 6;
    final conMejora = !mejoraMostrada && (soloTablas || ultima);
    if (conMejora) mejoraMostrada = true;
    doc.addPage(
      pw.MultiPage(
        pageFormat: apaisada
            ? PdfPageFormat.letter.landscape
            : PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: _encabezadoHoja(
            empresaNombre: empresaNombre,
            sistema: sistema,
            parte: parte,
            ctx: ctx,
            logo: logo,
            acento: acento,
            etiqueta: etiqueta,
          ),
        ),
        footer: (_) => pie,
        build: (ctx) => [
          if (v.esPrueba) _titulo('PRUEBA · SIN VALIDEZ OPERATIVA'),
          _datosVisita(v),
          if (i == 0 && formato.partes.length > 1)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                _s(
                  'Cumplimiento total de la visita: '
                  '${resumen.porcentaje == null ? '-' : '${resumen.porcentaje}%'}'
                  '  ·  ${hallazgos.length} hallazgo(s)',
                ),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ..._informacionRegistrada(v, items),
          ..._hojaItems(v, formato, codigoItems, conElementos: tieneElementos),
          for (final t in tablas) ..._hojaTabla(v, t),
          if (conMejora) ..._mejoraYSeguimiento(v, hallazgos),
          if (ultima) _observacionesGenerales(v),
          _firmas(v, firmaEst, firmaPro),
        ],
      ),
    );
  }
  if (!conAnexos) return;
  final a = await _anexosDe(v, formato, cargarImagen);
  if (a.anexos.isEmpty && a.sinBajar.isEmpty) return;
  final hojaAnexos = VisitaFormatoParte(
    codigo: hojas.last.codigo,
    nombre: 'ANEXOS · REGISTRO FOTOGRÁFICO',
    version: hojas.last.version,
    elaboracion: hojas.last.elaboracion,
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: _encabezadoHoja(
          empresaNombre: empresaNombre,
          sistema: sistema,
          parte: hojaAnexos,
          ctx: ctx,
          logo: logo,
          acento: acento,
          etiqueta: etiqueta,
        ),
      ),
      footer: (_) => pie,
      build: (ctx) => [
        pw.Text(
          _s(
            '${v.establecimiento} · ${v.areaNombre} · '
            '${_dd(v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada)} · '
            'Profesional: ${v.profesionalNombre}',
          ),
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        ..._paginasAnexos(a.anexos, a.sinBajar),
      ],
    ),
  );
}

// ── Consolidado ─────────────────────────────────────────────────────────────

/// Consolidado de un periodo (26 sep 2026: "según las fechas que se asignen;
/// al final es una agrupación, un combinado, con colores para saber cuál es
/// cuál"). Con varias áreas cada una lleva su color en las tablas, la
/// gráfica y la franja de sus actas. Con [incluirActas] van detrás las
/// actas completas de las visitas terminadas, en el mismo PDF.
Future<Uint8List> generarConsolidadoVisitas({
  required ConsolidadoMensual c,
  required String titulo,
  required DateTime desde,
  required DateTime hasta,
  required String empresaNombre,
  required List<VisitaProfesional> visitas,
  required Map<String, int> colorAreas,
  Map<String, VisitaFormato> formatos = const {},
  Uint8List? logo,
  bool incluirActas = false,
  bool conAnexos = false,
  CargadorImagen? cargarImagen,
  String generadoPor = '',
}) async {
  final doc = pw.Document(
    title: _s('Consolidado de visitas ${_dd(desde)} - ${_dd(hasta)}'),
    author: _s(empresaNombre),
  );
  PdfColor color(String areaId) =>
      PdfColor.fromInt(colorAreaVisitas(colorAreas, areaId));
  PdfColor suave(String areaId) {
    final k = color(areaId);
    return PdfColor(
      1 - (1 - k.red) * .12,
      1 - (1 - k.green) * .12,
      1 - (1 - k.blue) * .12,
    );
  }

  final varias = c.porArea.length > 1;
  final terminadas =
      visitas.where((v) => !v.esPrueba && v.estado == kVisitaTerminada).toList()
        ..sort((a, b) {
          final porArea = a.areaNombre.compareTo(b.areaNombre);
          if (varias && porArea != 0) return porArea;
          return a.fechaProgramada.compareTo(b.fechaProgramada);
        });
  final hoja = VisitaFormatoParte(
    codigo: 'CONSOLIDADO',
    nombre: 'INFORME CONSOLIDADO DE VISITAS',
    version: '1',
    elaboracion: _dd(DateTime.now()),
  );

  pw.Widget muestra(String areaId) => pw.Container(
    width: 9,
    height: 9,
    decoration: pw.BoxDecoration(
      color: color(areaId),
      borderRadius: pw.BorderRadius.circular(2),
    ),
  );

  pw.Widget kpi(String k, String v, PdfColor col) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 6),
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: col, width: .8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_s(k), style: const pw.TextStyle(fontSize: 7)),
          pw.Text(
            _s(v),
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: col,
            ),
          ),
        ],
      ),
    ),
  );

  pw.Widget subtitulo(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
    child: pw.Text(
      _s(t),
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: _kAzul,
      ),
    ),
  );

  // Barras de cumplimiento por área, del color de cada área.
  pw.Widget barras() => pw.Column(
    children: [
      for (final a in c.porArea)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 120,
                child: pw.Text(
                  _s(a.nombre),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (ctx, box) => pw.Stack(
                    children: [
                      pw.Container(
                        height: 12,
                        width: box!.maxWidth,
                        color: PdfColors.grey200,
                      ),
                      pw.Container(
                        height: 12,
                        width: box.maxWidth * ((a.promedio ?? 0) / 100),
                        color: color(a.areaId),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  a.promedio == null ? '  sin cierres' : '  ${a.promedio}%',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: _encabezadoHoja(
          empresaNombre: empresaNombre,
          sistema: 'SISTEMA DE GESTIÓN · VISITAS DE PROFESIONALES',
          parte: hoja,
          ctx: ctx,
          logo: logo,
        ),
      ),
      footer: (ctx) => pw.Text(
        _s(
          'Consolidado del ${_dd(desde)} al ${_dd(hasta)}'
          '${generadoPor.isEmpty ? '' : ' · generado por $generadoPor'}'
          ' · ${_dd(DateTime.now())} ${_hhmm(DateTime.now())}',
        ),
        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
      ),
      build: (ctx) => [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _kBorde, width: .6),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                children: [
                  _celda('PERIODO:', negrita: true, fondo: _kGris),
                  pw.Expanded(
                    child: _celda('Del ${_dd(desde)} al ${_dd(hasta)}'),
                  ),
                  _celda('DEPARTAMENTO:', negrita: true, fondo: _kGris),
                  pw.Expanded(flex: 2, child: _celda(titulo)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            kpi('Terminadas', '${c.visitasTerminadas}', PdfColors.green700),
            kpi('Sin realizar', '${c.visitasProgramadas}', PdfColors.blue700),
            kpi('Canceladas', '${c.visitasCanceladas}', PdfColors.grey600),
            kpi(
              'Cumplimiento',
              c.promedioGeneral == null ? '-' : '${c.promedioGeneral}%',
              _kMorado,
            ),
            kpi('Hallazgos', '${c.hallazgos}', PdfColors.red700),
          ],
        ),
        // Desde el 28 sep 2026 el consolidado es de un departamento ("no
        // combinar informe por áreas"); la tabla por departamento solo sale si
        // llegan varios.
        if (varias) ...[
          subtitulo('Por departamento (cada uno con su color)'),
          pw.Table(
            border: pw.TableBorder.all(color: _kBorde, width: .5),
            columnWidths: {
              0: const pw.FixedColumnWidth(16),
              1: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _kGris),
                children: [
                  _celda(''),
                  _celda('DEPARTAMENTO', negrita: true),
                  _celda('TERMINADAS', negrita: true),
                  _celda('SIN REALIZAR', negrita: true),
                  _celda('CANCELADAS', negrita: true),
                  _celda('CUMPLIMIENTO', negrita: true),
                  _celda('HALLAZGOS', negrita: true),
                ],
              ),
              for (final a in c.porArea)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: suave(a.areaId)),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: muestra(a.areaId),
                    ),
                    _celda(a.nombre, negrita: true),
                    _celda('${a.terminadas}', align: pw.Alignment.center),
                    _celda('${a.programadas}', align: pw.Alignment.center),
                    _celda('${a.canceladas}', align: pw.Alignment.center),
                    _celda(
                      a.promedio == null ? '-' : '${a.promedio}%',
                      align: pw.Alignment.center,
                      negrita: true,
                    ),
                    _celda('${a.hallazgos}', align: pw.Alignment.center),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 8),
          barras(),
        ],
        subtitulo('Por establecimiento (peores primero)'),
        pw.Table(
          border: pw.TableBorder.all(color: _kBorde, width: .5),
          columnWidths: {
            0: const pw.FixedColumnWidth(16),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: _kGris),
              children: [
                _celda(''),
                _celda('ESTABLECIMIENTO', negrita: true),
                _celda('DEPARTAMENTO', negrita: true),
                _celda('VISITAS', negrita: true),
                _celda('CUMPLIMIENTO', negrita: true),
                _celda('HALLAZGOS', negrita: true),
              ],
            ),
            for (final e in c.porEstablecimiento)
              pw.TableRow(
                decoration: e.areaId.isEmpty
                    ? null
                    : pw.BoxDecoration(color: suave(e.areaId)),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: e.areaId.isEmpty ? pw.SizedBox() : muestra(e.areaId),
                  ),
                  _celda(e.nombre),
                  _celda(e.areaNombre.isEmpty ? titulo : e.areaNombre, fs: 7),
                  _celda('${e.visitas}', align: pw.Alignment.center),
                  _celda(
                    e.promedio == null ? '-' : '${e.promedio}%',
                    align: pw.Alignment.center,
                    negrita: true,
                    color: (e.promedio ?? 100) < 80 ? PdfColors.red800 : null,
                  ),
                  _celda('${e.hallazgos}', align: pw.Alignment.center),
                ],
              ),
            if (c.porEstablecimiento.isEmpty)
              pw.TableRow(
                children: [
                  _celda(''),
                  _celda('Sin visitas terminadas en el periodo'),
                  _celda(''),
                  _celda(''),
                  _celda(''),
                  _celda(''),
                ],
              ),
          ],
        ),
        if (c.itemsCriticos.isNotEmpty) ...[
          subtitulo('Lo que más se incumple'),
          pw.Table(
            border: pw.TableBorder.all(color: _kBorde, width: .5),
            columnWidths: {
              0: const pw.FlexColumnWidth(6),
              1: const pw.FixedColumnWidth(50),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _kGris),
                children: [
                  _celda('ÍTEM', negrita: true),
                  _celda('VECES', negrita: true),
                ],
              ),
              for (final i in c.itemsCriticos.take(15))
                pw.TableRow(
                  children: [
                    _celda(i.texto, fs: 7.5),
                    _celda(
                      '${i.incumplimientos}',
                      align: pw.Alignment.center,
                      negrita: true,
                    ),
                  ],
                ),
            ],
          ),
        ],
        subtitulo('Detalle de visitas terminadas'),
        pw.Table(
          border: pw.TableBorder.all(color: _kBorde, width: .5),
          columnWidths: {
            0: const pw.FixedColumnWidth(12),
            1: const pw.FixedColumnWidth(48),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: _kGris),
              children: [
                _celda(''),
                _celda('FECHA', negrita: true, fs: 7),
                _celda('ESTABLECIMIENTO', negrita: true, fs: 7),
                _celda('ÁREA', negrita: true, fs: 7),
                _celda('PROFESIONAL', negrita: true, fs: 7),
                _celda('%', negrita: true, fs: 7),
                _celda('HALL.', negrita: true, fs: 7),
                _celda('INICIO', negrita: true, fs: 7),
                _celda('EN SITIO', negrita: true, fs: 7),
                _celda('FIRMAS', negrita: true, fs: 7),
              ],
            ),
            for (final v in terminadas)
              pw.TableRow(
                decoration: varias
                    ? pw.BoxDecoration(color: suave(v.areaId))
                    : null,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(2),
                    child: muestra(v.areaId),
                  ),
                  _celda(_dd(v.fechaProgramada), fs: 7),
                  _celda(v.establecimiento, fs: 7),
                  _celda(v.areaNombre, fs: 7),
                  _celda(v.profesionalNombre, fs: 7),
                  _celda(
                    v.cumplimiento == null ? '-' : '${v.cumplimiento}',
                    fs: 7,
                    negrita: true,
                  ),
                  _celda('${hallazgosDe(v)}', fs: 7),
                  _celda(
                    v.inicio == null
                        ? '-'
                        : _hhmm(v.inicio!.at.toDate().toLocal()),
                    fs: 7,
                  ),
                  _celda(
                    v.inicio?.distanciaMetros == null
                        ? '-'
                        : '${v.inicio!.distanciaMetros!.round()} m',
                    fs: 7,
                  ),
                  _celda(v.firmada ? 'Sí' : 'No', fs: 7),
                ],
              ),
          ],
        ),
        if (incluirActas && terminadas.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              _s(
                'A continuación, las ${terminadas.length} actas completas'
                '${varias ? ', agrupadas por área y con la franja del color de su área' : ''}.',
              ),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
      ],
    ),
  );

  if (incluirActas) {
    for (var i = 0; i < terminadas.length; i++) {
      final v = terminadas[i];
      final f = v.formatoAsignado ?? formatos[v.formatoId];
      if (f == null) continue;
      await _agregarVisita(
        doc,
        v: v,
        formato: f,
        empresaNombre: empresaNombre,
        logo: logo,
        cargarImagen: cargarImagen,
        conAnexos: conAnexos,
        acento: color(v.areaId),
        etiqueta:
            'ACTA ${i + 1} DE ${terminadas.length} · ${v.areaNombre.toUpperCase()} · '
            '${v.establecimiento.toUpperCase()} · ${_dd(v.fechaProgramada)}',
      );
    }
  }
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
