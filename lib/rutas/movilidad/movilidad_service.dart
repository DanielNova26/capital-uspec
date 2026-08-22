// lib/rutas/movilidad/movilidad_service.dart
//
// Servicio del ESTUDIO DE MOVILIDAD: lectura/escritura de configuración y
// horarios, consulta de mediciones (las escribe solo el backend), disparo de
// mediciones manuales vía callable, estadísticas y exportes (CSV/Excel/PDF).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../rutas_models.dart';
import 'movilidad_models.dart';

class MovilidadService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  // ── Configuración ──────────────────────────────────────────────────────────

  Stream<MovConfigDoc> configStream(String empresaId) => _db
      .collection(kMovColConfig)
      .doc(empresaId)
      .snapshots()
      .map(
        (d) => d.exists
            ? MovConfigDoc.fromMap(d.id, d.data()!)
            : MovConfigDoc.defaults(empresaId),
      );

  Future<MovConfigDoc> cargarConfig(String empresaId) async {
    final d = await _db.collection(kMovColConfig).doc(empresaId).get();
    return d.exists
        ? MovConfigDoc.fromMap(d.id, d.data()!)
        : MovConfigDoc.defaults(empresaId);
  }

  Future<void> guardarConfig(MovConfigDoc config) => _db
      .collection(kMovColConfig)
      .doc(config.empresaId)
      .set(config.toMap(), SetOptions(merge: true));

  // ── Horarios (measurement_schedules) ───────────────────────────────────────

  Stream<List<MovHorarioDoc>> horariosStream(String empresaId) => _db
      .collection(kMovColHorarios)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => MovHorarioDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          // Orden del estudio: sáb, dom, lun, mar…, luego por hora.
          int pos(int w) {
            final i = kMovDiasEstudio.indexOf(w);
            return i >= 0 ? i : kMovDiasEstudio.length + w;
          }

          final byDay = pos(a.weekday).compareTo(pos(b.weekday));
          if (byDay != 0) return byDay;
          return a.minutosDia.compareTo(b.minutosDia);
        });
        return list;
      });

  Future<void> guardarHorario(MovHorarioDoc h) async {
    if (h.id.isEmpty) {
      await _db.collection(kMovColHorarios).add(h.toMap());
    } else {
      await _db
          .collection(kMovColHorarios)
          .doc(h.id)
          .set(h.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> eliminarHorario(String id) =>
      _db.collection(kMovColHorarios).doc(id).delete();

  /// Crea los horarios sugeridos del estudio (sáb/dom/lun/mar ×
  /// 06:00, 07:00, 09:30, 12:00, 17:00) y asegura el doc de configuración.
  /// No duplica los que ya existan (mismo día + hora).
  ///
  /// Devuelve cuántos creó y cuántos había antes: si informa que ya existían
  /// pero la pantalla no los lista, el problema es de LECTURA, no de
  /// escritura.
  Future<({int creados, int yaExistian})> crearHorariosSugeridos(
    String empresaId,
  ) async {
    if (empresaId.trim().isEmpty) {
      throw ArgumentError(
        'No hay empresa activa seleccionada; no se pueden crear horarios.',
      );
    }
    final existentes = await _db
        .collection(kMovColHorarios)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final claves = existentes.docs
        .map((d) => '${d.data()['weekday']}_${d.data()['hora']}')
        .toSet();

    final batch = _db.batch();
    var creados = 0;
    for (final dia in kMovDiasEstudio) {
      for (final e in kMovHorasSugeridas.entries) {
        if (claves.contains('${dia}_${e.key}')) continue;
        final esFinDeSemana = dia >= 6;
        final h = MovHorarioDoc(
          empresaId: empresaId,
          weekday: dia,
          hora: e.key,
          escenario: esFinDeSemana ? kMovEscFinSemana : e.value,
          createdAt: Timestamp.now(),
        );
        batch.set(_db.collection(kMovColHorarios).doc(), h.toMap());
        creados++;
      }
    }
    // Asegura la configuración para que el cron pueda correr.
    final cfgRef = _db.collection(kMovColConfig).doc(empresaId);
    final cfg = await cfgRef.get();
    if (!cfg.exists) {
      batch.set(cfgRef, MovConfigDoc.defaults(empresaId).toMap());
    }
    if (creados > 0 || !cfg.exists) await batch.commit();
    return (creados: creados, yaExistian: existentes.docs.length);
  }

  /// Próxima medición programada según los horarios activos (hora local).
  static ({DateTime cuando, MovHorarioDoc horario})? proximaMedicion(
    List<MovHorarioDoc> horarios, {
    DateTime? ahora,
  }) {
    final now = ahora ?? DateTime.now();
    ({DateTime cuando, MovHorarioDoc horario})? mejor;
    for (final h in horarios.where((h) => h.activo)) {
      final p = h.hora.split(':');
      if (p.length != 2) continue;
      final hh = int.tryParse(p[0]) ?? 0;
      final mm = int.tryParse(p[1]) ?? 0;
      for (var d = 0; d < 8; d++) {
        final dia = DateTime(now.year, now.month, now.day + d, hh, mm);
        if (dia.weekday != h.weekday) continue;
        if (!dia.isAfter(now)) continue;
        if (mejor == null || dia.isBefore(mejor.cuando)) {
          mejor = (cuando: dia, horario: h);
        }
        break;
      }
    }
    return mejor;
  }

  // ── Corridas ───────────────────────────────────────────────────────────────

  Stream<List<MovRunDoc>> runsStream(String empresaId, {int limit = 30}) => _db
      .collection(kMovColRuns)
      .where('empresaId', isEqualTo: empresaId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => MovRunDoc.fromMap(d.id, d.data())).toList());

  // ── Mediciones (solo lectura desde la app) ─────────────────────────────────

  Stream<List<MovMedicionDoc>> medicionesStream(
    String empresaId, {
    required DateTime desde,
    required DateTime hasta,
    int limit = 6000,
  }) => _db
      .collection(kMovColMediciones)
      .where('empresaId', isEqualTo: empresaId)
      .where(
        'fechaHora',
        isGreaterThanOrEqualTo: Timestamp.fromDate(desde),
      )
      .where('fechaHora', isLessThan: Timestamp.fromDate(hasta))
      .orderBy('fechaHora', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => MovMedicionDoc.fromMap(d.id, d.data()))
            .toList(),
      );

  Future<List<MovMedicionDoc>> historialPunto(
    String empresaId,
    String puntoId, {
    int limit = 200,
  }) async {
    final s = await _db
        .collection(kMovColMediciones)
        .where('empresaId', isEqualTo: empresaId)
        .where('puntoId', isEqualTo: puntoId)
        .orderBy('fechaHora', descending: true)
        .limit(limit)
        .get();
    return s.docs.map((d) => MovMedicionDoc.fromMap(d.id, d.data())).toList();
  }

  // ── Puntos (maestro TBL_RUTAS_ESTABLECIMIENTOS) ────────────────────────────

  Future<List<RutaEstablecimientoDoc>> puntosActivos(String empresaId) async {
    final s = await _db
        .collection('TBL_RUTAS_ESTABLECIMIENTOS')
        .where('empresaId', isEqualTo: empresaId)
        .where('activo', isEqualTo: true)
        .get();
    final list = s.docs
        .map((d) => RutaEstablecimientoDoc.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) => a.nombre.compareTo(b.nombre));
    return list;
  }

  /// Normaliza nombres para comparar rutas y puntos sin depender de
  /// tildes ni mayúsculas.
  static String normalizarNombre(String v) => v
      .trim()
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ñ', 'N')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Sincroniza el maestro de establecimientos con la tabla corregida del
  /// estudio (KML/CSV): actualiza coordenadas/dirección de los existentes
  /// (match por nombre) y crea los que falten. El Centro de Operaciones no se
  /// crea como establecimiento (es el origen, vive en la configuración).
  Future<({int creados, int actualizados})> sincronizarPuntosCsv(
    String empresaId,
  ) async {
    final s = await _db
        .collection('TBL_RUTAS_ESTABLECIMIENTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final porNombre = <String, DocumentSnapshot<Map<String, dynamic>>>{
      for (final d in s.docs) normalizarNombre((d.data()['nombre'] ?? '').toString()): d,
    };

    final batch = _db.batch();
    var creados = 0;
    var actualizados = 0;
    for (final seed in kMovPuntosSeed) {
      final clave = normalizarNombre(seed.nombre);
      final datos = {
        'empresaId': empresaId,
        'nombre': seed.nombre,
        'direccionLimpia': seed.direccion,
        'lat': seed.lat,
        'lng': seed.lng,
        'distanciaCentroKm': seed.distanciaKm,
        'rangoDistancia': seed.rango,
        'activo': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existente = porNombre[clave];
      if (existente != null) {
        batch.set(existente.reference, datos, SetOptions(merge: true));
        actualizados++;
      } else {
        batch.set(_db.collection('TBL_RUTAS_ESTABLECIMIENTOS').doc(), {
          ...datos,
          'direccionRaw': seed.direccion,
          'createdAt': Timestamp.now(),
        });
        creados++;
      }
    }
    await batch.commit();
    return (creados: creados, actualizados: actualizados);
  }

  // ── Reset de mediciones (destructivo) ──────────────────────────────────────

  /// Borra por lotes todos los documentos de [coleccion] de una empresa.
  /// Pagina para no cargar colecciones grandes de una sola vez.
  Future<int> _borrarPorEmpresa(String coleccion, String empresaId) async {
    var total = 0;
    while (true) {
      final snap = await _db
          .collection(coleccion)
          .where('empresaId', isEqualTo: empresaId)
          .limit(400)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      total += snap.docs.length;
      if (snap.docs.length < 400) break;
    }
    return total;
  }

  /// Borra las mediciones indicadas por id. Se usa desde la tabla para
  /// depurar registros puntuales (una corrida de prueba, un punto mal
  /// medido) sin tumbar todo el histórico.
  Future<int> eliminarMediciones(Iterable<String> ids) async {
    final lista = ids.where((e) => e.trim().isNotEmpty).toList();
    if (lista.isEmpty) return 0;
    var borradas = 0;
    for (var i = 0; i < lista.length; i += 400) {
      final lote = lista.skip(i).take(400).toList();
      final batch = _db.batch();
      for (final id in lote) {
        batch.delete(_db.collection(kMovColMediciones).doc(id));
      }
      await batch.commit();
      borradas += lote.length;
    }
    return borradas;
  }

  /// Reset profundo del estudio: borra el histórico de mediciones y la
  /// bitácora de corridas de la empresa. NO toca la configuración, los
  /// horarios ni el maestro de establecimientos, para que el estudio pueda
  /// volver a arrancar de inmediato.
  ///
  /// Es irreversible: las mediciones son evidencia y no se pueden reconstruir
  /// (dependen del tráfico que había en ese instante).
  Future<({int mediciones, int corridas})> resetMediciones(
    String empresaId,
  ) async {
    final eid = empresaId.trim();
    if (eid.isEmpty) return (mediciones: 0, corridas: 0);
    final mediciones = await _borrarPorEmpresa(kMovColMediciones, eid);
    final corridas = await _borrarPorEmpresa(kMovColRuns, eid);
    return (mediciones: mediciones, corridas: corridas);
  }

  // ── Rutas del estudio (secuencia real de entrega) ──────────────────────────

  /// Crea o actualiza en `TBL_RUTAS` las 10 rutas del estudio con su
  /// secuencia de paradas, tomando las coordenadas del maestro de
  /// establecimientos. Es lo que permite medir tramo a tramo en vez de
  /// viajes independientes desde la planta.
  Future<({int rutas, int paradas, List<String> faltantes})>
      sincronizarRutasEstudio(String empresaId) async {
    if (empresaId.trim().isEmpty) {
      throw ArgumentError('No hay empresa activa seleccionada.');
    }
    final establecimientos = await puntosActivos(empresaId);
    final porNombre = <String, RutaEstablecimientoDoc>{
      for (final e in establecimientos) normalizarNombre(e.nombre): e,
    };

    final existentes = await _db
        .collection('TBL_RUTAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final porCodigo = <String, DocumentReference>{
      for (final d in existentes.docs)
        normalizarNombre((d.data()['codigo'] ?? '').toString()): d.reference,
    };

    final faltantes = <String>[];
    final batch = _db.batch();
    var rutas = 0;
    var paradas = 0;

    for (final entrada in kMovRutasEstudio.entries) {
      final stops = <Map<String, dynamic>>[];
      var orden = 0;
      for (final nombre in entrada.value) {
        final est = porNombre[normalizarNombre(nombre)];
        if (est == null) {
          faltantes.add('${entrada.key}: $nombre');
          continue;
        }
        stops.add({
          'establecimientoId': est.id,
          'nombre': est.nombre,
          'direccionRaw': est.direccionRaw,
          'direccionLimpia': est.direccionLimpia,
          'lat': est.lat,
          'lng': est.lng,
          'orden': orden++,
          'distanciaCentroKm': est.distanciaCentroKm,
          'rangoDistancia': est.rangoDistancia,
        });
      }
      if (stops.isEmpty) continue;

      final datos = {
        'empresaId': empresaId,
        'codigo': entrada.key,
        'stops': stops,
        'activa': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final ref = porCodigo[normalizarNombre(entrada.key)];
      if (ref != null) {
        batch.set(ref, datos, SetOptions(merge: true));
      } else {
        batch.set(_db.collection('TBL_RUTAS').doc(), {
          ...datos,
          'createdAt': Timestamp.now(),
        });
      }
      rutas++;
      paradas += stops.length;
    }
    await batch.commit();
    return (rutas: rutas, paradas: paradas, faltantes: faltantes);
  }

  /// ¿La secuencia guardada coincide con la definida para el estudio?
  ///
  /// Si no coincide, las mediciones de esa ruta NO son comparables entre sí
  /// (el acumulado depende del orden), así que conviene verlo antes de
  /// generar informes.
  static ({bool coincide, String esperado, String actual}) compararConEstudio(
    String codigo,
    List<String> paradas,
  ) {
    final esperadas = kMovRutasEstudio[codigo];
    if (esperadas == null) {
      return (
        coincide: false,
        esperado: 'no forma parte del estudio',
        actual: paradas.join(' → '),
      );
    }
    final a = esperadas.map(normalizarNombre).join('|');
    final b = paradas.map(normalizarNombre).join('|');
    return (
      coincide: a == b,
      esperado: esperadas.join(' → '),
      actual: paradas.join(' → '),
    );
  }

  /// Rutas activas con sus paradas, para mostrar la secuencia en la app.
  Future<List<({String codigo, List<String> paradas})>> rutasConfiguradas(
    String empresaId,
  ) async {
    final s = await _db
        .collection('TBL_RUTAS')
        .where('empresaId', isEqualTo: empresaId)
        .where('activa', isEqualTo: true)
        .get();
    final out = s.docs.map((d) {
      final m = d.data();
      final stops = ((m['stops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort(
          (a, b) => ((a['orden'] as num?) ?? 0)
              .compareTo((b['orden'] as num?) ?? 0),
        );
      return (
        codigo: (m['codigo'] ?? d.id).toString(),
        paradas: stops.map((e) => (e['nombre'] ?? '').toString()).toList(),
      );
    }).toList();
    out.sort((a, b) {
      int n(String c) =>
          int.tryParse(c.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
      return n(a.codigo).compareTo(n(b.codigo));
    });
    return out;
  }

  // ── Medición manual (callable) ─────────────────────────────────────────────

  Future<Map<String, dynamic>> medirAhora({
    required String empresaId,
    required String cedula,
    String? puntoId,
  }) async {
    final res = await _functions
        .httpsCallable(
          'rutasMovilidadMedirAhora',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
        )
        .call<dynamic>({
      'empresaId': empresaId,
      'cedula': cedula,
      if (puntoId != null && puntoId.isNotEmpty) 'puntoId': puntoId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Estadísticas compartidas por el panel y los reportes
// ══════════════════════════════════════════════════════════════════════════════

class MovPuntoResumen {
  final String puntoId;
  final String nombre;
  final String direccion;
  final int n;

  /// Promedio del tiempo TOTAL en ruta al llegar (desde la planta).
  /// Es el que define el riesgo del punto.
  final double promMin;
  final double maxMin;
  final double minMin;

  /// Promedio del último tramo aislado (referencia operativa).
  final double promTramoMin;
  final double promDemoraMin;
  final int alertas;

  /// Ruta y posición del punto en la secuencia de entrega.
  final String rutaCodigo;
  final int ordenParada;
  final int totalParadasRuta;

  final MovMedicionDoc ultima;

  const MovPuntoResumen({
    required this.puntoId,
    required this.nombre,
    required this.direccion,
    required this.n,
    required this.promMin,
    required this.maxMin,
    required this.minMin,
    required this.promTramoMin,
    required this.promDemoraMin,
    required this.alertas,
    required this.rutaCodigo,
    required this.ordenParada,
    required this.totalParadasRuta,
    required this.ultima,
  });

  String get posicionTexto => rutaCodigo.isEmpty
      ? ''
      : '$rutaCodigo · parada $ordenParada de $totalParadasRuta';

  String get riesgoProm => movClasificarRiesgo(promMin);
  String get riesgoPeor => movClasificarRiesgo(maxMin);
}

/// Una fila del comparativo entre proveedores de API para un mismo punto.
class MovComparativoPunto {
  final String nombre;
  final String fuenteA;
  final String fuenteB;
  final double minA;
  final double minB;
  final int n;

  const MovComparativoPunto({
    required this.nombre,
    required this.fuenteA,
    required this.fuenteB,
    required this.minA,
    required this.minB,
    required this.n,
  });

  /// Positiva = la fuente B estima MÁS tiempo que la A.
  double get diferencia => minB - minA;
  double get diferenciaAbs => diferencia.abs();

  double get diferenciaPct => minA == 0 ? 0 : (diferencia / minA) * 100;

  /// Promedio de ambas fuentes: el valor más defendible cuando dos
  /// proveedores independientes coinciden en el orden de magnitud.
  double get promedio => (minA + minB) / 2;
}

class MovStats {
  /// Solo mediciones exitosas.
  static List<MovMedicionDoc> okDe(List<MovMedicionDoc> ms) =>
      ms.where((m) => m.ok).toList();

  /// Valor de referencia del estudio: el tiempo TOTAL en ruta al llegar al
  /// punto, no el del último tramo. Las rutas van encadenadas, así que lo
  /// que expone el alimento es el acumulado desde la planta.
  static double valor(MovMedicionDoc m) => m.minutosEnRutaAlLlegar;

  static double? promedio(Iterable<double> valores) {
    final list = valores.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  /// Resumen por punto (ordenado de mayor a menor tiempo promedio).
  static List<MovPuntoResumen> porPunto(List<MovMedicionDoc> ms) {
    final ok = okDe(ms);
    final grupos = <String, List<MovMedicionDoc>>{};
    for (final m in ok) {
      grupos.putIfAbsent(m.puntoId.isEmpty ? m.puntoNombre : m.puntoId, () => [])
          .add(m);
    }
    final out = <MovPuntoResumen>[];
    for (final g in grupos.values) {
      g.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      final tiempos = g.map(valor).toList();
      out.add(
        MovPuntoResumen(
          puntoId: g.first.puntoId,
          nombre: g.first.puntoNombre,
          direccion: g.first.puntoDireccion,
          n: g.length,
          promMin: promedio(tiempos) ?? 0,
          maxMin: tiempos.reduce((a, b) => a > b ? a : b),
          minMin: tiempos.reduce((a, b) => a < b ? a : b),
          promTramoMin:
              promedio(g.map((m) => m.duracionTraficoMin)) ?? 0,
          promDemoraMin:
              promedio(g.map((m) => m.demoraTraficoMin ?? 0)) ?? 0,
          alertas: g.where((m) => m.alerta).length,
          rutaCodigo: g.first.rutaCodigo,
          ordenParada: g.first.ordenParada,
          totalParadasRuta: g.first.totalParadasRuta,
          ultima: g.first,
        ),
      );
    }
    out.sort((a, b) => b.promMin.compareTo(a.promMin));
    return out;
  }

  /// escenario → promedio de minutos.
  static Map<String, double> promedioPorEscenario(List<MovMedicionDoc> ms) {
    final out = <String, double>{};
    for (final esc in kMovEscenarios) {
      final p = promedio(
        okDe(ms)
            .where((m) => m.escenario == esc)
            .map(valor),
      );
      if (p != null) out[esc] = p;
    }
    return out;
  }

  /// weekday (1-7) → promedio de minutos.
  static Map<int, double> promedioPorDia(List<MovMedicionDoc> ms) {
    final out = <int, double>{};
    for (var w = 1; w <= 7; w++) {
      final p = promedio(
        okDe(ms).where((m) => m.weekday == w).map(valor),
      );
      if (p != null) out[w] = p;
    }
    return out;
  }

  /// Ruta → promedio del tiempo en ruta al CERRAR el recorrido (la última
  /// parada). Es el indicador que decide si la ruta es operable.
  static Map<String, double> cierrePorRuta(List<MovMedicionDoc> ms) {
    final cierres = <String, List<double>>{};
    for (final m in okDe(ms)) {
      if (m.rutaCodigo.isEmpty) continue;
      if (m.ordenParada != m.totalParadasRuta) continue;
      cierres.putIfAbsent(m.rutaCodigo, () => []).add(valor(m));
    }
    final out = <String, double>{};
    final claves = cierres.keys.toList()
      ..sort((a, b) {
        int n(String c) =>
            int.tryParse(c.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
        return n(a).compareTo(n(b));
      });
    for (final k in claves) {
      final p = promedio(cierres[k]!);
      if (p != null) out[k] = p;
    }
    return out;
  }

  /// hora "HH:mm" → promedio de minutos.
  static Map<String, double> promedioPorHora(List<MovMedicionDoc> ms) {
    final horas = okDe(ms).map((m) => m.hora).toSet().toList()..sort();
    final out = <String, double>{};
    for (final h in horas) {
      final p = promedio(
        okDe(ms).where((m) => m.hora == h).map(valor),
      );
      if (p != null) out[h] = p;
    }
    return out;
  }

  /// Fuentes distintas presentes en el set de mediciones.
  static List<String> fuentesPresentes(List<MovMedicionDoc> ms) {
    final s = okDe(ms).map((m) => m.fuente).where((f) => f.isNotEmpty).toSet();
    final list = s.toList()..sort();
    return list;
  }

  /// Comparativo entre proveedores: por punto, el promedio de cada fuente y
  /// la diferencia entre ambas. Solo incluye puntos medidos por las DOS.
  static List<MovComparativoPunto> comparativoFuentes(
    List<MovMedicionDoc> ms,
  ) {
    final fuentes = fuentesPresentes(ms);
    if (fuentes.length < 2) return const [];
    final a = fuentes[0];
    final b = fuentes[1];

    final porPunto = <String, List<MovMedicionDoc>>{};
    for (final m in okDe(ms)) {
      porPunto
          .putIfAbsent(m.puntoId.isEmpty ? m.puntoNombre : m.puntoId, () => [])
          .add(m);
    }

    final out = <MovComparativoPunto>[];
    porPunto.forEach((_, lista) {
      final promA = promedio(
        lista.where((m) => m.fuente == a).map(MovStats.valor),
      );
      final promB = promedio(
        lista.where((m) => m.fuente == b).map(MovStats.valor),
      );
      if (promA == null || promB == null) return;
      out.add(
        MovComparativoPunto(
          nombre: lista.first.puntoNombre,
          fuenteA: a,
          fuenteB: b,
          minA: promA,
          minB: promB,
          n: lista.length,
        ),
      );
    });
    out.sort((x, y) => y.diferenciaAbs.compareTo(x.diferenciaAbs));
    return out;
  }

  /// Comparación pico (mañana+tarde) vs valle. null si falta alguno.
  static ({double pico, double valle, double diferenciaPct})? picoVsValle(
    List<MovMedicionDoc> ms,
  ) {
    final pico = promedio(
      okDe(ms)
          .where(
            (m) =>
                m.escenario == kMovEscPicoManana ||
                m.escenario == kMovEscPicoTarde,
          )
          .map(valor),
    );
    final valle = promedio(
      okDe(ms)
          .where((m) => m.escenario == kMovEscValle)
          .map(valor),
    );
    if (pico == null || valle == null || valle == 0) return null;
    return (
      pico: pico,
      valle: valle,
      diferenciaPct: ((pico - valle) / valle) * 100,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Exportes: CSV, Excel y PDF
// ══════════════════════════════════════════════════════════════════════════════

class MovilidadExport {
  static final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy HH:mm');

  static String _n1(double? v) => v == null ? '' : v.toStringAsFixed(1);

  static List<String> _filaMedicion(MovMedicionDoc m) => [
        m.rutaCodigo,
        '${m.ordenParada}/${m.totalParadasRuta}',
        m.tramoDesdeNombre,
        m.puntoNombre,
        m.puntoDireccion,
        m.fecha,
        m.hora,
        m.horaSalidaTramoTxt,
        m.horaLlegadaTxt,
        movComidaLabel(m.comida),
        m.ventanaHasta,
        m.dentroDeVentana == null
            ? ''
            : (m.dentroDeVentana! ? 'A TIEMPO' : 'TARDE'),
        m.minutosFueraVentana > 0 ? '${m.minutosFueraVentana}' : '',
        m.weekdayNombre.isNotEmpty
            ? m.weekdayNombre
            : movWeekdayNombre(m.weekday),
        movEscenarioLabel(m.escenario),
        m.ok ? m.distanciaKm.toStringAsFixed(2) : '',
        m.ok ? _n1(m.minutosEnRutaAlLlegar) : '',
        m.ok ? _n1(m.distanciaAcumuladaKm) : '',
        m.ok ? _n1(m.duracionTraficoMin) : '',
        _n1(m.duracionSinTraficoMin),
        m.ok ? _n1(m.diferenciaCalculada) : '',
        _n1(m.demoraTraficoMin),
        m.rutaPrincipal,
        m.rutaAlterna,
        movTraficoLabel(m.estadoTrafico),
        '${m.obrasOficiales.total}',
        m.obrasOficiales.detalle.map((o) => o.radicadoSdm).join(' | '),
        m.obrasOficiales.detalle.map((o) => o.resumen).join(' | '),
        '${m.incidentes.obras}',
        '${m.incidentes.cierres}',
        '${m.incidentes.total}',
        m.incidentes.detalle.map((i) => i.resumen).join(' | '),
        movRiesgoLabel(m.riesgo),
        m.alerta ? 'SÍ' : '',
        movFuenteMedicionLabel(m.fuente),
        m.tipo,
        m.creadoPor,
        m.ok ? m.observaciones : 'FALLIDA: ${m.errorMsg}',
      ];

  static const List<String> _cabecera = [
    'Ruta',
    'Parada N°',
    'Tramo desde',
    'Punto',
    'Dirección',
    'Fecha',
    'Hora de la franja',
    'Salida del tramo',
    'Llegada a la parada',
    'Comida',
    'Cierre de ventana',
    'Cumple ventana',
    'Minutos de retraso',
    'Día',
    'Escenario',
    'Distancia del tramo (km)',
    'TIEMPO EN RUTA al llegar (min)',
    'Distancia acumulada (km)',
    'Tiempo del tramo con tráfico (min)',
    'Tiempo esperado del tramo (min)',
    'Diferencia actual - esperado (min)',
    'Demora por tráfico (min)',
    'Ruta principal',
    'Ruta alterna',
    'Estado tráfico',
    'Obras oficiales PMT (SDM)',
    'Radicados SDM',
    'Detalle obras oficiales',
    'Obras por tráfico en vivo',
    'Cierres en la ruta',
    'Incidentes totales',
    'Detalle de incidentes',
    'Riesgo',
    'Alerta',
    'Fuente',
    'Tipo',
    'Generado por',
    'Observaciones',
  ];

  // ── CSV ────────────────────────────────────────────────────────────────────

  static String csv(List<MovMedicionDoc> ms) {
    String esc(String v) {
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    final buf = StringBuffer()..writeln(_cabecera.map(esc).join(','));
    for (final m in ms) {
      buf.writeln(_filaMedicion(m).map(esc).join(','));
    }
    return buf.toString();
  }

  // ── Excel ──────────────────────────────────────────────────────────────────

  static Uint8List excel(List<MovMedicionDoc> ms) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Mediciones');
    final hoja = excel['Mediciones'];
    hoja.appendRow(_cabecera.map((h) => xl.TextCellValue(h)).toList());
    for (final m in ms) {
      hoja.appendRow([
        xl.TextCellValue(m.rutaCodigo),
        xl.TextCellValue('${m.ordenParada}/${m.totalParadasRuta}'),
        xl.TextCellValue(m.tramoDesdeNombre),
        xl.TextCellValue(m.puntoNombre),
        xl.TextCellValue(m.puntoDireccion),
        xl.TextCellValue(m.fecha),
        xl.TextCellValue(m.hora),
        xl.TextCellValue(m.horaSalidaTramoTxt),
        xl.TextCellValue(m.horaLlegadaTxt),
        xl.TextCellValue(movComidaLabel(m.comida)),
        xl.TextCellValue(m.ventanaHasta),
        xl.TextCellValue(
          m.dentroDeVentana == null
              ? ''
              : (m.dentroDeVentana! ? 'A TIEMPO' : 'TARDE'),
        ),
        m.minutosFueraVentana > 0
            ? xl.IntCellValue(m.minutosFueraVentana)
            : xl.TextCellValue(''),
        xl.TextCellValue(
          m.weekdayNombre.isNotEmpty
              ? m.weekdayNombre
              : movWeekdayNombre(m.weekday),
        ),
        xl.TextCellValue(movEscenarioLabel(m.escenario)),
        m.ok ? xl.DoubleCellValue(m.distanciaKm) : xl.TextCellValue(''),
        m.ok
            ? xl.DoubleCellValue(m.minutosEnRutaAlLlegar)
            : xl.TextCellValue(''),
        m.ok
            ? xl.DoubleCellValue(m.distanciaAcumuladaKm)
            : xl.TextCellValue(''),
        m.ok
            ? xl.DoubleCellValue(m.duracionTraficoMin)
            : xl.TextCellValue(''),
        m.duracionSinTraficoMin != null
            ? xl.DoubleCellValue(m.duracionSinTraficoMin!)
            : xl.TextCellValue(''),
        m.ok && m.diferenciaCalculada != null
            ? xl.DoubleCellValue(m.diferenciaCalculada!)
            : xl.TextCellValue(''),
        m.demoraTraficoMin != null
            ? xl.DoubleCellValue(m.demoraTraficoMin!)
            : xl.TextCellValue(''),
        xl.TextCellValue(m.rutaPrincipal),
        xl.TextCellValue(m.rutaAlterna),
        xl.TextCellValue(movTraficoLabel(m.estadoTrafico)),
        xl.IntCellValue(m.obrasOficiales.total),
        xl.TextCellValue(
          m.obrasOficiales.detalle.map((o) => o.radicadoSdm).join(' | '),
        ),
        xl.TextCellValue(
          m.obrasOficiales.detalle.map((o) => o.resumen).join(' | '),
        ),
        xl.IntCellValue(m.incidentes.obras),
        xl.IntCellValue(m.incidentes.cierres),
        xl.IntCellValue(m.incidentes.total),
        xl.TextCellValue(
          m.incidentes.detalle.map((i) => i.resumen).join(' | '),
        ),
        xl.TextCellValue(movRiesgoLabel(m.riesgo)),
        xl.TextCellValue(m.alerta ? 'SÍ' : ''),
        xl.TextCellValue(movFuenteMedicionLabel(m.fuente)),
        xl.TextCellValue(m.tipo),
        xl.TextCellValue(m.creadoPor),
        xl.TextCellValue(m.ok ? m.observaciones : 'FALLIDA: ${m.errorMsg}'),
      ]);
    }

    // Hoja 2: resumen por punto.
    final resumen = excel['Resumen por punto'];
    resumen.appendRow(
      [
        'Ruta',
        'Parada N°',
        'Punto',
        'Dirección',
        'Mediciones',
        'Promedio EN RUTA (min)',
        'Máximo (min)',
        'Mínimo (min)',
        'Demora prom. (min)',
        'Riesgo (promedio)',
        'Riesgo (peor caso)',
        'Alertas',
      ].map((h) => xl.TextCellValue(h)).toList(),
    );
    for (final r in MovStats.porPunto(ms)) {
      resumen.appendRow([
        xl.TextCellValue(r.rutaCodigo),
        xl.TextCellValue('${r.ordenParada}/${r.totalParadasRuta}'),
        xl.TextCellValue(r.nombre),
        xl.TextCellValue(r.direccion),
        xl.IntCellValue(r.n),
        xl.DoubleCellValue(double.parse(r.promMin.toStringAsFixed(1))),
        xl.DoubleCellValue(r.maxMin),
        xl.DoubleCellValue(r.minMin),
        xl.DoubleCellValue(double.parse(r.promDemoraMin.toStringAsFixed(1))),
        xl.TextCellValue(movRiesgoLabel(r.riesgoProm)),
        xl.TextCellValue(movRiesgoLabel(r.riesgoPeor)),
        xl.IntCellValue(r.alertas),
      ]);
    }

    // Hoja 3: promedios por día, franja y hora + pico vs valle.
    final prom = excel['Promedios'];
    prom.appendRow([xl.TextCellValue('PROMEDIO POR DÍA')]);
    prom.appendRow(
      ['Día', 'Promedio (min)'].map((h) => xl.TextCellValue(h)).toList(),
    );
    MovStats.promedioPorDia(ms).forEach((w, p) {
      prom.appendRow([
        xl.TextCellValue(movWeekdayNombre(w)),
        xl.DoubleCellValue(double.parse(p.toStringAsFixed(1))),
      ]);
    });
    prom.appendRow([xl.TextCellValue('')]);
    prom.appendRow([xl.TextCellValue('PROMEDIO POR ESCENARIO')]);
    prom.appendRow(
      ['Escenario', 'Promedio (min)'].map((h) => xl.TextCellValue(h)).toList(),
    );
    MovStats.promedioPorEscenario(ms).forEach((esc, p) {
      prom.appendRow([
        xl.TextCellValue(movEscenarioLabel(esc)),
        xl.DoubleCellValue(double.parse(p.toStringAsFixed(1))),
      ]);
    });
    prom.appendRow([xl.TextCellValue('')]);
    prom.appendRow([xl.TextCellValue('PROMEDIO POR HORA')]);
    prom.appendRow(
      ['Hora', 'Promedio (min)'].map((h) => xl.TextCellValue(h)).toList(),
    );
    MovStats.promedioPorHora(ms).forEach((h, p) {
      prom.appendRow([
        xl.TextCellValue(h),
        xl.DoubleCellValue(double.parse(p.toStringAsFixed(1))),
      ]);
    });
    // Hoja 4: comparativo entre proveedores (solo si hay dos fuentes).
    final comparativo = MovStats.comparativoFuentes(ms);
    if (comparativo.isNotEmpty) {
      final comp = excel['Comparativo fuentes'];
      final a = movFuenteCorta(comparativo.first.fuenteA);
      final b = movFuenteCorta(comparativo.first.fuenteB);
      comp.appendRow(
        [
          'Punto',
          '$a (min)',
          '$b (min)',
          'Diferencia $b - $a (min)',
          'Diferencia (%)',
          'Promedio de ambas (min)',
          'Mediciones',
        ].map((h) => xl.TextCellValue(h)).toList(),
      );
      for (final c in comparativo) {
        comp.appendRow([
          xl.TextCellValue(c.nombre),
          xl.DoubleCellValue(double.parse(c.minA.toStringAsFixed(1))),
          xl.DoubleCellValue(double.parse(c.minB.toStringAsFixed(1))),
          xl.DoubleCellValue(double.parse(c.diferencia.toStringAsFixed(1))),
          xl.DoubleCellValue(
            double.parse(c.diferenciaPct.toStringAsFixed(1)),
          ),
          xl.DoubleCellValue(double.parse(c.promedio.toStringAsFixed(1))),
          xl.IntCellValue(c.n),
        ]);
      }
      final difProm = MovStats.promedio(
        comparativo.map((c) => c.diferenciaAbs),
      );
      comp.appendRow([xl.TextCellValue('')]);
      comp.appendRow([
        xl.TextCellValue('Diferencia absoluta promedio entre proveedores'),
        xl.DoubleCellValue(
          double.parse((difProm ?? 0).toStringAsFixed(1)),
        ),
      ]);
    }

    final pv = MovStats.picoVsValle(ms);
    if (pv != null) {
      prom.appendRow([xl.TextCellValue('')]);
      prom.appendRow([xl.TextCellValue('HORA PICO VS HORA VALLE')]);
      prom.appendRow([
        xl.TextCellValue('Promedio hora pico (min)'),
        xl.DoubleCellValue(double.parse(pv.pico.toStringAsFixed(1))),
      ]);
      prom.appendRow([
        xl.TextCellValue('Promedio hora valle (min)'),
        xl.DoubleCellValue(double.parse(pv.valle.toStringAsFixed(1))),
      ]);
      prom.appendRow([
        xl.TextCellValue('Diferencia (%)'),
        xl.DoubleCellValue(double.parse(pv.diferenciaPct.toStringAsFixed(1))),
      ]);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  static PdfColor _pdfRiesgoColor(String riesgo) {
    switch (riesgo) {
      case kMovRiesgoBajo:
        return PdfColor.fromInt(0xFF16A34A);
      case kMovRiesgoMedio:
        return PdfColor.fromInt(0xFFCA8A04);
      case kMovRiesgoAlto:
        return PdfColor.fromInt(0xFFEA580C);
      case kMovRiesgoCritico:
        return PdfColor.fromInt(0xFFDC2626);
      default:
        return PdfColors.grey700;
    }
  }

  /// Reporte PDF.
  /// [modo]: 'resumen' | 'punto' | 'dia' | 'consolidado'.
  static Future<Uint8List> pdf({
    required String modo,
    required List<MovMedicionDoc> ms,
    required MovConfigDoc config,
    required String rangoTexto,
  }) async {
    final data = await rootBundle.load('assets/arial.ttf');
    final arial = pw.Font.ttf(data);
    final theme = pw.ThemeData.withFont(base: arial, bold: arial);
    final verde = PdfColor.fromInt(0xFF15803D);
    final doc = pw.Document(theme: theme);
    final generado = _fmtFechaHora.format(DateTime.now());
    final ok = MovStats.okDe(ms);
    final porPunto = MovStats.porPunto(ms);

    pw.Widget titulo(String t) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
          child: pw.Text(
            t,
            style: pw.TextStyle(
              fontSize: 13,
              color: verde,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );

    pw.Widget tabla(List<String> headers, List<List<String>> rows,
            {Map<int, pw.Alignment>? aligns}) =>
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: pw.BoxDecoration(color: verde),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: aligns ?? const {},
          oddRowDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F1)),
        );

    // ── Gráficas ────────────────────────────────────────────────────────
    // El informe va a licitación: los datos tienen que leerse de un vistazo,
    // no solo en tablas.

    /// Escala "bonita" para el eje Y (0, paso, 2·paso, …) que cubra el máximo.
    List<double> ejeY(double maximo) {
      if (maximo <= 0) return [0, 1];
      final crudo = maximo / 4;
      final magnitud = math.pow(10, (math.log(crudo) / math.ln10).floor());
      final paso = (crudo / magnitud).ceil() * magnitud.toDouble();
      final n = (maximo / paso).ceil() + 1;
      return List.generate(n, (i) => i * paso);
    }

    pw.Widget grafico({
      required String titulo,
      required List<String> etiquetas,
      required List<double> valores,
      required PdfColor color,
      String unidad = 'min',
      double alto = 165,
      bool lineas = false,
      double anguloEtiqueta = 0,
    }) {
      if (valores.isEmpty) return pw.SizedBox();
      final maximo = valores.reduce((a, b) => a > b ? a : b);
      final datos = <pw.PointChartValue>[
        for (var i = 0; i < valores.length; i++)
          pw.PointChartValue(i.toDouble(), valores[i]),
      ];
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.SizedBox(
            height: alto,
            child: pw.Chart(
              grid: pw.CartesianGrid(
                // Con una sola categoría el eje quedaría sin rango y el
                // paquete pinta con NaN: siempre se dejan ≥ 2 posiciones y
                // la sobrante va sin etiqueta.
                xAxis: pw.FixedAxis<int>(
                  List.generate(math.max(2, etiquetas.length), (i) => i),
                  buildLabel: (v) {
                    final i = v.toInt();
                    if (i < 0 || i >= etiquetas.length) return pw.SizedBox();
                    return pw.Transform.rotateBox(
                      angle: anguloEtiqueta,
                      child: pw.Text(
                        etiquetas[i],
                        style: const pw.TextStyle(fontSize: 6.5),
                      ),
                    );
                  },
                  marginStart: 20,
                  marginEnd: 20,
                ),
                yAxis: pw.FixedAxis<double>(
                  ejeY(maximo),
                  format: (v) => v.toStringAsFixed(0),
                  textStyle: const pw.TextStyle(fontSize: 6.5),
                  divisions: true,
                ),
              ),
              datasets: [
                if (lineas)
                  pw.LineDataSet(
                    data: datos,
                    color: color,
                    lineWidth: 1.6,
                    pointSize: 2.2,
                    drawSurface: true,
                    surfaceOpacity: .15,
                    isCurved: true,
                  )
                else
                  pw.BarDataSet(
                    data: datos,
                    color: color,
                    width: (330 / etiquetas.length).clamp(4.0, 22.0),
                    borderColor: color,
                  ),
              ],
            ),
          ),
          pw.Text(
            'Valores en $unidad.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 10),
        ],
      );
    }

    List<pw.Widget> encabezado(String subtitulo) => [
          pw.Text(
            'ESTUDIO DE MOVILIDAD — TIEMPOS DE DESPLAZAMIENTO',
            style: pw.TextStyle(
              fontSize: 16,
              color: verde,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Origen: ${config.origenNombre} — ${config.origenDireccion} '
            '(${config.origenLat.toStringAsFixed(6)}, '
            '${config.origenLng.toStringAsFixed(6)})',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            'Periodo: $rangoTexto · Generado: $generado · '
            'Mediciones: ${ms.length} (exitosas: ${ok.length})',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Divider(color: verde),
        ];

    /// Comportamiento del sistema en gráficas.
    List<pw.Widget> bloqueGraficas() {
      if (ok.isEmpty) return [];
      final w = <pw.Widget>[titulo('Comportamiento de los tiempos en ruta')];

      // 1) Por hora de salida — la curva del día.
      final porHora = MovStats.promedioPorHora(ms);
      if (porHora.length >= 2) {
        w.add(
          grafico(
            titulo: 'Tiempo en ruta promedio segun la hora de salida',
            etiquetas: porHora.keys.toList(),
            valores: porHora.values.toList(),
            color: PdfColor.fromInt(0xFF15803D),
            lineas: true,
          ),
        );
      }

      // 2) Por escenario.
      final porEsc = MovStats.promedioPorEscenario(ms);
      if (porEsc.isNotEmpty) {
        w.add(
          grafico(
            titulo: 'Tiempo en ruta promedio por escenario de trafico',
            etiquetas: porEsc.keys.map(movEscenarioLabel).toList(),
            valores: porEsc.values.toList(),
            color: PdfColor.fromInt(0xFF2563EB),
          ),
        );
      }

      // 3) Por día.
      final porDia = MovStats.promedioPorDia(ms);
      if (porDia.length >= 2) {
        w.add(
          grafico(
            titulo: 'Tiempo en ruta promedio por dia de la semana',
            etiquetas: porDia.keys.map(movWeekdayNombre).toList(),
            valores: porDia.values.toList(),
            color: PdfColor.fromInt(0xFF7C3AED),
          ),
        );
      }

      // 4) Cierre de cada ruta: el dato que decide si la operación es viable.
      final cierres = MovStats.cierrePorRuta(ms);
      if (cierres.isNotEmpty) {
        w.add(
          grafico(
            titulo:
                'Tiempo total en ruta al cerrar cada recorrido (promedio)',
            etiquetas: cierres.keys.toList(),
            valores: cierres.values.toList(),
            color: PdfColor.fromInt(0xFFEA580C),
          ),
        );
      }

      // 5) Distribución de riesgo.
      final riesgos = <String, double>{};
      for (final r in kMovRiesgos) {
        riesgos[movRiesgoLabel(r)] =
            ok.where((m) => m.riesgo == r).length.toDouble();
      }
      if (riesgos.values.any((v) => v > 0)) {
        w.add(
          grafico(
            titulo: 'Distribucion de las entregas por nivel de riesgo',
            etiquetas: riesgos.keys.toList(),
            valores: riesgos.values.toList(),
            color: PdfColor.fromInt(0xFFDC2626),
            unidad: 'entregas medidas',
          ),
        );
      }
      return w;
    }

    /// Cumplimiento de las ventanas de entrega del servicio.
    List<pw.Widget> bloqueVentanas() {
      final conVentana =
          ok.where((m) => m.dentroDeVentana != null).toList();
      if (conVentana.isEmpty) return [];
      final tarde = conVentana.where((m) => m.llegaTarde).toList();

      // Resumen por comida.
      final filasComida = <List<String>>[];
      for (final comida in [
        kMovComidaDesayuno,
        kMovComidaAlmuerzo,
        kMovComidaCena,
      ]) {
        final deComida =
            conVentana.where((m) => m.comida == comida).toList();
        if (deComida.isEmpty) continue;
        final tardeC = deComida.where((m) => m.llegaTarde).toList();
        final pct = (tardeC.length / deComida.length) * 100;
        final maxRetraso = tardeC.isEmpty
            ? 0
            : tardeC
                  .map((m) => m.minutosFueraVentana)
                  .reduce((a, b) => a > b ? a : b);
        filasComida.add([
          movComidaLabel(comida),
          deComida.first.ventanaHasta,
          '${deComida.length}',
          '${tardeC.length}',
          '${pct.toStringAsFixed(1)} %',
          tardeC.isEmpty ? '—' : '$maxRetraso min',
        ]);
      }

      // Puntos que incumplen, agrupados.
      final porPuntoTarde = <String, List<MovMedicionDoc>>{};
      for (final m in tarde) {
        porPuntoTarde
            .putIfAbsent('${m.rutaCodigo}|${m.puntoNombre}', () => [])
            .add(m);
      }
      final filasPunto = porPuntoTarde.entries.map((e) {
        final l = e.value;
        final peor = l
            .map((m) => m.minutosFueraVentana)
            .reduce((a, b) => a > b ? a : b);
        return [
          l.first.rutaCodigo,
          '${l.first.ordenParada}/${l.first.totalParadasRuta}',
          l.first.puntoNombre,
          movComidaLabel(l.first.comida),
          '${l.length}',
          '$peor min',
        ];
      }).toList()
        ..sort((a, b) {
          int n(String s) => int.tryParse(s.replaceAll(' min', '')) ?? 0;
          return n(b[5]).compareTo(n(a[5]));
        });

      return [
        titulo('Cumplimiento de las ventanas de entrega'),
        pw.Text(
          'Ademas del limite por conservacion de alimentos, la operacion debe '
          'entregar dentro del horario de cada servicio. Este apartado mide '
          'esa segunda restriccion: si el vehiculo llega despues del cierre '
          'de la ventana, la entrega se considera incumplida aunque el tiempo '
          'en ruta sea aceptable. De ${conVentana.length} entregas medidas '
          'dentro de una ventana, ${tarde.length} llegaron tarde '
          '(${((tarde.length / conVentana.length) * 100).toStringAsFixed(1)} %).',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        tabla(
          ['Servicio', 'Cierra', 'Entregas medidas', 'Fuera de ventana',
            '% incumplimiento', 'Peor retraso'],
          filasComida,
        ),
        if (filasPunto.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Puntos que no alcanzan su ventana',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          tabla(
            ['Ruta', 'Parada', 'Punto', 'Servicio', 'Veces tarde',
              'Peor retraso'],
            filasPunto,
          ),
        ],
      ];
    }

    /// Trazabilidad: todas las fuentes de las que sale el informe.
    List<pw.Widget> bloqueFuentes() {
      final fuentesUsadas = MovStats.fuentesPresentes(ms)
          .map(movFuenteMedicionLabel)
          .join(', ');
      final conObras = ok.where((m) => m.obrasOficiales.hayAlgo).length;
      final conInc = ok.where((m) => m.incidentes.hayAlgo).length;

      final filas = <List<String>>[
        [
          'Tiempos de recorrido con tráfico',
          fuentesUsadas.isEmpty ? '—' : fuentesUsadas,
          'API comercial de enrutamiento, consultada en el instante de cada '
              'medición. Entrega distancia vial, tiempo con tráfico en vivo y '
              'tiempo nominal sin tráfico.',
        ],
        [
          'Obras y cierres autorizados',
          'Planes de Manejo de Transito (PMT) - Secretaria Distrital de '
              'Movilidad, servicio geografico SIMUR',
          'Fuente OFICIAL. Cada obra tiene acto administrativo (radicado '
              'SDM), contratista, tipo de afectacion, localidad y vigencia. '
              'Se filtran las vigentes en la fecha de la medicion y se cruzan '
              'con la geometria de cada ruta. Mediciones con obra oficial '
              'sobre la ruta: $conObras de ${ok.length}.',
        ],
        [
          'Incidentes viales en tiempo real',
          'TomTom Traffic Incidents API',
          'Accidentes, congestion, cierres imprevistos, vehiculos averiados y '
              'clima adverso vigentes al momento de la medicion. Captura lo '
              'NO programado, que ningun PMT puede anticipar. Mediciones con '
              'incidente sobre la ruta: $conInc de ${ok.length}.',
        ],
        [
          'Ubicacion de los puntos de entrega',
          'Archivo KML/CSV del estudio, con coordenadas verificadas',
          'Origen (Centro de Operaciones) y ${porPunto.length} destinos. Las '
              'coordenadas corregidas se contrastaron contra fuentes '
              'oficiales de cada entidad.',
        ],
        [
          'Ejecucion y registro',
          'Cloud Functions de Firebase (zona horaria America/Bogota)',
          'Las mediciones corren en servidor, sin intervencion humana ni '
              'dependencia de dispositivos moviles. Cada registro conserva la '
              'respuesta cruda de la API en formato JSON.',
        ],
      ];

      return [
        titulo('Fuentes de informacion y trazabilidad'),
        pw.Text(
          'El informe combina fuentes independientes para que cada tiempo '
          'reportado pueda contrastarse y reproducirse. Se distingue entre '
          'fuentes OFICIALES del Distrito (con acto administrativo) y '
          'fuentes comerciales de trafico en tiempo real.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        tabla(['Dato', 'Fuente', 'Alcance y uso en el estudio'], filas),
      ];
    }

    /// Obras AUTORIZADAS (PMT) vigentes sobre las rutas medidas.
    List<pw.Widget> bloqueObrasOficiales() {
      final conObras = ok.where((m) => m.obrasOficiales.hayAlgo).toList();
      if (conObras.isEmpty) return [];

      // Una obra puede afectar varias rutas: se agrupa por radicado.
      final porRadicado = <String, ({MovObraOficial obra, Set<String> puntos})>{};
      for (final m in conObras) {
        for (final o in m.obrasOficiales.detalle) {
          final clave = o.radicadoSdm.isNotEmpty
              ? o.radicadoSdm
              : '${o.direccionInicio}|${o.contratista}';
          final actual = porRadicado[clave];
          if (actual == null) {
            porRadicado[clave] = (obra: o, puntos: {m.puntoNombre});
          } else {
            actual.puntos.add(m.puntoNombre);
          }
        }
      }
      final filas = porRadicado.values.toList()
        ..sort((a, b) => b.puntos.length.compareTo(a.puntos.length));

      return [
        titulo('Obras autorizadas por la SDM sobre las rutas medidas'),
        pw.Text(
          'Obras y cierres con Plan de Manejo de Transito (PMT) aprobado por '
          'la Secretaria Distrital de Movilidad, vigentes en la fecha de la '
          'medicion y localizados sobre el trayecto recorrido. Cada registro '
          'es verificable por su radicado SDM. Mediciones afectadas por al '
          'menos una obra autorizada: ${conObras.length} de ${ok.length}.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        tabla(
          [
            'Tramo intervenido',
            'Afectacion',
            'Localidad',
            'Contratista',
            'Vigencia',
            'Radicado SDM',
            'Rutas afectadas',
          ],
          filas
              .map(
                (e) => [
                  e.obra.tramo,
                  e.obra.tipoAfectacion,
                  e.obra.localidad,
                  e.obra.contratista,
                  e.obra.vigencia.replaceFirst('vigente ', ''),
                  e.obra.radicadoSdm,
                  e.puntos.take(4).join(', ') +
                      (e.puntos.length > 4
                          ? ' (+${e.puntos.length - 4})'
                          : ''),
                ],
              )
              .toList(),
        ),
      ];
    }

    /// Obras, cierres y congestión encontrados sobre las rutas medidas.
    List<pw.Widget> bloqueIncidentes() {
      final conIncidentes = ok.where((m) => m.incidentes.hayAlgo).toList();
      if (conIncidentes.isEmpty) return [];
      final obras = conIncidentes.where((m) => m.incidentes.obras > 0).toList();

      // Agrupa por punto para no repetir la misma obra en cada corrida.
      final porPuntoInc = <String, List<MovMedicionDoc>>{};
      for (final m in conIncidentes) {
        porPuntoInc.putIfAbsent(m.puntoNombre, () => []).add(m);
      }

      return [
        titulo('Condiciones de la vía durante las mediciones'),
        pw.Text(
          'Obras, cierres y congestión detectados SOBRE el trayecto en el '
          'momento exacto de cada medición (fuente: TomTom Traffic Incidents, '
          'incidentes vigentes a menos de 150 m de la ruta). Este apartado '
          'permite explicar por qué una ruta concreta tardó más de lo '
          'habitual. Mediciones con incidentes en ruta: '
          '${conIncidentes.length} de ${ok.length}; de ellas '
          '${obras.length} con obras en la vía.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        tabla(
          ['Punto', 'Mediciones con incidente', 'Obras', 'Cierres',
            'Ejemplo reportado'],
          porPuntoInc.entries.map((e) {
            final obrasPunto = e.value
                .map((m) => m.incidentes.obras)
                .fold<int>(0, (a, b) => a > b ? a : b);
            final cierresPunto = e.value
                .map((m) => m.incidentes.cierres)
                .fold<int>(0, (a, b) => a > b ? a : b);
            final ejemplo = e.value
                .expand((m) => m.incidentes.detalle)
                .where((i) => i.esObra)
                .followedBy(e.value.expand((m) => m.incidentes.detalle))
                .firstOrNull;
            return [
              e.key,
              '${e.value.length}',
              '$obrasPunto',
              '$cierresPunto',
              ejemplo?.resumen ?? '—',
            ];
          }).toList(),
        ),
      ];
    }

    List<pw.Widget> bloqueComparativo() {
      final comparativo = MovStats.comparativoFuentes(ms);
      if (comparativo.isEmpty) return [];
      final a = movFuenteCorta(comparativo.first.fuenteA);
      final b = movFuenteCorta(comparativo.first.fuenteB);
      final difProm =
          MovStats.promedio(comparativo.map((c) => c.diferenciaAbs)) ?? 0;
      return [
        titulo('Contraste entre dos proveedores independientes'),
        pw.Text(
          'Cada punto se midió en la misma corrida con $a y con $b. Que dos '
          'proveedores independientes coincidan en el orden de magnitud '
          'refuerza la validez de los tiempos reportados. Diferencia '
          'absoluta promedio entre ambos: ${difProm.toStringAsFixed(1)} min. '
          'La tabla incluye ${comparativo.length} de ${porPunto.length} '
          'puntos: solo aparecen aquellos con medición válida de AMBOS '
          'proveedores en el periodo.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        tabla(
          [
            'Punto',
            '$a (min)',
            '$b (min)',
            'Dif. (min)',
            'Dif. (%)',
            'Promedio (min)',
          ],
          comparativo
              .map(
                (c) => [
                  c.nombre,
                  c.minA.toStringAsFixed(1),
                  c.minB.toStringAsFixed(1),
                  c.diferencia.toStringAsFixed(1),
                  '${c.diferenciaPct.toStringAsFixed(1)} %',
                  c.promedio.toStringAsFixed(1),
                ],
              )
              .toList(),
        ),
      ];
    }

    List<pw.Widget> bloqueResumen() {
      final promGeneral =
          MovStats.promedio(ok.map(MovStats.valor));
      final alertas = ok.where((m) => m.alerta).length;
      final pv = MovStats.picoVsValle(ms);
      final criticas = porPunto
          .where(
            (r) =>
                r.riesgoPeor == kMovRiesgoCritico ||
                r.riesgoPeor == kMovRiesgoAlto,
          )
          .toList();
      return [
        titulo('1. Indicadores generales'),
        pw.Bullet(
          text: 'Puntos medidos: ${porPunto.length} · '
              'Mediciones exitosas: ${ok.length} · Fallidas: '
              '${ms.length - ok.length} · Alertas (≥ '
              '${config.umbralAlertaMin} min): $alertas',
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (promGeneral != null)
          pw.Bullet(
            // El formato h/min solo aporta cuando pasa de una hora.
            text: 'Tiempo promedio general con tráfico: '
                '${promGeneral.toStringAsFixed(1)} min'
                '${promGeneral >= 60 ? ' (${MovMedicionDoc.formatoMin(promGeneral)})' : ''}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (pv != null)
          pw.Bullet(
            text: 'Hora pico: ${pv.pico.toStringAsFixed(1)} min vs hora '
                'valle: ${pv.valle.toStringAsFixed(1)} min → diferencia '
                '${pv.diferenciaPct.toStringAsFixed(1)} %',
            style: const pw.TextStyle(fontSize: 9),
          ),
        titulo('2. Promedio por día'),
        tabla(
          ['Día', 'Promedio (min)'],
          MovStats.promedioPorDia(ms)
              .entries
              .map((e) => [movWeekdayNombre(e.key), e.value.toStringAsFixed(1)])
              .toList(),
        ),
        titulo('3. Promedio por escenario'),
        tabla(
          ['Escenario', 'Promedio (min)'],
          MovStats.promedioPorEscenario(ms)
              .entries
              .map((e) => [movEscenarioLabel(e.key), e.value.toStringAsFixed(1)])
              .toList(),
        ),
        titulo('4. Ranking de puntos por TIEMPO EN RUTA'),
        pw.Text(
          'El tiempo reportado es el ACUMULADO desde la planta hasta cada '
          'parada, siguiendo la secuencia real de la ruta. Es el tiempo que '
          'el alimento lleva fuera de la planta al momento de la entrega, y '
          'es el que define la clasificacion de riesgo.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 4),
        tabla(
          [
            'Ruta',
            'Parada',
            'Punto',
            'N',
            'Prom en ruta (min)',
            'Max (min)',
            'Prom tramo (min)',
            'Riesgo prom.',
            'Riesgo peor caso',
            'Alertas',
          ],
          porPunto
              .map(
                (r) => [
                  r.rutaCodigo,
                  '${r.ordenParada}/${r.totalParadasRuta}',
                  r.nombre,
                  '${r.n}',
                  r.promMin.toStringAsFixed(1),
                  r.maxMin.toStringAsFixed(1),
                  r.promTramoMin.toStringAsFixed(1),
                  movRiesgoLabel(r.riesgoProm),
                  movRiesgoLabel(r.riesgoPeor),
                  '${r.alertas}',
                ],
              )
              .toList(),
        ),
        if (criticas.isNotEmpty) ...[
          titulo('5. Rutas en riesgo alto controlado o crítico (peor caso)'),
          tabla(
            ['Punto', 'Peor tiempo', 'Riesgo'],
            criticas
                .map(
                  (r) => [
                    r.nombre,
                    MovMedicionDoc.formatoMin(r.maxMin),
                    movRiesgoLabel(r.riesgoPeor),
                  ],
                )
                .toList(),
          ),
        ],
        ...bloqueVentanas(),
        ...bloqueGraficas(),
        ...bloqueComparativo(),
        ...bloqueObrasOficiales(),
        ...bloqueIncidentes(),
      ];
    }

    List<pw.Widget> bloqueMetodologia() => [
          titulo('Metodología'),
          pw.Text(
            'Las mediciones se ejecutan automáticamente desde el backend '
            '(Cloud Functions de Firebase, zona horaria America/Bogota), sin '
            'depender de dispositivos móviles. En cada corrida se consulta la '
            'API de rutas configurada (Google Routes API con '
            'routingPreference=TRAFFIC_AWARE_OPTIMAL, o TomTom Routing API '
            'con traffic=true) para el trayecto Centro de Operaciones → cada '
            'punto, obteniendo distancia vial, tiempo estimado con tráfico en '
            'tiempo real, tiempo sin tráfico y demora atribuida al tráfico. '
            'Cada medición conserva la respuesta cruda de la API (JSON) como '
            'evidencia verificable y reproducible.\n\n'
            'Clasificación de riesgo según el tiempo estimado con tráfico: '
            '0-60 min riesgo bajo; 61-90 min riesgo medio; 91-120 min riesgo '
            'alto controlado; más de 120 min riesgo crítico. Cuando una ruta '
            'alcanza el umbral de alerta (${config.umbralAlertaMin} min) se '
            'genera una alerta, dado que el estudio exige evaluar la '
            'compatibilidad de las rutas con la conservación segura de '
            'alimentos preparados (límite de referencia: 2 horas).\n\n'
            'Frecuencia programada del estudio: sábado, domingo, lunes y '
            'martes en las franjas configuradas (sugeridas: 06:00, 07:00, '
            '09:30, 12:00 y 17:00), cubriendo hora pico mañana, hora valle, '
            'medio día, hora pico tarde y fin de semana.\n\n'
            'Modelo de operacion: las entregas NO son trayectos '
            'independientes desde la planta a cada punto. La operacion se '
            'realiza con 10 rutas encadenadas: cada vehiculo sale del Centro '
            'de Operaciones, entrega en su primera parada, continua a la '
            'segunda y asi sucesivamente. Por eso el estudio mide TRAMO a '
            'TRAMO (planta -> parada 1, parada 1 -> parada 2, ...) y acumula '
            'los tiempos siguiendo la secuencia real. Cada tramo se consulta '
            'con la hora de salida que le corresponde, es decir, el momento '
            'en que el vehiculo termina los tramos anteriores, de modo que '
            'las paradas finales se evaluan con las condiciones de trafico '
            'que efectivamente encontraran.\n\n'
            'La CLASIFICACION DE RIESGO se aplica sobre el tiempo acumulado '
            'en ruta al llegar a cada parada, no sobre la duracion del ultimo '
            'tramo, porque lo determinante para la inocuidad es cuanto tiempo '
            'lleva el alimento fuera de la planta al momento de la entrega.\n\n'
            'Nota sobre los tiempos reportados: el tiempo ACTUAL es la '
            'predicción con tráfico en vivo del instante de la consulta; el '
            'tiempo ESPERADO es el que calcula la API con las velocidades '
            'nominales de cada tramo, sin considerar el tráfico. La '
            'diferencia entre ambos, con signo, indica si el trayecto '
            'transcurrió peor o mejor de lo previsto por el modelo.\n\n'
            'Adicionalmente, en cada medición se consultan los incidentes '
            'viales vigentes (obras, cierres de vía o carril, congestión y '
            'accidentes) y se conservan los que se encuentran a menos de '
            '150 m del trayecto medido, de modo que cada tiempo pueda '
            'contrastarse con las condiciones reales de la vía en ese '
            'momento.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ];

    List<List<String>> filasDetalle(List<MovMedicionDoc> lista) => lista
        .map(
          (m) => [
            m.fecha,
            m.hora,
            m.rutaCodigo.isEmpty
                ? m.weekdayNombre
                : '${m.rutaCodigo} ${m.ordenParada}/${m.totalParadasRuta}',
            m.puntoNombre,
            movEscenarioLabel(m.escenario),
            m.horarioTramoTexto.isEmpty ? m.hora : m.horarioTramoTexto,
            m.dentroDeVentana == null
                ? '—'
                : (m.llegaTarde ? '+${m.minutosFueraVentana}' : 'OK'),
            m.ok ? m.minutosEnRutaAlLlegar.toStringAsFixed(0) : '—',
            m.ok ? m.distanciaKm.toStringAsFixed(1) : '—',
            m.ok ? m.duracionTraficoMin.toStringAsFixed(0) : '—',
            m.duracionSinTraficoMin?.toStringAsFixed(0) ?? '—',
            m.ok ? m.diferenciaTexto : '—',
            movFuenteCorta(m.fuente),
            movRiesgoLabel(m.riesgo),
          ],
        )
        .toList();

    const cabDetalle = [
      'Fecha',
      'Hora',
      'Ruta',
      'Punto',
      'Escenario',
      'Sale-llega',
      'Ventana',
      'EN RUTA',
      'km',
      'Actual',
      'Esperado',
      'Dif.',
      'Fuente',
      'Riesgo',
    ];

    final contenido = <pw.Widget>[];
    switch (modo) {
      case 'punto':
        contenido.addAll(encabezado('Reporte por punto de entrega'));
        for (final r in porPunto) {
          contenido.add(titulo('${r.nombre} — ${r.direccion}'));
          contenido.add(
            pw.Text(
              'Mediciones: ${r.n} · Promedio: '
              '${MovMedicionDoc.formatoMin(r.promMin)} · Máximo: '
              '${MovMedicionDoc.formatoMin(r.maxMin)} · Mínimo: '
              '${MovMedicionDoc.formatoMin(r.minMin)} · Riesgo promedio: '
              '${movRiesgoLabel(r.riesgoProm)} · Alertas: ${r.alertas}',
              style: pw.TextStyle(
                fontSize: 9,
                color: _pdfRiesgoColor(r.riesgoProm),
              ),
            ),
          );
          contenido.add(pw.SizedBox(height: 4));
          contenido.add(
            tabla(
              cabDetalle,
              filasDetalle(
                ok.where((m) => m.puntoId == r.puntoId).toList(),
              ),
            ),
          );
        }
        break;
      case 'ruta':
        contenido.addAll(encabezado('Reporte por ruta'));
        final codigos = ok.map((m) => m.rutaCodigo).toSet().toList()
          ..sort((a, b) {
            int n(String c) =>
                int.tryParse(c.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
            return n(a).compareTo(n(b));
          });
        for (final codigo in codigos) {
          final deRuta = ok.where((m) => m.rutaCodigo == codigo).toList();
          if (deRuta.isEmpty) continue;
          // Se toma la ÚLTIMA CORRIDA completa, no la última medición de
          // cada parada: mezclar corridas produce secuencias imposibles
          // (una parada a las 16:14 y la siguiente a las 07:21).
          MovMedicionDoc? masReciente;
          for (final m in deRuta) {
            if (masReciente == null ||
                m.fechaHora.compareTo(masReciente.fechaHora) > 0) {
              masReciente = m;
            }
          }
          final runId = masReciente?.runId ?? '';
          final ultimaPorParada = <int, MovMedicionDoc>{};
          for (final m in deRuta) {
            if (m.runId != runId) continue;
            ultimaPorParada[m.ordenParada] = m;
          }
          final ordenes = ultimaPorParada.keys.toList()..sort();
          final cierre = ordenes.isEmpty
              ? null
              : ultimaPorParada[ordenes.last];
          contenido.add(
            titulo(
              '$codigo — ${ordenes.length} paradas'
              '${cierre == null ? '' : ' · total en ruta ${cierre.acumuladoTexto} (${movRiesgoLabel(cierre.riesgo)})'}',
            ),
          );
          contenido.add(
            pw.Text(
              'Secuencia de entrega segun la ultima corrida registrada. El '
              'tiempo en ruta es acumulado desde la planta.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
          contenido.add(pw.SizedBox(height: 4));
          contenido.add(
            tabla(
              ['#', 'Parada', 'Desde', 'Sale', 'Llega', 'Tramo (min)',
                'EN RUTA (min)', 'km acum.', 'Ventana', 'Riesgo'],
              ordenes.map((o) {
                final m = ultimaPorParada[o]!;
                return [
                  '$o',
                  m.puntoNombre,
                  m.tramoDesdeNombre,
                  m.horaSalidaTramoTxt.isEmpty ? '—' : m.horaSalidaTramoTxt,
                  m.horaLlegadaTxt.isEmpty ? '—' : m.horaLlegadaTxt,
                  m.duracionTraficoMin.toStringAsFixed(1),
                  m.minutosEnRutaAlLlegar.toStringAsFixed(1),
                  m.distanciaAcumuladaKm.toStringAsFixed(1),
                  m.dentroDeVentana == null
                      ? '—'
                      : (m.llegaTarde
                            ? 'TARDE +${m.minutosFueraVentana}'
                            : 'A tiempo'),
                  movRiesgoLabel(m.riesgo),
                ];
              }).toList(),
            ),
          );
          contenido.add(pw.SizedBox(height: 6));
          contenido.add(
            pw.Text(
              'Historico completo de $codigo',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
          contenido.add(pw.SizedBox(height: 3));
          contenido.add(tabla(cabDetalle, filasDetalle(deRuta)));
        }
        break;
      case 'dia':
        contenido.addAll(encabezado('Reporte por día'));
        final fechas = ok.map((m) => m.fecha).toSet().toList()..sort();
        for (final f in fechas) {
          final delDia = ok.where((m) => m.fecha == f).toList()
            ..sort((a, b) => a.hora.compareTo(b.hora));
          final prom = MovStats.promedio(
            delDia.map(MovStats.valor),
          );
          contenido.add(
            titulo(
              '$f (${delDia.first.weekdayNombre}) — ${delDia.length} '
              'mediciones · promedio '
              '${prom == null ? "—" : MovMedicionDoc.formatoMin(prom)}',
            ),
          );
          contenido.add(tabla(cabDetalle, filasDetalle(delDia)));
        }
        break;
      case 'consolidado':
        contenido.addAll(
          encabezado('Reporte consolidado para anexo al estudio técnico'),
        );
        contenido.addAll(bloqueMetodologia());
        contenido.addAll(bloqueFuentes());
        contenido.addAll(bloqueResumen());
        contenido.add(titulo('Anexo: detalle completo de mediciones'));
        contenido.add(tabla(cabDetalle, filasDetalle(ok)));
        break;
      default: // resumen
        contenido.addAll(encabezado('Resumen ejecutivo'));
        contenido.addAll(bloqueResumen());
        contenido.addAll(bloqueFuentes());
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 400,
        margin: const pw.EdgeInsets.all(28),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Estudio de Movilidad · página ${ctx.pageNumber} de '
            '${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => contenido,
      ),
    );
    return doc.save();
  }

  // ── Descarga multiplataforma ───────────────────────────────────────────────

  static Future<void> descargarCsv(String nombre, String contenido) async {
    await FileSaver.instance.saveFile(
      name: nombre,
      // BOM UTF-8 para que Excel abra las tildes correctamente.
      bytes: Uint8List.fromList(utf8.encode('﻿$contenido')),
      fileExtension: 'csv',
      mimeType: MimeType.text,
    );
  }

  static Future<void> descargarExcel(String nombre, Uint8List bytes) async {
    await FileSaver.instance.saveFile(
      name: nombre,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  static Future<void> descargarPdf(String nombre, Uint8List bytes) async {
    await FileSaver.instance.saveFile(
      name: nombre,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}
