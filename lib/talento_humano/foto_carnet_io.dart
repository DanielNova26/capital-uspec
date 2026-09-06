// lib/talento_humano/foto_carnet_io.dart
//
// Recorte de fondo con ML Kit. Ver foto_carnet.dart para el porqué.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// Fondo sobre el que se pega a la persona.
///
/// No es blanco puro a propósito: la tarjeta impresa también es blanca, así que
/// con blanco sobre blanco la cabeza queda flotando sin que se distinga el
/// círculo de la foto. Este gris azulado muy claro marca el disco sin competir
/// con nada.
const int kFondoFotoCarnet = 0xFFEEF2F7;

/// ML Kit solo corre en Android e iOS. En Windows o en el navegador el paquete
/// existe pero el canal nativo no, así que se responde que no hay soporte en
/// vez de dejar que reviente al primer uso.
bool get soportaRecorteDeFondo {
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// Devuelve la foto recortada y encuadrada en cuadrado, lista para el círculo
/// del carnet. `null` significa "usa la original": no hay soporte, no se
/// detectó a nadie, o algo falló. Nunca es motivo para dejar sin foto.
Future<Uint8List?> recortarFondoCarnet({
  required String rutaArchivo,
  required Uint8List bytes,
}) async {
  if (!soportaRecorteDeFondo) return null;

  SelfieSegmenter? segmenter;
  try {
    // `single` y no `stream`: es una foto suelta, no un cuadro de video. En
    // modo stream ML Kit suaviza contra fotogramas anteriores que aquí no
    // existen, y la máscara sale peor.
    segmenter = SelfieSegmenter(mode: SegmenterMode.single);
    final mascara = await segmenter.processImage(
      InputImage.fromFilePath(rutaArchivo),
    );
    if (mascara == null || mascara.confidences.isEmpty) return null;

    return await compute(_componer, {
      'bytes': bytes,
      'mascara': Float32List.fromList(
        mascara.confidences.map((c) => c.toDouble()).toList(),
      ),
      'anchoMascara': mascara.width,
      'altoMascara': mascara.height,
      'fondo': kFondoFotoCarnet,
    });
  } catch (_) {
    return null;
  } finally {
    await segmenter?.close();
  }
}

/// Pega a la persona sobre el fondo plano y recorta un cuadrado centrado en
/// ella. Corre en un isolate: el recorrido pixel por pixel de una foto de
/// teléfono congelaría la interfaz durante un segundo largo.
Uint8List? _componer(Map<String, dynamic> args) {
  final origen = img.decodeImage(args['bytes'] as Uint8List);
  if (origen == null) return null;

  // Las fotos de teléfono vienen giradas por EXIF. Sin esto, la mitad de los
  // carnets salen acostados.
  final foto = img.bakeOrientation(origen);

  final mascara = args['mascara'] as Float32List;
  final anchoM = args['anchoMascara'] as int;
  final altoM = args['altoMascara'] as int;
  final fondo = img.ColorRgb8(
    (args['fondo'] as int) >> 16 & 0xFF,
    (args['fondo'] as int) >> 8 & 0xFF,
    (args['fondo'] as int) & 0xFF,
  );
  if (anchoM <= 0 || altoM <= 0) return null;

  double confianzaEn(int x, int y) {
    // La máscara puede venir a otra resolución que la foto: se muestrea por
    // proporción en vez de asumir que coinciden.
    final mx = (x * anchoM ~/ foto.width).clamp(0, anchoM - 1);
    final my = (y * altoM ~/ foto.height).clamp(0, altoM - 1);
    final i = my * anchoM + mx;
    return i >= 0 && i < mascara.length ? mascara[i] : 0.0;
  }

  final recorte = _encuadre(foto, confianzaEn);

  final salida = img.Image(width: recorte.lado, height: recorte.lado);
  for (var y = 0; y < recorte.lado; y++) {
    for (var x = 0; x < recorte.lado; x++) {
      final sx = recorte.x + x;
      final sy = recorte.y + y;
      final p = foto.getPixel(sx, sy);
      final a = confianzaEn(sx, sy).clamp(0.0, 1.0);
      // Mezcla con el fondo en vez de un corte duro: el borde del pelo tiene
      // confianzas intermedias y recortarlo a sí/no deja un contorno dentado
      // que a 54 mm impresos se ve como un recorte de tijera.
      salida.setPixelRgb(
        x,
        y,
        (p.r * a + fondo.r * (1 - a)).round(),
        (p.g * a + fondo.g * (1 - a)).round(),
        (p.b * a + fondo.b * (1 - a)).round(),
      );
    }
  }

  // 900 px de lado: sobra para imprimir el círculo de ~21 mm a 300 dpi (250 px)
  // y evita subir una foto de 12 MP a Storage por cada persona.
  final ajustada = salida.width > 900
      ? img.copyResize(salida, width: 900)
      : salida;
  return img.encodeJpg(ajustada, quality: 88);
}

/// Cuadrado que se le recorta a la foto.
///
/// Se centra horizontalmente en la persona y se sube un poco respecto a ella,
/// porque en el círculo del carnet lo que tiene que quedar es la cara, no el
/// pecho. Si no se detecta a nadie, cae al centro geométrico de la foto.
({int x, int y, int lado}) _encuadre(
  img.Image foto,
  double Function(int, int) confianzaEn,
) {
  final lado = foto.width < foto.height ? foto.width : foto.height;

  var minX = foto.width;
  var maxX = -1;
  var minY = foto.height;
  var maxY = -1;
  // Se muestrea cada 4 px: para ubicar a una persona sobra, y recorrer la foto
  // completa cuatro veces no aporta nada.
  for (var y = 0; y < foto.height; y += 4) {
    for (var x = 0; x < foto.width; x += 4) {
      if (confianzaEn(x, y) < 0.5) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < 0) {
    return (
      x: (foto.width - lado) ~/ 2,
      y: (foto.height - lado) ~/ 2,
      lado: lado,
    );
  }

  final centroX = (minX + maxX) ~/ 2;
  // Un 8% del lado por encima de la coronilla: pegar el corte a la cabeza deja
  // el carnet claustrofóbico.
  final aire = (lado * 0.08).round();
  final x = (centroX - lado ~/ 2).clamp(0, foto.width - lado);
  final y = (minY - aire).clamp(0, foto.height - lado);
  return (x: x, y: y, lado: lado);
}
