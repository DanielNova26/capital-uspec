// lib/talento_humano/carnet_pdf.dart
//
// El carnet impreso. Un solo modelo para todas las empresas: lo único que
// cambia son los dos colores y el logo (ver carnet_marca.dart).
//
// Se dibuja como PDF VECTORIAL, no como imagen. A 54 mm de ancho, un PNG
// tendría que venir a 640 px para no verse pixelado en impresión, y habría que
// rehacerlo cada vez que una empresa cambia de color. Aquí el tamaño de
// impresión no degrada nada y el color es un parámetro.
//
// El QR es el mismo de carnet_qr.dart: lleva el token opaco, no la cédula.
// Su tamaño NO es decorativo — ver la nota en [_ladoQr].

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'carnet_layout.dart';
import 'carnet_marca.dart';
import 'carnet_qr.dart';

/// Tamaños de impresión disponibles.
enum CarnetFormato {
  /// Tarjeta PVC estándar (CR80 vertical). Es la que aceptan las impresoras de
  /// carnets y la que entra en cualquier porta-carnet del mercado.
  tarjeta(54, 85.6, 'Tarjeta 54 × 86 mm'),

  /// Escarapela de cinta: se lee de lejos, no entra en porta-carnet normal.
  escarapela(86, 120, 'Escarapela 86 × 120 mm');

  const CarnetFormato(this.anchoMm, this.altoMm, this.etiqueta);

  final double anchoMm;
  final double altoMm;
  final String etiqueta;

  double get ancho => anchoMm * PdfPageFormat.mm;
  double get alto => altoMm * PdfPageFormat.mm;
}

/// Los datos que se imprimen. Nada más entra al carnet.
class CarnetPersona {
  final String userId;
  final String nombres;
  final String apellidos;
  final String cargo;
  final String cedula;
  final String rh;
  final String token;
  final String fotoUrl;

  const CarnetPersona({
    required this.userId,
    required this.nombres,
    required this.apellidos,
    required this.cargo,
    required this.cedula,
    this.rh = '',
    this.token = '',
    this.fotoUrl = '',
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  String get inicial {
    final base = nombres.trim().isNotEmpty ? nombres.trim() : apellidos.trim();
    return base.isEmpty ? '?' : base[0].toUpperCase();
  }
}

/// Imágenes ya descargadas. Se pasan armadas para que una hoja de 9 carnets no
/// baje el logo nueve veces.
class CarnetRecursos {
  final pw.ImageProvider? logo;
  final Map<String, pw.ImageProvider> fotos;

  const CarnetRecursos({this.logo, this.fotos = const {}});
}

const PdfColor _kTexto = PdfColor.fromInt(0xFF111111);
const PdfColor _kPlaceholder = PdfColor.fromInt(0xFFE2E8F0);
const PdfColor _kPlaceholderTexto = PdfColor.fromInt(0xFF94A3B8);
const PdfColor _kMarcaCorte = PdfColor.fromInt(0xFFBFBFBF);

/// Carnet de una sola persona, en una página del tamaño exacto de la tarjeta.
///
/// Sin márgenes: la banda del cargo sangra de borde a borde, como en el diseño.
Future<Uint8List> buildCarnetPdf({
  required CarnetPersona persona,
  required CarnetMarca marca,
  CarnetFormato formato = CarnetFormato.tarjeta,
  CarnetRecursos? recursos,
}) {
  return buildCarnetsIndividualesPdf(
    personas: [persona],
    marca: marca,
    formato: formato,
    recursos: recursos,
  );
}

/// Un carnet por página, con la página del tamaño exacto de la tarjeta.
///
/// Es lo que espera una impresora de carnets PVC: alimenta tarjeta por tarjeta
/// y no sabe recortar. La hoja carta de [buildCarnetsHojaPdf] sirve para lo
/// contrario, imprimir en papel y cortar a mano.
Future<Uint8List> buildCarnetsIndividualesPdf({
  required List<CarnetPersona> personas,
  required CarnetMarca marca,
  CarnetFormato formato = CarnetFormato.tarjeta,
  CarnetRecursos? recursos,
}) async {
  if (personas.isEmpty) {
    throw ArgumentError('No hay personas seleccionadas para el carnet.');
  }
  final res =
      recursos ?? await cargarRecursosCarnet(marca: marca, personas: personas);
  final doc = pw.Document(theme: await temaCarnet());
  for (final persona in personas) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(formato.ancho, formato.alto, marginAll: 0),
        build: (_) => carnetWidget(
          persona: persona,
          marca: marca,
          formato: formato,
          recursos: res,
        ),
      ),
    );
  }
  return doc.save();
}

