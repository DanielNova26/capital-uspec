// lib/services/rendimiento_service.dart
//
// Medición de velocidad de usuarios reales (Firebase Performance).
//
// - Web: Firebase Performance recoge solo la carga de página y las peticiones
//   de red, con el desglose por navegador, país y conexión.
// - Android/iOS: tiempo de arranque, pantallas y red.
// - [medir] agrega trazas propias para operaciones lentas de negocio.
//
// Nunca altera la app: solo corre en release, tras `runApp`, y cualquier fallo
// del SDK se ignora. No registra datos personales: los nombres de traza son
// fijos y no incluyen cédulas, correos ni identificadores de empresa.

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

class RendimientoService {
  RendimientoService._();

  static bool _activo = false;

  static Future<void> iniciar() async {
    if (!kReleaseMode) return;
    try {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
      _activo = true;
    } catch (e) {
      debugPrint('[rendimiento] no disponible: $e');
    }
  }

  /// Registra cuánto tardó la app en pintar su primer frame.
  static Future<void> primerFrame(Duration transcurrido) async {
    if (!_activo) return;
    try {
      final traza = FirebasePerformance.instance.newTrace('arranque_app');
      await traza.start();
      traza.setMetric('ms_hasta_primer_frame', transcurrido.inMilliseconds);
      await traza.stop();
    } catch (_) {}
  }

  /// Mide una operación con una traza de nombre fijo (letras, números y `_`).
  static Future<T> medir<T>(String nombre, Future<T> Function() accion) async {
    if (!_activo) return accion();
    Trace? traza;
    try {
      traza = FirebasePerformance.instance.newTrace(nombre);
      await traza.start();
    } catch (_) {
      traza = null;
    }
    try {
      return await accion();
    } finally {
      try {
        await traza?.stop();
      } catch (_) {}
    }
  }
}
