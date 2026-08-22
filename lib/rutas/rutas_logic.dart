// lib/rutas/rutas_logic.dart
//
// Lógica de negocio PURA del módulo Rutas (sin Firebase, sin Flutter).
// Aislada para poder probarla con flutter_test sin emuladores.

import 'dart:math' as math;

import 'rutas_models.dart';

class RutasLogic {
  RutasLogic._();

  // ── Fecha ────────────────────────────────────────────────────────────────

  /// Clave de día "yyyy-MM-dd" en hora local. Se usa como campo `fecha` y para
  /// componer el docId determinístico de una evidencia.
  static String fechaKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Solo la fecha (sin hora), para diferencias en días completos.
  static DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── Menú: ciclo rotativo de 21 días ───────────────────────────────────────

  /// Número de menú (1..kMenuCount) para [fecha] dado el [cicloFechaBase]
  /// (la fecha del "Menú 1"). El doble módulo evita negativos si la base
  /// es futura. Misma fórmula que debe usar la Cloud Function.
  static int menuNumeroParaFecha(DateTime fecha, DateTime cicloFechaBase) {
    final dias = _soloFecha(
      fecha,
    ).difference(_soloFecha(cicloFechaBase)).inDays;
    final idx = ((dias % kMenuCount) + kMenuCount) % kMenuCount;
    return idx + 1;
  }

  // ── Tiempo de comida por hora ──────────────────────────────────────────────

  /// Convierte "HH:mm" a minutos desde medianoche. -1 si es inválido.
  static int _minutosDeHora(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }

  /// Comida cuya ventana contiene [ahora]. Si ninguna la contiene, devuelve la
  /// de inicio más cercano (para que el conductor casi nunca tenga que cambiarla).
  static String comidaPorHora(DateTime ahora, RutaConfigDoc cfg) {
    final minutosAhora = ahora.hour * 60 + ahora.minute;

    for (final comida in kComidasOrden) {
      final v = cfg.ventanaDe(comida);
      final desde = _minutosDeHora(v.desde);
      final hasta = _minutosDeHora(v.hasta);
      if (desde < 0 || hasta < 0) continue;
      if (minutosAhora >= desde && minutosAhora <= hasta) return comida;
    }

    // Fallback: la comida con el "desde" más cercano a la hora actual.
    String mejor = kComidasOrden.first;
    int mejorDist = 1 << 30;
    for (final comida in kComidasOrden) {
      final desde = _minutosDeHora(cfg.ventanaDe(comida).desde);
      if (desde < 0) continue;
      final dist = (minutosAhora - desde).abs();
      if (dist < mejorDist) {
        mejorDist = dist;
        mejor = comida;
      }
    }
    return mejor;
  }

  // ── Secuencia de comidas (por establecimiento) ────────────────────────────

  /// Comida inmediatamente anterior en el orden, o null si es la primera.
  static String? comidaAnterior(String comida) {
    final i = kComidasOrden.indexOf(comida);
    if (i <= 0) return null;
    return kComidasOrden[i - 1];
  }

  /// ¿Se puede tomar [comida] en un establecimiento dado el conjunto de comidas
  /// YA registradas y NO rechazadas de ese mismo establecimiento/día?
  ///
  /// Regla: solo se permite una foto no rechazada por comida. La comida previa
  /// debe existir y no estar rechazada. Si una comida fue rechazada, deja de
  /// estar en este conjunto y el conductor puede repetirla.
  static bool puedeTomarComida({
    required String comida,
    required Set<String> comidasNoRechazadasDelPunto,
  }) {
    if (comidasNoRechazadasDelPunto.contains(comida)) return false;
    final previa = comidaAnterior(comida);
    if (previa == null) return true; // desayuno: siempre permitido
    return comidasNoRechazadasDelPunto.contains(previa);
  }

  /// Mensaje de bloqueo cuando [puedeTomarComida] es false (para mostrar al
  /// conductor). Vacío si está permitido.
  static String motivoBloqueoComida({
    required String comida,
    required Set<String> comidasNoRechazadasDelPunto,
  }) {
    if (puedeTomarComida(
      comida: comida,
      comidasNoRechazadasDelPunto: comidasNoRechazadasDelPunto,
    )) {
      return '';
    }
    if (comidasNoRechazadasDelPunto.contains(comida)) {
      return 'Ya existe una foto de "$comida" para este establecimiento. Solo se puede repetir si Calidad la rechaza.';
    }
    final previa = comidaAnterior(comida);
    return 'Primero registra y deja aprobada la foto de "$previa" en este establecimiento.';
  }

  // ── Distancia (Haversine) ──────────────────────────────────────────────────

  static const double _radioTierraM = 6371000.0;

  /// Distancia en metros entre dos coordenadas. -1 si falta alguna.
  static double distanciaMetros(
    double? lat1,
    double? lng1,
    double? lat2,
    double? lng2,
  ) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return -1;
    }
    final dLat = _gradosARadianes(lat2 - lat1);
    final dLng = _gradosARadianes(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_gradosARadianes(lat1)) *
            math.cos(_gradosARadianes(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _radioTierraM * c;
  }

  static double _gradosARadianes(double grados) => grados * math.pi / 180.0;

  /// Índice del stop más cercano a (lat,lng), o -1 si no hay candidatos con geo.
  static int indiceStopMasCercano(
    List<RutaStop> stops,
    double? lat,
    double? lng,
  ) {
    if (lat == null || lng == null) return -1;
    int mejor = -1;
    double mejorDist = double.infinity;
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      if (!s.geocodificada) continue;
      final d = distanciaMetros(lat, lng, s.lat, s.lng);
      if (d >= 0 && d < mejorDist) {
        mejorDist = d;
        mejor = i;
      }
    }
    return mejor;
  }

  // ── DocId determinístico de evidencia ──────────────────────────────────────

  static String _slug(String s) {
    final base = s.trim().isEmpty ? 'NA' : s.trim();
    return base.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  }

  /// Una evidencia por (empresa, ruta, fecha, parada, comida). Determinístico:
  /// re-tomar la foto reemplaza el documento y refuerza la secuencia.
  static String evidenciaDocId({
    required String empresaId,
    required String rutaId,
    required String fecha,
    required String paradaNombre,
    required String comida,
  }) {
    return [
      empresaId,
      rutaId,
      fecha,
      _slug(paradaNombre),
      _slug(comida),
    ].join('__');
  }

  /// Ruta de Storage organizada (compatible con interventoría):
  /// rutas/{empresaId}/{yyyy}/{MM}/{dd}/{PARADA}/{COMIDA}/{timestamp}.jpg
  static String storagePath({
    required String empresaId,
    required DateTime fecha,
    required String paradaNombre,
    required String comida,
    required int timestampMs,
    String ext = 'jpg',
  }) {
    final y = fecha.year.toString().padLeft(4, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final d = fecha.day.toString().padLeft(2, '0');
    return 'rutas/$empresaId/$y/$m/$d/${_slug(paradaNombre)}/${_slug(comida)}/$timestampMs.$ext';
  }
}
