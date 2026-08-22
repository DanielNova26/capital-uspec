// lib/rutas/rutas_watermark.dart
//
// Genera la imagen de evidencia con una banda inferior de datos (sin mapa).
// Salida en JPEG (mucho más liviano que el PNG de FYC) + miniatura.
// Usa dart:ui para dibujar y el paquete `image` para codificar a JPEG.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

class RutasImagenResultado {
  final Uint8List full;
  final Uint8List thumb;

  const RutasImagenResultado({required this.full, required this.thumb});
}

Future<ui.Image> _decodeUi(Uint8List bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, completer.complete);
  return completer.future;
}

/// Rota [src] en múltiplos de 90° horneando la rotación en un bitmap nuevo.
/// Se usa para enderezar la foto ANTES de dibujar la banda, de modo que la
/// marca de agua quede siempre derecha (la banda no rota con la foto).
Future<ui.Image> _rotateUiImage(ui.Image src, int quarterTurns) async {
  final q = quarterTurns % 4;
  if (q == 0) return src;
  final sw = src.width.toDouble();
  final sh = src.height.toDouble();
  final swap = q.isOdd;
  final outW = swap ? sh : sw;
  final outH = swap ? sw : sh;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, outW, outH));
  canvas.translate(outW / 2, outH / 2);
  canvas.rotate(q * math.pi / 2);
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, sw, sh),
    ui.Rect.fromLTWH(-sw / 2, -sh / 2, sw, sh),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  return recorder.endRecording().toImage(outW.round(), outH.round());
}

