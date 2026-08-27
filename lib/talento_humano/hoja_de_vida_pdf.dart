// lib/talento_humano/hoja_de_vida_pdf.dart

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ── Colores ───────────────────────────────────────────────────────────────────
const _kPrimary = PdfColor.fromInt(0xFFC28942);
const _kBg      = PdfColor.fromInt(0xFFF9F3EA);
const _kText    = PdfColor.fromInt(0xFF1A1A1A);
const _kMuted   = PdfColor.fromInt(0xFF6B7280);
const _kDivider = PdfColor.fromInt(0xFFE5D9C7);

// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generarHojaDeVidaPDF(
  Map<String, dynamic> data,
  Map<String, dynamic>? orgData,
  String nombreEmpleado,
) async {
  final doc = pw.Document(compress: true);

  // Foto
  pw.ImageProvider? foto;
  final fotoUrl = data['fotoUrl'] as String?;
  if (fotoUrl != null && fotoUrl.isNotEmpty) {
    try {
      final r = await http.get(Uri.parse(fotoUrl));
      if (r.statusCode == 200) foto = pw.MemoryImage(r.bodyBytes);
    } catch (_) {}
  }

  // ── Páginas de texto ─────────────────────────────────────────────────────────
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // header + content con margen suficiente para no solapar
      margin: const pw.EdgeInsets.fromLTRB(40, 20, 40, 36),
      header: (ctx) => _header(nombreEmpleado),
      footer: (ctx) => _footer(ctx),
      build: (ctx) => [
        pw.SizedBox(height: 10), // espacio bajo el header
        _portada(data, orgData, foto),
        pw.SizedBox(height: 16),
        ..._seccionDatosPersonales(data), // lista de widgets → page-break aware
        pw.SizedBox(height: 12),
        ..._seccionFormacion(data),
        pw.SizedBox(height: 12),
        ..._seccionCursos(data),
        pw.SizedBox(height: 12),
        ..._seccionExperiencia(data),
      ],
    ),
  );

  // ── Anexos: PDF soportes rasterizados ────────────────────────────────────────
  final anexos = _buildAnexosList(data);
  for (final anexo in anexos) {
    if ((anexo.url ?? '').isEmpty) continue;
    try {
      final r = await http.get(Uri.parse(anexo.url!));
      if (r.statusCode != 200) continue;

      // Sin página separadora — el documento va directo
      const dpi = 96.0;
      await for (final raster in Printing.raster(r.bodyBytes, dpi: dpi)) {
        final imgBytes = await raster.toPng();
        final ptW = raster.width * 72.0 / dpi;
        final ptH = raster.height * 72.0 / dpi;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(ptW, ptH),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(imgBytes)),
          ),
        );
        // Cede el hilo al event-loop para no congelar el navegador
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      debugPrint('[HvPDF] error anexando ${anexo.label}: $e');
    }
  }

  return doc.save();
}

// ── Anexos ────────────────────────────────────────────────────────────────────

class _Anexo {
  final String label;
  final String? url;
  const _Anexo(this.label, this.url);
}

List<_Anexo> _buildAnexosList(Map<String, dynamic> d) {
  final list = <_Anexo>[
    _Anexo('Procuraduría',       d['procUrl']       as String?),
    _Anexo('Contraloría',        d['contrUrl']      as String?),
    _Anexo('Policía Nacional',   d['polUrl']        as String?),
    _Anexo('Medidas Correctivas',d['medUrl']        as String?),
    _Anexo('Documento de Cédula',d['cedulaDocUrl']  as String?),
    _Anexo('Soporte EPS',        d['epsUrl']        as String?),
    _Anexo('Soporte Pensiones',  d['pensionUrl']    as String?),
    _Anexo('Soporte Cesantías',  d['cesantiasUrl']  as String?),
    _Anexo('Título Bachillerato',d['bachillerUrl']  as String?),
  ];
  if (d['hasUniversity'] == true) {
    list.add(_Anexo('Título Universitario', d['uniUrl'] as String?));
    if (d['hasTarjeta'] == true) {
      list.add(_Anexo('Tarjeta Profesional', d['tarjetaUrl'] as String?));
    }
  }
  if (d['hasSecondCareer'] == true) {
    list.add(_Anexo('Segunda Carrera', d['secUrl'] as String?));
  }
  if (d['hasEspecializacion'] == true) {
    list.add(_Anexo('Especialización', d['espUrl'] as String?));
  }
  if (d['hasMaestria'] == true) {
    list.add(_Anexo('Maestría', d['maeUrl'] as String?));
  }

  for (var i = 0; i < (d['cursos'] as List? ?? []).length; i++) {
    final c = (d['cursos'] as List)[i] as Map<String, dynamic>? ?? {};
    list.add(_Anexo('Curso: ${c['nombre'] ?? i + 1}', c['url'] as String?));
  }
  for (var i = 0; i < (d['experiencias'] as List? ?? []).length; i++) {
    final e = (d['experiencias'] as List)[i] as Map<String, dynamic>? ?? {};
    list.add(_Anexo('Experiencia: ${e['empresa'] ?? i + 1}', e['soporteUrl'] as String?));
  }

  return list.where((a) => (a.url ?? '').isNotEmpty).toList();
}

