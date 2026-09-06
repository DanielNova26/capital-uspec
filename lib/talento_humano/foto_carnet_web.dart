// lib/talento_humano/foto_carnet_web.dart
//
// En el navegador no hay ML Kit. Este archivo existe para que el import
// condicional de foto_carnet.dart compile en web sin arrastrar el plugin
// nativo, que no tiene implementación para esta plataforma.
//
// La foto se sube tal cual y el carnet la usa con su fondo: quien necesite el
// recorte tiene que tomarla desde la app del teléfono.

import 'dart:typed_data';

/// Mismo fondo que la implementación nativa, para que quien lo referencie no
/// tenga que preguntarse en qué plataforma está.
const int kFondoFotoCarnet = 0xFFEEF2F7;

/// Siempre falso en web.
bool get soportaRecorteDeFondo => false;

/// Siempre `null`: "usa la foto original".
Future<Uint8List?> recortarFondoCarnet({
  required String rutaArchivo,
  required Uint8List bytes,
}) async => null;