/// Cuántos quarterTurns hacen falta para que la foto quede HORIZONTAL
/// (0 si ya es horizontal, 1 si viene vertical). Decodifica aplicando la
/// orientación EXIF, así el cálculo coincide con lo que verá la marca de agua.
Future<int> quarterTurnsParaHorizontal(Uint8List fotoBytes) async {
  try {
    final image = await _decodeUi(fotoBytes);
    return image.height > image.width ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

ui.Rect _fitContainRect(ui.Rect box, int imageW, int imageH) {
  final scale = math.min(box.width / imageW, box.height / imageH);
  final w = imageW * scale;
  final h = imageH * scale;
  return ui.Rect.fromLTWH(
    box.left + (box.width - w) / 2,
    box.top + (box.height - h) / 2,
    w,
    h,
  );
}

/// Dibuja [lineas] en una banda inferior agregada debajo de [fotoBytes].
/// Devuelve la imagen final y una miniatura, ambas en JPEG.
Future<RutasImagenResultado> generarEvidenciaConMarca({
  required Uint8List fotoBytes,
  required List<String> lineas,
  Uint8List? logoBytes,
  int jpgQuality = 82,
  int thumbWidth = 360,
  int quarterTurns = 0,
}) async {
  var base = await _decodeUi(fotoBytes);
  // Endereza la foto ANTES de la banda: así la marca de agua siempre queda
  // derecha (no rota con la foto).
  if (quarterTurns % 4 != 0) {
    base = await _rotateUiImage(base, quarterTurns);
  }
  final w = base.width;
  final h = base.height;
  final bandH = (h * 0.22).clamp(190.0, 320.0).toDouble();
  final outH = h + bandH.round();
  final bandTop = h.toDouble();
  final bandRealH = outH - bandTop;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, w.toDouble(), outH.toDouble()),
  );

  canvas.drawImage(base, ui.Offset.zero, ui.Paint());

  // Banda inferior legible fuera de la foto: no cubre evidencia visual.
  canvas.drawRRect(
    ui.RRect.fromRectAndCorners(
      ui.Rect.fromLTWH(0, bandTop, w.toDouble(), bandRealH),
      topLeft: const ui.Radius.circular(18),
      topRight: const ui.Radius.circular(18),
    ),
    ui.Paint()..color = const ui.Color(0xEE000000),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, bandTop, w.toDouble(), 4),
    ui.Paint()..color = const ui.Color(0xFF15803D),
  );

  final padding = (w * 0.022).clamp(14.0, 28.0).toDouble();
  double textLeft = padding;

  // Logo de la empresa a la izquierda. Se pone sobre una tarjeta clara para que
  // no desaparezca si el logo o la foto tienen fondo oscuro.
  if (logoBytes != null) {
    try {
      final logo = await _decodeUi(logoBytes);
      final logoBoxH = (bandRealH - padding * 1.35)
          .clamp(118.0, 230.0)
          .toDouble();
      final logoBoxW = (w * 0.24).clamp(180.0, 340.0).toDouble();
      final logoBox = ui.Rect.fromLTWH(
        padding,
        bandTop + (bandRealH - logoBoxH) / 2,
        logoBoxW,
        logoBoxH,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(logoBox, const ui.Radius.circular(18)),
        ui.Paint()..color = const ui.Color(0xF5FFFFFF),
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          logoBox.deflate(1),
          const ui.Radius.circular(17),
        ),
        ui.Paint()
          ..color = const ui.Color(0x22000000)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final logoDst = _fitContainRect(
        logoBox.deflate((logoBoxH * 0.11).clamp(8.0, 14.0).toDouble()),
        logo.width,
        logo.height,
      );
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        logoDst,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      textLeft = logoBox.right + padding;
    } catch (_) {}
  }

  // Texto de la banda: primera línea como título, detalles debajo.
  final title = lineas.isEmpty ? '' : lineas.first;
  final details = lineas.length <= 1 ? '' : lineas.skip(1).join('\n');
  final titleSize = (h * 0.028).clamp(22.0, 38.0).toDouble();
  final detailSize = (h * 0.018).clamp(14.0, 24.0).toDouble();
  final textWidth = math.max(80.0, w - textLeft - padding);

  final titleBuilder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: ui.TextAlign.left,
            maxLines: 2,
            ellipsis: '…',
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFFFFFFFF),
            fontSize: titleSize,
            fontWeight: ui.FontWeight.w700,
            height: 1.08,
          ),
        )
        ..addText(title);

  final titleParagraph = titleBuilder.build()
    ..layout(ui.ParagraphConstraints(width: textWidth));
  final detailsBuilder = details.isEmpty
      ? null
      : (ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: ui.TextAlign.left,
              maxLines: math.max(1, lineas.length - 1),
              ellipsis: '…',
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFFE8F5E9),
              fontSize: detailSize,
              height: 1.1,
            ),
          )
          ..addText(details));
  final detailsParagraph = detailsBuilder?.build()
    ?..layout(ui.ParagraphConstraints(width: textWidth));

  final textHeight =
      titleParagraph.height +
      (detailsParagraph == null ? 0 : 5 + detailsParagraph.height);
  final titleTop = bandTop + math.max(padding, (bandRealH - textHeight) / 2);
  canvas.drawParagraph(titleParagraph, ui.Offset(textLeft, titleTop));

  if (detailsParagraph != null) {
    canvas.drawParagraph(
      detailsParagraph,
      ui.Offset(textLeft, titleTop + titleParagraph.height + 5),
    );
  }

  final picture = recorder.endRecording();
  final outImage = await picture.toImage(w, outH);
  final pngData = await outImage.toByteData(format: ui.ImageByteFormat.png);
  if (pngData == null) {
    throw StateError('No fue posible renderizar la evidencia.');
  }

  // dart:ui solo codifica PNG; re-codificamos a JPEG con el paquete `image`.
  final decoded = img.decodeImage(pngData.buffer.asUint8List());
  if (decoded == null) {
    throw StateError('No fue posible procesar la imagen.');
  }

  final fullJpg = img.encodeJpg(decoded, quality: jpgQuality);
  final thumb = img.copyResize(decoded, width: thumbWidth);
  final thumbJpg = img.encodeJpg(thumb, quality: 70);

  return RutasImagenResultado(
    full: Uint8List.fromList(fullJpg),
    thumb: Uint8List.fromList(thumbJpg),
  );
}