// ── Header / Footer ───────────────────────────────────────────────────────────

pw.Widget _header(String nombre) => pw.Container(
  padding: const pw.EdgeInsets.only(bottom: 6),
  margin:  const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _kPrimary, width: 1.5)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('HOJA DE VIDA',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
              color: _kPrimary, letterSpacing: 1.5)),
      pw.Text(nombre.toUpperCase(),
          style: const pw.TextStyle(fontSize: 9, color: _kMuted)),
    ],
  ),
);

pw.Widget _footer(pw.Context ctx) => pw.Container(
  padding: const pw.EdgeInsets.only(top: 6),
  decoration: const pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _kDivider, width: 0.5)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('Documento confidencial – Talento Humano',
          style: const pw.TextStyle(fontSize: 8, color: _kMuted)),
      pw.Text('Pág. ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _kMuted)),
    ],
  ),
);

// ── Portada ───────────────────────────────────────────────────────────────────

pw.Widget _portada(Map<String, dynamic> d, Map<String, dynamic>? org, pw.ImageProvider? foto) {
  final nombre = '${d['primerNombre'] ?? ''} ${d['segundoNombre'] ?? ''} '
      '${d['primerApellido'] ?? ''} ${d['segundoApellido'] ?? ''}'
      .replaceAll(RegExp(r'\s+'), ' ').trim();
  final cedula = (d['cedula'] ?? '').toString();
  final cargo  = (org?['cargo'] ?? d['cargo'] ?? '').toString();
  final area   = (org?['areaNombre'] ?? d['areaNombre'] ?? '').toString();

  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: _kBg,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _kDivider),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (foto != null)
          pw.Container(
            width: 80, height: 100,
            margin: const pw.EdgeInsets.only(right: 16),
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: _kDivider, width: 1),
            ),
            child: pw.ClipRRect(
              horizontalRadius: 6, verticalRadius: 6,
              child: pw.Image(foto, fit: pw.BoxFit.cover),
            ),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(nombre,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _kText)),
              if (cedula.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text('C.C. $cedula',
                    style: const pw.TextStyle(fontSize: 10, color: _kMuted)),
              ],
              if (cargo.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: const pw.BoxDecoration(
                    color: _kPrimary,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(20)),
                  ),
                  child: pw.Text(cargo,
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                ),
              ],
              if (area.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(area, style: const pw.TextStyle(fontSize: 10, color: _kMuted)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Secciones de texto ────────────────────────────────────────────────────────

/// Retorna lista de widgets (page-break aware en MultiPage).
List<pw.Widget> _seccionDatosPersonales(Map<String, dynamic> d) {
  // Todos los datos en pares de filas (2 columnas) → cada Row es un item
  // separado que MultiPage puede partir entre páginas.
  final pares = <List<_DatoItem>>[];

  void add(String label, dynamic value) {
    final v = (value?.toString() ?? '').trim();
    if (v.isEmpty) return;
    if (pares.isEmpty || pares.last.length >= 2) pares.add([]);
    pares.last.add(_DatoItem(label, v));
  }

  add('Email',              d['email']);
  add('Teléfono',           d['telefono']);
  add('Dirección',          d['direccion']);
  add('Ciudad',             d['ciudad']);
  add('Barrio',             d['barrio']);
  add('EPS',                d['eps']);
  add('Pensiones',          d['fondoPensiones']);
  add('Cesantías',          d['fondoCesantias']);
  add('Fecha de nacimiento',d['fechaNacimiento']);
  add('Lugar de nacimiento',d['nacimientoCiudadNombre'] ?? d['lugarNacimiento']);

  if (pares.isEmpty) return [];

  return [
    _titulo('DATOS PERSONALES'),
    pw.SizedBox(height: 8),
    ...pares.map((par) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _datoWidget(par[0].label, par[0].value)),
          if (par.length > 1)
            pw.Expanded(child: _datoWidget(par[1].label, par[1].value))
          else
            pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    )),
  ];
}

class _DatoItem {
  final String label, value;
  const _DatoItem(this.label, this.value);
}

pw.Widget _datoWidget(String label, String value) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _kMuted)),
    pw.Text(value,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kText)),
  ],
);

