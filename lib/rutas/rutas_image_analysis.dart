// lib/rutas/rutas_image_analysis.dart
//
// Análisis heurístico ON-DEVICE de la foto de evidencia (gratis, sin nube).
// Se ejecuta en un isolate (vía `compute`) ANTES de subir, sobre la foto cruda,
// mientras el conductor mira la vista previa: NO agrega tiempo de red, solo un
// chequeo local de fracciones de segundo.
//
// Detecta señales típicas de "foto inadecuada":
//   - oscura / quemada  → brillo promedio fuera de rango
//   - plana             → poca variación (tapada, negra o un solo color)
//   - borrosa           → baja varianza de Laplaciano (poco enfoque)
//
// Umbrales conservadores (constantes abajo) para no molestar con falsos avisos.
// NO valida orientación "de cabeza": eso la geometría no lo puede saber
// (ver rutas_watermark.quarterTurnsParaHorizontal + botón "Rotar").

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Umbrales tunables (0..255 para brillo/variación; Laplaciano en escala 256px).
const double _kBrilloMin = 45; // < => oscura
const double _kBrilloMax = 225; // > => quemada
const double _kVariacionMin = 12; // < => plana (un solo color)
const double _kNitidezMin = 55; // < => borrosa (varianza de Laplaciano)

/// Devuelve las alertas de calidad de la foto (lista vacía = se ve bien).
/// Pensada para `compute(analizarCalidadFoto, bytes)`.
List<String> analizarCalidadFoto(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const <String>[];

    // Orientación EXIF + reducción para velocidad; a escala de grises.
    final baked = img.bakeOrientation(decoded);
    final small = img.copyResize(baked, width: 256);
    final gray = img.grayscale(small);

    final w = gray.width;
    final h = gray.height;
    if (w < 8 || h < 8) return const <String>[];

    final lum = Float64List(w * h);
    double sum = 0;
    double sumSq = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        lum[y * w + x] = v;
        sum += v;
        sumSq += v * v;
      }
    }
    final n = w * h;
    final mean = sum / n;
    final varLum = (sumSq / n) - (mean * mean);
    final std = varLum <= 0 ? 0.0 : math.sqrt(varLum);

    // Varianza del Laplaciano (proxy de enfoque).
    double lapSum = 0;
    double lapSumSq = 0;
    int lapN = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = lum[y * w + x];
        final lap = 4 * c -
            lum[(y - 1) * w + x] -
            lum[(y + 1) * w + x] -
            lum[y * w + x - 1] -
            lum[y * w + x + 1];
        lapSum += lap;
        lapSumSq += lap * lap;
        lapN++;
      }
    }
    final lapMean = lapN == 0 ? 0.0 : lapSum / lapN;
    final lapVar = lapN == 0 ? 0.0 : (lapSumSq / lapN) - (lapMean * lapMean);

    final alertas = <String>[];
    if (mean < _kBrilloMin) {
      alertas.add('oscura');
    } else if (mean > _kBrilloMax) {
      alertas.add('quemada');
    }
    if (std < _kVariacionMin) alertas.add('plana');
    if (lapVar < _kNitidezMin) alertas.add('borrosa');
    return alertas;
  } catch (_) {
    return const <String>[];
  }
}