/// Hoja carta con varios carnets listos para recortar.
///
/// La rejilla se calcula con el tamaño real de la tarjeta en vez de fijar
/// "3 × 3": así el mismo código sirve para los dos formatos y no queda un
/// número mágico que se rompe si mañana se agrega otro tamaño.
Future<Uint8List> buildCarnetsHojaPdf({
  required List<CarnetPersona> personas,
  required CarnetMarca marca,
  CarnetFormato formato = CarnetFormato.tarjeta,
  CarnetRecursos? recursos,
}) async {
  if (personas.isEmpty) {
    throw ArgumentError('No hay personas seleccionadas para el carnet.');
  }
  final res =
      recursos ?? await cargarRecursosCarnet(marca: marca, personas: personas);
  final doc = pw.Document(theme: await temaCarnet());

  const margen = 8 * PdfPageFormat.mm;
  const canal = 3 * PdfPageFormat.mm;
  final utilAncho = PdfPageFormat.letter.width - margen * 2;
  final utilAlto = PdfPageFormat.letter.height - margen * 2;

  final columnas = math.max(
    1,
    ((utilAncho + canal) / (formato.ancho + canal)).floor(),
  );
  final filas = math.max(
    1,
    ((utilAlto + canal) / (formato.alto + canal)).floor(),
  );
  final porHoja = columnas * filas;

  for (var inicio = 0; inicio < personas.length; inicio += porHoja) {
    final lote = personas.skip(inicio).take(porHoja).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.copyWith(
          marginTop: margen,
          marginBottom: margen,
          marginLeft: margen,
          marginRight: margen,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var fila = 0; fila * columnas < lote.length; fila++) ...[
              if (fila > 0) pw.SizedBox(height: canal),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (
                    var col = 0;
                    col < columnas && fila * columnas + col < lote.length;
                    col++
                  ) ...[
                    if (col > 0) pw.SizedBox(width: canal),
                    _conMarcasDeCorte(
                      formato: formato,
                      child: carnetWidget(
                        persona: lote[fila * columnas + col],
                        marca: marca,
                        formato: formato,
                        recursos: res,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Cuántos carnets caben en una hoja carta. La pantalla lo usa para avisar
/// cuántas hojas va a imprimir antes de mandar el documento.
int carnetsPorHoja(CarnetFormato formato) {
  const margen = 8 * PdfPageFormat.mm;
  const canal = 3 * PdfPageFormat.mm;
  final columnas = math.max(
    1,
    ((PdfPageFormat.letter.width - margen * 2 + canal) /
            (formato.ancho + canal))
        .floor(),
  );
  final filas = math.max(
    1,
    ((PdfPageFormat.letter.height - margen * 2 + canal) /
            (formato.alto + canal))
        .floor(),
  );
  return columnas * filas;
}

/// Marcas de corte en las esquinas, por fuera de la tarjeta.
///
/// No se dibuja un borde sobre el carnet: la tijera nunca cae exacta y ese
/// borde queda como una línea sucia dentro de la tarjeta impresa.
pw.Widget _conMarcasDeCorte({
  required CarnetFormato formato,
  required pw.Widget child,
}) {
  return pw.CustomPaint(
    size: PdfPoint(formato.ancho, formato.alto),
    foregroundPainter: (canvas, size) {
      const largo = 2.0 * PdfPageFormat.mm;
      canvas
        ..saveContext()
        ..setStrokeColor(_kMarcaCorte)
        ..setLineWidth(0.4);
      for (final x in [0.0, size.x]) {
        for (final y in [0.0, size.y]) {
          final haciaX = x == 0 ? -largo : largo;
          final haciaY = y == 0 ? -largo : largo;
          canvas
            ..moveTo(x, y)
            ..lineTo(x + haciaX, y)
            ..moveTo(x, y)
            ..lineTo(x, y + haciaY);
        }
      }
      canvas
        ..strokePath()
        ..restoreContext();
    },
    child: child,
  );
}

/// El carnet en sí. Se usa igual suelto que dentro de la hoja de lotes.
pw.Widget carnetWidget({
  required CarnetPersona persona,
  required CarnetMarca marca,
  required CarnetFormato formato,
  required CarnetRecursos recursos,
}) {
  final w = formato.ancho;
  final h = formato.alto;
  // Letras y QR se miden contra la unidad, no contra el ancho: ver la nota de
  // las dos unidades en carnet_layout.dart.
  final u = unidadCarnet(w, h);
  final primario = PdfColor.fromInt(marca.colorPrimario);
  final secundario = PdfColor.fromInt(marca.colorSecundario);

  return pw.SizedBox(
    width: w,
    height: h,
    child: pw.Stack(
      fit: pw.StackFit.expand,
      children: [
        // Fondo blanco + arcos decorativos.
        pw.CustomPaint(
          size: PdfPoint(w, h),
          painter: (canvas, size) =>
              _fondo(canvas, size, primario: primario, secundario: secundario),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(height: h * CarnetLayout.margenSuperior),
            _logo(recursos.logo, marca, w: w, h: h, color: primario),
            pw.SizedBox(height: h * CarnetLayout.espacioLogoFoto),
            _foto(persona, recursos, h: h),
            pw.SizedBox(height: h * CarnetLayout.espacioFotoNombre),
            _nombre(persona, w: w, u: u),
            pw.Spacer(),
            _bandaCargo(persona.cargo, w: w, h: h, u: u, color: primario),
            pw.SizedBox(height: h * CarnetLayout.espacioBandaPie),
            _pie(persona, w: w, h: h, u: u),
          ],
        ),
      ],
    ),
  );
}

/// Blanco de base y los arcos concéntricos de las esquinas.
///
/// Los centros de los círculos caen FUERA de la tarjeta: por eso se ve el arco
/// y no el círculo completo. El recorte al rectángulo del carnet es
/// obligatorio; sin él la circunferencia se sale y, en la hoja de lotes,
/// invade el carnet de al lado.
void _fondo(
  PdfGraphics canvas,
  PdfPoint size, {
  required PdfColor primario,
  required PdfColor secundario,
}) {
  final w = size.x;
  final h = size.y;

  canvas
    ..saveContext()
    ..drawRect(0, 0, w, h)
    ..clipPath()
    ..setFillColor(PdfColors.white)
    ..drawRect(0, 0, w, h)
    ..fillPath();

  // El origen del PDF está abajo a la izquierda: el cúmulo "de arriba" lleva
  // la y alta.
  _arcos(
    canvas,
    cx: w * CarnetLayout.arcoSupCx,
    cy: h * CarnetLayout.arcoSupCy,
    rMin: w * CarnetLayout.arcoSupRadioMin,
    paso: w * CarnetLayout.arcoSupPaso,
    cuantos: CarnetLayout.arcoSupCuantos,
    a: secundario,
    b: primario,
    grosor: w * CarnetLayout.arcoGrosor,
  );
  _arcos(
    canvas,
    cx: w * CarnetLayout.arcoInfCx,
    cy: h * CarnetLayout.arcoInfCy,
    rMin: w * CarnetLayout.arcoInfRadioMin,
    paso: w * CarnetLayout.arcoInfPaso,
    cuantos: CarnetLayout.arcoInfCuantos,
    a: primario,
    b: secundario,
    grosor: w * CarnetLayout.arcoGrosor,
  );

  canvas.restoreContext();
}

void _arcos(
  PdfGraphics canvas, {
  required double cx,
  required double cy,
  required double rMin,
  required double paso,
  required int cuantos,
  required PdfColor a,
  required PdfColor b,
  required double grosor,
}) {
  canvas.setLineWidth(grosor);
  for (var i = 0; i < cuantos; i++) {
    final r = rMin + paso * i;
    canvas
      ..setStrokeColor(i.isEven ? a : b)
      ..drawEllipse(cx, cy, r, r)
      ..strokePath();
  }
}

/// Logo de la empresa. Si no hay, el nombre de la empresa ocupa su sitio: un
/// carnet sin logo sigue sirviendo, uno con un hueco arriba no.
pw.Widget _logo(
  pw.ImageProvider? logo,
  CarnetMarca marca, {
  required double w,
  required double h,
  required PdfColor color,
}) {
  final alto = h * CarnetLayout.altoLogo;
  if (logo != null) {
    return pw.SizedBox(
      height: alto,
      width: w * CarnetLayout.anchoLogo,
      child: pw.Image(logo, fit: pw.BoxFit.contain),
    );
  }
  return pw.SizedBox(
    height: alto,
    width: w * CarnetLayout.anchoNombreEmpresa,
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      child: pw.Text(
        marca.empresaNombre.toUpperCase(),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: w * CarnetLayout.letraEmpresaSinLogo,
          color: color,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  );
}

pw.Widget _foto(
  CarnetPersona persona,
  CarnetRecursos recursos, {
  required double h,
}) {
  final d = h * CarnetLayout.diametroFoto;
  final foto = recursos.fotos[persona.userId];
  if (foto == null) {
    return pw.Container(
      width: d,
      height: d,
      alignment: pw.Alignment.center,
      decoration: const pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: _kPlaceholder,
      ),
      child: pw.Text(
        persona.inicial,
        style: pw.TextStyle(
          fontSize: d * 0.42,
          color: _kPlaceholderTexto,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }
  return pw.Container(
    width: d,
    height: d,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      image: pw.DecorationImage(image: foto, fit: pw.BoxFit.cover),
    ),
  );
}

/// Nombres arriba y apellidos abajo, en dos renglones y en mayúsculas.
///
/// Van separados porque es como se lee un carnet de un vistazo: el apellido en
/// grande. Si la persona solo tiene uno de los dos cargado, se imprime el que
/// haya en vez de dejar un renglón vacío.
pw.Widget _nombre(
  CarnetPersona persona, {
  required double w,
  required double u,
}) {
  final nombres = persona.nombres.trim().toUpperCase();
  final apellidos = persona.apellidos.trim().toUpperCase();

  pw.Widget renglon(String texto, double tamano) {
    return pw.SizedBox(
      width: w * CarnetLayout.anchoNombre,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        child: pw.Text(
          texto,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: tamano, color: _kTexto),
        ),
      ),
    );
  }

  if (nombres.isEmpty && apellidos.isEmpty) {
    return renglon('SIN NOMBRE', u * CarnetLayout.letraNombres);
  }
  if (nombres.isEmpty || apellidos.isEmpty) {
    return renglon(
      nombres.isEmpty ? apellidos : nombres,
      u * CarnetLayout.letraNombreUnico,
    );
  }
  return pw.Column(
    children: [
      renglon(nombres, u * CarnetLayout.letraNombres),
      pw.SizedBox(height: u * CarnetLayout.espacioRenglon),
      renglon(apellidos, u * CarnetLayout.letraApellidos),
    ],
  );
}

/// Banda de color con el cargo, de borde a borde.
///
/// Alto fijo aunque el cargo sea corto: si la banda cambiara de alto según el
/// texto, dos carnets de la misma hoja quedarían desalineados.
pw.Widget _bandaCargo(
  String cargo, {
  required double w,
  required double h,
  required double u,
  required PdfColor color,
}) {
  return pw.Container(
    width: w,
    height: h * CarnetLayout.altoBanda,
    color: color,
    alignment: pw.Alignment.center,
    padding: pw.EdgeInsets.symmetric(horizontal: w * CarnetLayout.margenCargo),
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      child: pw.Text(
        cargo.trim().isEmpty ? '—' : cargo.trim(),
        textAlign: pw.TextAlign.center,
        maxLines: 2,
        style: pw.TextStyle(
          fontSize: u * CarnetLayout.letraCargo,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  );
}

/// Pie del carnet: cédula y RH a la izquierda, QR a la derecha.
///
/// En el diseño de referencia la cédula va centrada ENCIMA del QR, pero ese
/// modelo es más alargado (proporción 0,59) que una tarjeta CR80 (0,63). Al
/// apilarlos, el contenido no cabe en el alto de la tarjeta y la columna
/// desborda. Ponerlos en la misma fila ocupa el hueco que en el modelo queda
/// vacío al lado del QR y devuelve el alto que faltaba, sin quitar ni encoger
/// nada de lo que el carnet tiene que mostrar.
pw.Widget _pie(
  CarnetPersona persona, {
  required double w,
  required double h,
  required double u,
}) {
  return pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(
      w * CarnetLayout.margenPie,
      0,
      w * CarnetLayout.margenPie,
      h * CarnetLayout.margenInferior,
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(child: _documento(persona, u: u)),
        _ladoQr(persona, u: u),
      ],
    ),
  );
}

/// Cédula y RH.
///
/// La cédula SÍ va impresa: el carnet es un documento que se muestra en mano y
/// para eso sirve. Lo que no puede llevarla es el QR, porque ese se fotografía
/// y circula sin control (ver carnet_qr.dart).
pw.Widget _documento(CarnetPersona persona, {required double u}) {
  final estilo = pw.TextStyle(
    fontSize: u * CarnetLayout.letraDocumento,
    color: _kTexto,
  );
  final rh = persona.rh.trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text('CC: ${persona.cedula.trim()}', style: estilo, maxLines: 1),
      if (rh.isNotEmpty) ...[
        pw.SizedBox(height: u * CarnetLayout.espacioRenglon),
        pw.Text('RH: $rh', style: estilo, maxLines: 1),
      ],
    ],
  );
}

/// QR de verificación.
///
/// El lado NO se puede achicar "porque se ve mejor". La URL con el token da un
/// QR de unos 37 módulos más su zona de silencio; por debajo de este tamaño
/// cada módulo baja de ~0,36 mm impresos y los teléfonos empiezan a fallar. Un
/// carnet cuyo QR no se lee no es un carnet verificable.
pw.Widget _ladoQr(CarnetPersona persona, {required double u}) {
  final lado = u * CarnetLayout.ladoQr;
  if (persona.token.trim().isEmpty) {
    return pw.SizedBox(width: lado, height: lado);
  }
  return pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: urlCarnet(persona.token.trim()),
    width: lado,
    height: lado,
    drawText: false,
  );
}

/// Descarga logo y fotos una sola vez para todo el lote.
Future<CarnetRecursos> cargarRecursosCarnet({
  required CarnetMarca marca,
  required List<CarnetPersona> personas,
}) async {
  final logo = await _descargarImagen(marca.logoUrl);
  final fotos = <String, pw.ImageProvider>{};
  // En serie y no con Future.wait: una hoja de 9 carnets dispararía 9
  // descargas simultáneas desde un teléfono con datos móviles.
  for (final persona in personas) {
    if (fotos.containsKey(persona.userId)) continue;
    final img = await _descargarImagen(persona.fotoUrl);
    if (img != null) fotos[persona.userId] = img;
  }
  return CarnetRecursos(logo: logo, fotos: fotos);
}

/// Baja una imagen. Devuelve null ante cualquier problema: un carnet sin foto
/// se imprime igual, y quedarse sin carnet por una URL caída sería peor.
Future<pw.ImageProvider?> _descargarImagen(String url) async {
  final limpia = url.trim();
  if (limpia.isEmpty) return null;
  try {
    final r = await http.get(Uri.parse(limpia));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
    return pw.MemoryImage(r.bodyBytes);
  } catch (_) {
    return null;
  }
}

pw.ThemeData? _temaCache;
bool _temaResuelto = false;

/// Tipografía del carnet.
///
/// Las fuentes que trae el paquete `pdf` son Helvetica, que no tiene Unicode:
/// sin esto "Muñoz" y "Cómbita" salen partidos en el documento impreso.
///
/// La negrita usa `assets/arial_bold.ttf` SI el archivo existe. No viene en el
/// repo porque Arial Bold no es redistribuible; si falta, la negrita cae en la
/// regular y el carnet sale bien, solo con menos contraste en el cargo.
Future<pw.ThemeData?> temaCarnet() async {
  if (_temaResuelto) return _temaCache;
  _temaResuelto = true;
  try {
    final regular = await _fuente('assets/arial.ttf');
    if (regular == null) {
      _temaCache = null;
      return null;
    }
    _temaCache = pw.ThemeData.withFont(
      base: regular,
      bold: await _fuente('assets/arial_bold.ttf') ?? regular,
    );
  } catch (_) {
    _temaCache = null;
  }
  return _temaCache;
}

/// Carga una fuente solo si el archivo es realmente una fuente.
///
/// En web, pedir un asset que no existe NO falla: el servidor devuelve
/// `index.html` con estado 200, así que `rootBundle.load` entrega HTML y
/// `Font.ttf` lo intenta parsear como tipografía. El fallo no salta ahí —
/// salta después, al construir el PDF, como "Invalid typed array length", y ya
/// fuera de cualquier try. Por eso se revisa la firma del archivo antes.
Future<pw.Font?> _fuente(String ruta) async {
  try {
    final data = await rootBundle.load(ruta);
    if (data.lengthInBytes < 4) return null;
    // Firmas válidas: 0x00010000 (TrueType), 'OTTO', 'true', 'ttcf'.
    const firmas = {0x00010000, 0x4F54544F, 0x74727565, 0x74746366};
    if (!firmas.contains(data.getUint32(0))) return null;
    return pw.Font.ttf(data);
  } catch (_) {
    return null;
  }
}