List<pw.Widget> _seccionFormacion(Map<String, dynamic> d) {
  final items = <pw.Widget>[];
  void add(String nivel, String? inst, String? carr, String? fecha) {
    if ((inst ?? '').isEmpty && (carr ?? '').isEmpty) return;
    items.add(_itemFormacion(nivel: nivel, institucion: inst, carrera: carr, fecha: fecha));
  }
  add('Bachillerato', d['bachInst'] as String?, null, d['bachFecha'] as String?);
  if (d['hasUniversity'] == true) {
    add('Universidad', d['uniInst'] as String?, d['uniCarr'] as String?, d['uniFecha'] as String?);
  }
  if (d['hasSecondCareer'] == true) {
    add('Segunda Carrera', d['secInst'] as String?, d['secCarr'] as String?, d['secFecha'] as String?);
  }
  if (d['hasEspecializacion'] == true) {
    add('Especialización', d['espInst'] as String?, d['espCarr'] as String?, d['espFecha'] as String?);
  }
  if (d['hasMaestria'] == true) {
    add('Maestría', d['maeInst'] as String?, d['maeCarr'] as String?, d['maeFecha'] as String?);
  }
  if (items.isEmpty) return [];
  return [_titulo('FORMACIÓN ACADÉMICA'), pw.SizedBox(height: 8), ...items];
}

List<pw.Widget> _seccionCursos(Map<String, dynamic> d) {
  final cursos = (d['cursos'] as List? ?? []).cast<Map<String, dynamic>>();
  if (cursos.isEmpty) return [];
  return [
    _titulo('CURSOS COMPLEMENTARIOS'),
    pw.SizedBox(height: 8),
    ...cursos.map(_itemCurso),
  ];
}

List<pw.Widget> _seccionExperiencia(Map<String, dynamic> d) {
  final exps = (d['experiencias'] as List? ?? []).cast<Map<String, dynamic>>();
  if (exps.isEmpty) return [];
  return [
    _titulo('EXPERIENCIA LABORAL'),
    pw.SizedBox(height: 8),
    ...exps.map(_itemExperiencia),
  ];
}

// ── Componentes reutilizables ─────────────────────────────────────────────────

pw.Widget _titulo(String text) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
            color: _kPrimary, letterSpacing: 1.2)),
    pw.Container(height: 1, color: _kPrimary,
        margin: const pw.EdgeInsets.only(top: 3, bottom: 2)),
  ],
);

pw.Widget _itemFormacion({
  required String nivel,
  String? institucion,
  String? carrera,
  String? fecha,
}) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(
        color: _kBg,
        border: pw.Border(left: pw.BorderSide(color: _kPrimary, width: 3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(nivel,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kPrimary)),
          if ((institucion ?? '').isNotEmpty)
            pw.Text(institucion!,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kText)),
          if ((carrera ?? '').isNotEmpty)
            pw.Text(carrera!, style: const pw.TextStyle(fontSize: 10, color: _kText)),
          if ((fecha ?? '').isNotEmpty)
            pw.Text(fecha!, style: const pw.TextStyle(fontSize: 9, color: _kMuted)),
        ],
      ),
    );

pw.Widget _itemCurso(Map<String, dynamic> c) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 5, height: 5,
        margin: const pw.EdgeInsets.only(top: 3, right: 8),
        decoration: const pw.BoxDecoration(color: _kPrimary, shape: pw.BoxShape.circle),
      ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(c['nombre'] as String? ?? '',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kText)),
            pw.Text(
              [
                if ((c['institucion'] as String? ?? '').isNotEmpty) c['institucion'],
                if ((c['fecha'] as String? ?? '').isNotEmpty) c['fecha'],
                if ((c['horas'] as String? ?? '').isNotEmpty) '${c['horas']} horas',
              ].join(' · '),
              style: const pw.TextStyle(fontSize: 9, color: _kMuted),
            ),
          ],
        ),
      ),
    ],
  ),
);

pw.Widget _itemExperiencia(Map<String, dynamic> e) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 10),
  padding: const pw.EdgeInsets.all(10),
  decoration: const pw.BoxDecoration(
    color: _kBg,
    border: pw.Border(left: pw.BorderSide(color: _kPrimary, width: 3)),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(e['empresa'] as String? ?? '',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kText)),
      if ((e['cargo'] as String? ?? '').isNotEmpty)
        pw.Text(e['cargo'] as String,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kPrimary)),
      pw.Text(
        [(e['fechaInicio'] ?? ''), (e['fechaFin'] ?? '')].where((s) => s.isNotEmpty).join(' — '),
        style: const pw.TextStyle(fontSize: 9, color: _kMuted),
      ),
      if ((e['funciones'] as String? ?? '').isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(e['funciones'] as String, style: const pw.TextStyle(fontSize: 9, color: _kText)),
      ],
    ],
  ),
);
