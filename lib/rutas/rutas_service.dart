// lib/rutas/rutas_service.dart
//
// Capa de datos del módulo Rutas: Firestore + Storage. Convención del proyecto:
// las queries filtran por igualdad (empresaId + campos string) y ordenan en
// cliente, para no requerir índices compuestos.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/task_service.dart';
import 'rutas_excel_parser.dart';
import 'rutas_logic.dart';
import 'rutas_models.dart';

class RutasSyncResult {
  final int total;
  final int created;
  final int updated;
  final int skipped;

  const RutasSyncResult({
    required this.total,
    required this.created,
    required this.updated,
    required this.skipped,
  });
}

class RutasEstablecimientosImportResult {
  final int total;
  final int created;
  final int updated;
  final int rutasDesactivadas;
  final int asignacionesLiberadas;

  const RutasEstablecimientosImportResult({
    required this.total,
    required this.created,
    required this.updated,
    required this.rutasDesactivadas,
    required this.asignacionesLiberadas,
  });
}

class RutasCleanupResult {
  final int evidencias;
  final int resumenes;

  const RutasCleanupResult({required this.evidencias, required this.resumenes});
}

class RutasService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _tasks;

  RutasService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? tasks,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _tasks = tasks ?? TaskService();

  static const String _cRutas = 'TBL_RUTAS';
  static const String _cAsignaciones = 'TBL_RUTAS_ASIGNACIONES';
  static const String _cConfig = 'TBL_RUTAS_CONFIG';
  static const String _cEvidencias = 'TBL_RUTAS_EVIDENCIAS';
  static const String _cResumen = 'TBL_RUTAS_RESUMEN_DIARIO';
  static const String _cRoles = 'TBL_RUTAS_ROLES';
  static const String _cUbicaciones = 'TBL_RUTAS_UBICACIONES';
  static const String _cVehiculos = 'TBL_RUTAS_PLACAS';
  static const String _cEstablecimientos = 'TBL_RUTAS_ESTABLECIMIENTOS';

  // ─── ESTABLECIMIENTOS ─────────────────────────────────────────────────────

  Stream<List<RutaEstablecimientoDoc>> streamEstablecimientos(
    String empresaId,
  ) => _db
      .collection(_cEstablecimientos)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RutaEstablecimientoDoc.fromMap(d.id, d.data()))
            .where((e) => !_esCentroOperaciones(e.nombre))
            .toList();
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      });

  Future<List<RutaEstablecimientoDoc>> getEstablecimientos(
    String empresaId,
  ) async {
    final s = await _db
        .collection(_cEstablecimientos)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final list = s.docs
        .map((d) => RutaEstablecimientoDoc.fromMap(d.id, d.data()))
        .where((e) => !_esCentroOperaciones(e.nombre))
        .toList();
    list.sort((a, b) => a.nombre.compareTo(b.nombre));
    return list;
  }

  Future<String> guardarEstablecimiento(
    RutaEstablecimientoDoc establecimiento, {
    required bool isNew,
  }) async {
    final ref = isNew
        ? _db
              .collection(_cEstablecimientos)
              .doc(
                _establecimientoDocId(
                  establecimiento.empresaId,
                  establecimiento.nombre,
                ),
              )
        : _db.collection(_cEstablecimientos).doc(establecimiento.id);
    await ref.set(establecimiento.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> eliminarEstablecimiento(String id) =>
      _db.collection(_cEstablecimientos).doc(id).delete();

  Future<RutasSyncResult> sincronizarEstablecimientosDesdeExcel({
    required String empresaId,
    required List<RutaExcelRow> filas,
    String sourceName = '',
  }) async {
    final eid = empresaId.trim();
    if (eid.isEmpty || filas.isEmpty) {
      return RutasSyncResult(
        total: 0,
        created: 0,
        updated: 0,
        skipped: filas.length,
      );
    }

    final now = Timestamp.now();
    final validas = filas
        .where(
          (f) =>
              (f.sede.trim().isNotEmpty || f.direccion.trim().isNotEmpty) &&
              !_esCentroOperaciones(f.sede),
        )
        .toList();
    final refs = [
      for (final fila in validas)
        _db
            .collection(_cEstablecimientos)
            .doc(
              _establecimientoDocId(
                eid,
                fila.sede.trim().isEmpty ? fila.codigo : fila.sede,
              ),
            ),
    ];
    final existing = await Future.wait(refs.map((r) => r.get()));
    var created = 0;
    var updated = 0;

    final batch = _db.batch();
    for (var i = 0; i < validas.length; i++) {
      final fila = validas[i];
      final exists = existing[i].exists;
      if (exists) {
        updated++;
      } else {
        created++;
      }
      final establecimiento = RutaEstablecimientoDoc.fromStop(
        id: refs[i].id,
        empresaId: eid,
        stop: fila.toStop(),
        createdAt: exists
            ? (existing[i].data()?['createdAt'] as Timestamp? ?? now)
            : now,
      );
      batch.set(refs[i], {
        ...establecimiento.toMap(),
        'origen': 'excel_establecimientos',
        'importSource': sourceName,
        'excelRowNumber': fila.excelRowNumber,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return RutasSyncResult(
      total: validas.length,
      created: created,
      updated: updated,
      skipped: filas.length - validas.length,
    );
  }

  Future<RutasEstablecimientosImportResult>
  sincronizarEstablecimientosDesdeRutas(
    String empresaId, {
    bool desactivarRutasDeUnEstablecimiento = false,
  }) async {
    final rutas = await getRutas(empresaId);
    final stops = <RutaStop>[];
    for (final ruta in rutas) {
      stops.addAll(ruta.stops);
    }
    final validos = stops
        .where(
          (s) => s.nombre.trim().isNotEmpty && !_esCentroOperaciones(s.nombre),
        )
        .toList();
    if (validos.isEmpty) {
      return const RutasEstablecimientosImportResult(
        total: 0,
        created: 0,
        updated: 0,
        rutasDesactivadas: 0,
        asignacionesLiberadas: 0,
      );
    }

    final now = Timestamp.now();
    final refs = [
      for (final stop in validos)
        _db
            .collection(_cEstablecimientos)
            .doc(_establecimientoDocId(empresaId, stop.nombre)),
    ];
    final existing = await Future.wait(refs.map((r) => r.get()));
    var created = 0;
    var updated = 0;
    final batch = _db.batch();
    for (var i = 0; i < validos.length; i++) {
      final exists = existing[i].exists;
      if (exists) {
        updated++;
      } else {
        created++;
      }
      final establecimiento = RutaEstablecimientoDoc.fromStop(
        id: refs[i].id,
        empresaId: empresaId,
        stop: validos[i],
        createdAt: exists
            ? (existing[i].data()?['createdAt'] as Timestamp? ?? now)
            : now,
      );
      batch.set(refs[i], {
        ...establecimiento.toMap(),
        'origen': 'rutas_existentes',
      }, SetOptions(merge: true));
    }

    var desactivadas = 0;
    var liberadas = 0;
    if (desactivarRutasDeUnEstablecimiento) {
      final legacyIds = rutas
          .where((r) => r.activa && r.stops.length == 1)
          .map((r) => r.id)
          .toSet();
      for (final ruta in rutas.where((r) => legacyIds.contains(r.id))) {
        batch.update(_db.collection(_cRutas).doc(ruta.id), {
          'activa': false,
          'tipo': 'establecimiento_legacy',
          'migratedToEstablecimientosAt': now,
        });
        desactivadas++;
      }
      if (legacyIds.isNotEmpty) {
        final activas = await _db
            .collection(_cAsignaciones)
            .where('empresaId', isEqualTo: empresaId)
            .where('activa', isEqualTo: true)
            .get();
        for (final d in activas.docs) {
          final rutaId = (d.data()['rutaId'] ?? '').toString();
          if (!legacyIds.contains(rutaId)) continue;
          batch.update(d.reference, {
            'activa': false,
            'vigenteHasta': now,
            'closedByMigration': 'establecimientos_legacy',
          });
          liberadas++;
        }
      }
    }

    await batch.commit();
    return RutasEstablecimientosImportResult(
      total: validos.length,
      created: created,
      updated: updated,
      rutasDesactivadas: desactivadas,
      asignacionesLiberadas: liberadas,
    );
  }

  String _establecimientoDocId(String empresaId, String nombre) {
    final slug = _slugTexto(nombre);
    final key = slug.isEmpty ? DateTime.now().millisecondsSinceEpoch : slug;
    return '${empresaId}_est_$key';
  }

  String _slugTexto(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _esCentroOperaciones(String value) =>
      _slugTexto(value).contains('centro_de_operaciones');

  String _establecimientoKey(RutaStop stop) => _slugTexto(stop.nombre);

  void _validarRutaSinDuplicadosInternos(RutaDoc ruta) {
    final vistos = <String>{};
    final duplicados = <String>{};
    for (final stop in ruta.stops) {
      final key = _establecimientoKey(stop);
      if (key.isEmpty) continue;
      if (!vistos.add(key)) duplicados.add(stop.nombre);
    }
    if (duplicados.isNotEmpty) {
      throw ArgumentError(
        'La ruta no puede repetir establecimientos: ${duplicados.join(', ')}.',
      );
    }
  }

  Future<void> _validarEstablecimientosLibres(RutaDoc ruta) async {
    if (!ruta.activa) return;
    final keys = {
      for (final stop in ruta.stops)
        if (_establecimientoKey(stop).isNotEmpty) _establecimientoKey(stop),
    };
    if (keys.isEmpty) return;

    final rutas = await getRutas(ruta.empresaId);
    final conflictos = <String, String>{};
    for (final other in rutas) {
      if (!other.activa || other.id == ruta.id) continue;
      for (final stop in other.stops) {
        if (keys.contains(_establecimientoKey(stop))) {
          conflictos[stop.nombre] = other.codigo;
        }
      }
    }
    if (conflictos.isEmpty) return;

    final detalle = conflictos.entries
        .take(6)
        .map((e) => '${e.key} (${e.value})')
        .join(', ');
    throw ArgumentError(
      'Estos establecimientos ya están en otra ruta activa: $detalle.',
    );
  }

  // ─── RUTAS ─────────────────────────────────────────────────────────────────

  Stream<List<RutaDoc>> streamRutas(String empresaId) => _db
      .collection(_cRutas)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RutaDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.numero.compareTo(b.numero));
        return list;
      });

  Future<List<RutaDoc>> getRutas(String empresaId) async {
    final s = await _db
        .collection(_cRutas)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final list = s.docs.map((d) => RutaDoc.fromMap(d.id, d.data())).toList();
    list.sort((a, b) => a.numero.compareTo(b.numero));
    return list;
  }

  Future<RutaDoc?> getRuta(String id) async {
    final d = await _db.collection(_cRutas).doc(id).get();
    if (!d.exists) return null;
    return RutaDoc.fromMap(d.id, d.data()!);
  }

  Future<String> guardarRuta(RutaDoc ruta, {required bool isNew}) async {
    final ref = isNew
        ? _db.collection(_cRutas).doc()
        : _db.collection(_cRutas).doc(ruta.id);
    final doc = ruta.copyWith(id: ref.id);
    _validarRutaSinDuplicadosInternos(doc);
    await _validarEstablecimientosLibres(doc);
    await ref.set(doc.toMap(), SetOptions(merge: true));
    if (!doc.activa) {
      await liberarRuta(doc.empresaId, doc.id);
    }
    return ref.id;
  }

  Future<void> eliminarRuta(String id) async {
    final rutaRef = _db.collection(_cRutas).doc(id);
    final rutaSnap = await rutaRef.get();
    final empresaId = (rutaSnap.data()?['empresaId'] ?? '').toString();
    final batch = _db.batch()..delete(rutaRef);
    if (empresaId.isNotEmpty) {
      final activas = await _db
          .collection(_cAsignaciones)
          .where('empresaId', isEqualTo: empresaId)
          .where('rutaId', isEqualTo: id)
          .where('activa', isEqualTo: true)
          .get();
      final ahora = Timestamp.now();
      for (final asignacion in activas.docs) {
        batch.update(asignacion.reference, {
          'activa': false,
          'vigenteHasta': ahora,
          'closedByRouteDeletion': true,
        });
      }
    }
    await batch.commit();
  }

  Future<void> cambiarEstadoRuta(RutaDoc ruta, bool activa) async {
    final doc = ruta.copyWith(activa: activa);
    if (activa) {
      _validarRutaSinDuplicadosInternos(doc);
      await _validarEstablecimientosLibres(doc);
    }
    await _db.collection(_cRutas).doc(ruta.id).set({
      'activa': activa,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!activa) {
      await liberarRuta(ruta.empresaId, ruta.id);
    }
  }

  Future<String> combinarRutas({
    required String empresaId,
    required String codigo,
    required List<RutaDoc> rutas,
    bool desactivarOriginales = true,
    String creadoPor = '',
  }) async {
    final eid = empresaId.trim();
    final seleccionadas = rutas
        .where((r) => r.empresaId == eid && r.stops.isNotEmpty)
        .toList();
    if (eid.isEmpty || seleccionadas.length < 2) {
      throw ArgumentError(
        'Selecciona al menos dos rutas con establecimientos.',
      );
    }
    if (!desactivarOriginales) {
      throw ArgumentError(
        'Para evitar establecimientos duplicados, la combinación debe desactivar las rutas originales.',
      );
    }

    final stops = <RutaStop>[];
    for (final ruta in seleccionadas) {
      for (final stop in ruta.stops) {
        stops.add(stop.copyWith(orden: stops.length + 1));
      }
    }

    final now = Timestamp.now();
    final ref = _db.collection(_cRutas).doc();
    final nueva = RutaDoc(
      id: ref.id,
      empresaId: eid,
      codigo: codigo.trim().isEmpty ? 'Ruta combinada' : codigo.trim(),
      stops: stops,
      activa: true,
      createdAt: now,
    );

    final batch = _db.batch();
    batch.set(ref, {
      ...nueva.toMap(),
      'origen': 'combinacion_rutas',
      'rutasOrigen': seleccionadas
          .map((r) => {'id': r.id, 'codigo': r.codigo})
          .toList(),
      'createdBy': creadoPor,
      'createdAt': now,
    }, SetOptions(merge: true));

    if (desactivarOriginales) {
      for (final ruta in seleccionadas) {
        batch.update(_db.collection(_cRutas).doc(ruta.id), {
          'activa': false,
          'mergedInto': ref.id,
          'mergedAt': now,
        });
      }
    }

    await batch.commit();
    return ref.id;
  }

  Future<RutasSyncResult> sincronizarRutasDesdeExcel({
    required String empresaId,
    required List<RutaExcelRow> filas,
    String sourceName = '',
  }) async {
    final eid = empresaId.trim();
    if (eid.isEmpty || filas.isEmpty) {
      return RutasSyncResult(
        total: 0,
        created: 0,
        updated: 0,
        skipped: filas.length,
      );
    }

    final now = Timestamp.now();
    final validas = filas
        .where((f) => f.sede.trim().isNotEmpty || f.direccion.trim().isNotEmpty)
        .toList();
    final refs = [
      for (final fila in validas)
        _db.collection(_cRutas).doc(_rutaCatalogoDocId(eid, fila)),
    ];
    final existing = await Future.wait(refs.map((r) => r.get()));
    var created = 0;
    var updated = 0;

    final batch = _db.batch();
    for (var i = 0; i < validas.length; i++) {
      final fila = validas[i];
      final exists = existing[i].exists;
      if (exists) {
        updated++;
      } else {
        created++;
      }

      final ruta = RutaDoc(
        id: refs[i].id,
        empresaId: eid,
        codigo: fila.codigo,
        stops: [fila.toStop()],
        activa: true,
        createdAt: exists
            ? (existing[i].data()?['createdAt'] as Timestamp? ?? now)
            : now,
      );

      batch.set(refs[i], {
        ...ruta.toMap(),
        'origen': 'excel_rutas',
        'importSource': sourceName,
        'importKey': _rutaCatalogoKey(fila),
        'excelRowNumber': fila.excelRowNumber,
        'distanciaCentroKm': fila.distanciaKm,
        'rangoDistancia': fila.rango,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return RutasSyncResult(
      total: validas.length,
      created: created,
      updated: updated,
      skipped: filas.length - validas.length,
    );
  }

  String _rutaCatalogoDocId(String empresaId, RutaExcelRow fila) {
    return '${empresaId}_${_rutaCatalogoKey(fila)}';
  }

  String _rutaCatalogoKey(RutaExcelRow fila) {
    final number = fila.numero;
    if (number != null) {
      return 'ruta_${number.toString().padLeft(3, '0')}';
    }
    final slug = fila.sede
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'ruta_${slug.isEmpty ? fila.excelRowNumber : slug}';
  }

  // ─── ASIGNACIONES (personal por ruta, con histórico) ────────────────────────

  /// Asignaciones vigentes de la empresa (una por ruta como máximo).
  Stream<List<RutaAsignacionDoc>> streamAsignacionesActivas(String empresaId) =>
      _db
          .collection(_cAsignaciones)
          .where('empresaId', isEqualTo: empresaId)
          .where('activa', isEqualTo: true)
          .snapshots()
          .map(
            (s) => s.docs
                .map((d) => RutaAsignacionDoc.fromMap(d.id, d.data()))
                .toList(),
          );

  Future<List<RutaAsignacionDoc>> getAsignacionesActivas(
    String empresaId,
  ) async {
    final s = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: empresaId)
        .where('activa', isEqualTo: true)
        .get();
    return s.docs
        .map((d) => RutaAsignacionDoc.fromMap(d.id, d.data()))
        .toList();
  }

  Future<List<RutaAsignacionDoc>> getAsignacionesEmpresa(
    String empresaId,
  ) async {
    final s = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final list = s.docs
        .map((d) => RutaAsignacionDoc.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) {
      final byRuta = a.rutaCodigo.compareTo(b.rutaCodigo);
      if (byRuta != 0) return byRuta;
      return b.vigenteDesde.compareTo(a.vigenteDesde);
    });
    return list;
  }

  Future<List<RutaAsignacionDoc>> asignacionesEnFecha({
    required String empresaId,
    required DateTime fecha,
  }) async {
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    final historial = await getAsignacionesEmpresa(empresaId);
    final list = historial.where((a) {
      final desde = a.vigenteDesde.toDate();
      final hasta = a.vigenteHasta?.toDate();
      final empezoAntesDeCerrarDia = desde.isBefore(fin);
      final seguiaVigenteAlIniciarDia =
          hasta == null || !hasta.isBefore(inicio);
      return empezoAntesDeCerrarDia && seguiaVigenteAlIniciarDia;
    }).toList();
    list.sort((a, b) => a.rutaCodigo.compareTo(b.rutaCodigo));
    return list;
  }

  /// Histórico completo de una ruta (vigentes y cerradas), recientes primero.
  Future<List<RutaAsignacionDoc>> historialAsignaciones(
    String empresaId,
    String rutaId,
  ) async {
    final s = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: empresaId)
        .where('rutaId', isEqualTo: rutaId)
        .get();
    final list = s.docs
        .map((d) => RutaAsignacionDoc.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) => b.vigenteDesde.compareTo(a.vigenteDesde));
    return list;
  }

  /// Asignación vigente de un conductor (su "ruta de hoy").
  Future<RutaAsignacionDoc?> asignacionVigenteDeConductor(
    String empresaId,
    String conductorCedula,
  ) async {
    final s = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: empresaId)
        .where('conductorCedula', isEqualTo: conductorCedula)
        .where('activa', isEqualTo: true)
        .get();
    if (s.docs.isEmpty) return null;
    for (final doc in s.docs) {
      final asignacion = RutaAsignacionDoc.fromMap(doc.id, doc.data());
      final ruta = await getRuta(asignacion.rutaId);
      if (ruta != null && ruta.activa) return asignacion;
    }
    return null;
  }

  /// Asigna personal a una ruta cerrando la asignación vigente previa de esa
  /// ruta (queda como histórico) y abriendo la nueva, todo en un batch.
  Future<void> asignarRuta(RutaAsignacionDoc nueva) async {
    final batch = _db.batch();
    final ahora = Timestamp.now();
    final activasEmpresa = await getAsignacionesActivas(nueva.empresaId);
    final rutasEmpresa = await getRutas(nueva.empresaId);
    final rutaIdsValidos = rutasEmpresa.map((r) => r.id).toSet();

    String clean(String value) => value.trim().toLowerCase();
    String cleanPlate(String value) => value.trim().toUpperCase();

    bool sameUser(String a, String b) {
      final aa = clean(a);
      final bb = clean(b);
      return aa.isNotEmpty && bb.isNotEmpty && aa == bb;
    }

    bool samePlate(String a, String b) {
      final aa = cleanPlate(a);
      final bb = cleanPlate(b);
      return aa.isNotEmpty && bb.isNotEmpty && aa == bb;
    }

    final personasNuevas = [
      nueva.conductorCedula,
      nueva.ayudanteCedula,
      nueva.ayudante2Cedula,
    ].map(clean).where((id) => id.isNotEmpty).toList();
    if (personasNuevas.toSet().length != personasNuevas.length) {
      throw ArgumentError(
        'El conductor y los ayudantes deben ser personas diferentes.',
      );
    }

    for (final actual in activasEmpresa) {
      if (!rutaIdsValidos.contains(actual.rutaId)) {
        batch.update(_db.collection(_cAsignaciones).doc(actual.id), {
          'activa': false,
          'vigenteHasta': ahora,
          'closedByMissingRoute': true,
        });
        continue;
      }
      if (actual.rutaId == nueva.rutaId) continue;
      final ocupados = [
        actual.conductorCedula,
        actual.ayudanteCedula,
        actual.ayudante2Cedula,
      ];
      if (ocupados.any((u) => sameUser(u, nueva.conductorCedula))) {
        throw ArgumentError(
          'El conductor seleccionado ya está asignado a ${actual.rutaCodigo}.',
        );
      }
      if (nueva.ayudanteCedula.trim().isNotEmpty &&
          ocupados.any((u) => sameUser(u, nueva.ayudanteCedula))) {
        throw ArgumentError(
          'El ayudante seleccionado ya está asignado a ${actual.rutaCodigo}.',
        );
      }
      if (nueva.ayudante2Cedula.trim().isNotEmpty &&
          ocupados.any((u) => sameUser(u, nueva.ayudante2Cedula))) {
        throw ArgumentError(
          'El segundo ayudante ya está asignado a ${actual.rutaCodigo}.',
        );
      }
      if (samePlate(actual.vehiculo, nueva.vehiculo)) {
        throw ArgumentError(
          'La placa seleccionada ya está asignada a ${actual.rutaCodigo}.',
        );
      }
    }

    // Cerrar asignaciones vigentes de la MISMA ruta.
    final activasRuta = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: nueva.empresaId)
        .where('rutaId', isEqualTo: nueva.rutaId)
        .where('activa', isEqualTo: true)
        .get();
    for (final d in activasRuta.docs) {
      batch.update(d.reference, {'activa': false, 'vigenteHasta': ahora});
    }

    final ref = _db.collection(_cAsignaciones).doc();
    batch.set(
      ref,
      nueva
          .copyWith(activa: true, vigenteDesde: ahora, createdAt: ahora)
          .toMap(),
    );
    await batch.commit();
  }

  /// Mueve una asignación vigente a otra ruta libre, conservando conductor,
  /// ayudante y placa. La ruta anterior queda disponible.
  Future<void> relevarAsignacion({
    required RutaAsignacionDoc actual,
    required RutaDoc nuevaRuta,
    required String asignadoPor,
  }) async {
    if (!actual.activa) {
      throw ArgumentError('La asignación seleccionada ya no está vigente.');
    }
    if (!nuevaRuta.activa) {
      throw ArgumentError('La ruta destino está deshabilitada.');
    }
    if (actual.rutaId == nuevaRuta.id) {
      throw ArgumentError('Selecciona una ruta diferente para el relevo.');
    }

    final activasEmpresa = await getAsignacionesActivas(actual.empresaId);
    for (final a in activasEmpresa) {
      if (a.rutaId == actual.rutaId || a.rutaId == nuevaRuta.id) continue;
      final personas = [
        a.conductorCedula.trim().toLowerCase(),
        a.ayudanteCedula.trim().toLowerCase(),
        a.ayudante2Cedula.trim().toLowerCase(),
      ].where((v) => v.isNotEmpty).toSet();
      final conductor = actual.conductorCedula.trim().toLowerCase();
      final ayudante = actual.ayudanteCedula.trim().toLowerCase();
      final ayudante2 = actual.ayudante2Cedula.trim().toLowerCase();
      if (personas.contains(conductor) ||
          (ayudante.isNotEmpty && personas.contains(ayudante)) ||
          (ayudante2.isNotEmpty && personas.contains(ayudante2))) {
        throw ArgumentError(
          'La persona del relevo ya está asignada a ${a.rutaCodigo}.',
        );
      }
      final placaActual = actual.vehiculo.trim().toUpperCase();
      if (placaActual.isNotEmpty &&
          a.vehiculo.trim().toUpperCase() == placaActual) {
        throw ArgumentError(
          'La placa del relevo ya está asignada a ${a.rutaCodigo}.',
        );
      }
    }

    final batch = _db.batch();
    final ahora = Timestamp.now();

    final activasOrigen = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: actual.empresaId)
        .where('rutaId', isEqualTo: actual.rutaId)
        .where('activa', isEqualTo: true)
        .get();
    for (final d in activasOrigen.docs) {
      batch.update(d.reference, {'activa': false, 'vigenteHasta': ahora});
    }

    final activasDestino = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: actual.empresaId)
        .where('rutaId', isEqualTo: nuevaRuta.id)
        .where('activa', isEqualTo: true)
        .get();
    for (final d in activasDestino.docs) {
      batch.update(d.reference, {'activa': false, 'vigenteHasta': ahora});
    }

    final ref = _db.collection(_cAsignaciones).doc();
    batch.set(
      ref,
      RutaAsignacionDoc(
        empresaId: actual.empresaId,
        rutaId: nuevaRuta.id,
        rutaCodigo: nuevaRuta.codigo,
        conductorCedula: actual.conductorCedula,
        conductorNombre: actual.conductorNombre,
        ayudanteCedula: actual.ayudanteCedula,
        ayudanteNombre: actual.ayudanteNombre,
        ayudante2Cedula: actual.ayudante2Cedula,
        ayudante2Nombre: actual.ayudante2Nombre,
        vehiculo: actual.vehiculo,
        asignadoPor: asignadoPor,
        vigenteDesde: ahora,
        createdAt: ahora,
      ).toMap(),
    );

    await batch.commit();
  }

  /// Relevo POR PERSONAS: pone al conductor/ayudante/placa elegidos en la ruta
  /// [destino], liberando cualquier ruta donde esas personas o esa placa estén
  /// vigentes, y cerrando la asignación previa de la ruta destino. Conserva el
  /// histórico (cierra lo viejo con vigenteHasta, abre uno nuevo).
  Future<void> relevarPersonalARuta({
    required RutaDoc destino,
    required String empresaId,
    required String conductorCedula,
    required String conductorNombre,
    String ayudanteCedula = '',
    String ayudanteNombre = '',
    String ayudante2Cedula = '',
    String ayudante2Nombre = '',
    String vehiculo = '',
    required String asignadoPor,
  }) async {
    if (!destino.activa) {
      throw ArgumentError('La ruta destino está deshabilitada.');
    }
    if (conductorCedula.trim().isEmpty) {
      throw ArgumentError('Selecciona un conductor para el relevo.');
    }

    final ahora = Timestamp.now();
    final placa = vehiculo.trim().toUpperCase();
    final elegidas = <String>{
      conductorCedula.trim().toLowerCase(),
      if (ayudanteCedula.trim().isNotEmpty) ayudanteCedula.trim().toLowerCase(),
      if (ayudante2Cedula.trim().isNotEmpty)
        ayudante2Cedula.trim().toLowerCase(),
    };
    final personasElegidas = [
      conductorCedula,
      ayudanteCedula,
      ayudante2Cedula,
    ].map((id) => id.trim().toLowerCase()).where((id) => id.isNotEmpty);
    if (personasElegidas.toSet().length != personasElegidas.length) {
      throw ArgumentError(
        'El conductor y los ayudantes deben ser personas diferentes.',
      );
    }

    final activas = await getAsignacionesActivas(empresaId);
    final batch = _db.batch();

    for (final a in activas) {
      if (a.id.isEmpty) continue;
      final personas = <String>{
        a.conductorCedula.trim().toLowerCase(),
        a.ayudanteCedula.trim().toLowerCase(),
        a.ayudante2Cedula.trim().toLowerCase(),
      }..removeWhere((e) => e.isEmpty);
      final chocaPersona = personas.any(elegidas.contains);
      final chocaPlaca =
          placa.isNotEmpty && a.vehiculo.trim().toUpperCase() == placa;
      if (a.rutaId == destino.id || chocaPersona || chocaPlaca) {
        batch.update(_db.collection(_cAsignaciones).doc(a.id), {
          'activa': false,
          'vigenteHasta': ahora,
        });
      }
    }

    final ref = _db.collection(_cAsignaciones).doc();
    batch.set(
      ref,
      RutaAsignacionDoc(
        empresaId: empresaId,
        rutaId: destino.id,
        rutaCodigo: destino.codigo,
        conductorCedula: conductorCedula.trim(),
        conductorNombre: conductorNombre.trim(),
        ayudanteCedula: ayudanteCedula.trim(),
        ayudanteNombre: ayudanteNombre.trim(),
        ayudante2Cedula: ayudante2Cedula.trim(),
        ayudante2Nombre: ayudante2Nombre.trim(),
        vehiculo: vehiculo.trim(),
        asignadoPor: asignadoPor,
        vigenteDesde: ahora,
        createdAt: ahora,
      ).toMap(),
    );

    await batch.commit();
  }

  /// Libera una ruta (cierra su asignación vigente sin abrir otra).
  Future<void> liberarRuta(String empresaId, String rutaId) async {
    final activas = await _db
        .collection(_cAsignaciones)
        .where('empresaId', isEqualTo: empresaId)
        .where('rutaId', isEqualTo: rutaId)
        .where('activa', isEqualTo: true)
        .get();
    final batch = _db.batch();
    final ahora = Timestamp.now();
    for (final d in activas.docs) {
      batch.update(d.reference, {'activa': false, 'vigenteHasta': ahora});
    }
    await batch.commit();
  }

  // ─── UBICACION / CENTRO DE CONTROL ────────────────────────────────────────

  Stream<List<RutaUbicacionDoc>> streamUbicaciones(String empresaId) => _db
      .collection(_cUbicaciones)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RutaUbicacionDoc.fromMap(d.id, d.data()))
            .where((u) => u.lat != 0 && u.lng != 0)
            .toList();
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return list;
      });

  Future<void> actualizarUbicacionConductor({
    required String empresaId,
    required String userId,
    required double lat,
    required double lng,
    RutaDoc? ruta,
    RutaAsignacionDoc? asignacion,
    RutaStop? parada,
    double? precisionMetros,
    String direccion = '',
  }) async {
    final eid = empresaId.trim();
    final uid = userId.trim();
    if (eid.isEmpty || uid.isEmpty) return;
    final docId = '${eid}_$uid'.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await _db.collection(_cUbicaciones).doc(docId).set({
      'empresaId': eid,
      'userId': uid,
      'rutaId': ruta?.id ?? asignacion?.rutaId ?? '',
      'rutaCodigo': ruta?.codigo ?? asignacion?.rutaCodigo ?? '',
      'conductorCedula': asignacion?.conductorCedula ?? uid,
      'conductorNombre': asignacion?.conductorNombre ?? '',
      'vehiculo': asignacion?.vehiculo ?? '',
      'paradaNombre': parada?.nombre ?? '',
      'lat': lat,
      'lng': lng,
      'precisionMetros': precisionMetros,
      'direccion': direccion,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // ─── CONFIG ──────────────────────────────────────────────────────────────

  Future<RutaConfigDoc> getConfig(String empresaId) async {
    final d = await _db.collection(_cConfig).doc(empresaId).get();
    if (!d.exists) return RutaConfigDoc.defaults(empresaId);
    return RutaConfigDoc.fromMap(d.id, d.data()!);
  }

  Stream<RutaConfigDoc> streamConfig(String empresaId) => _db
      .collection(_cConfig)
      .doc(empresaId)
      .snapshots()
      .map(
        (d) => d.exists
            ? RutaConfigDoc.fromMap(d.id, d.data()!)
            : RutaConfigDoc.defaults(empresaId),
      );

  Future<void> guardarConfig(RutaConfigDoc config) => _db
      .collection(_cConfig)
      .doc(config.empresaId)
      .set(config.toMap(), SetOptions(merge: true));

  Future<void> asegurarConfigBase(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return;
    final ref = _db.collection(_cConfig).doc(id);
    final doc = await ref.get();
    if (doc.exists) return;
    await ref.set(RutaConfigDoc.defaults(id).toMap(), SetOptions(merge: true));
  }

  // ─── MAESTRO DE VEHICULOS / PLACAS ───────────────────────────────────────

  Stream<List<RutaVehiculoDoc>> streamVehiculos(String empresaId) => _db
      .collection(_cVehiculos)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RutaVehiculoDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          if (a.activo != b.activo) return a.activo ? -1 : 1;
          return a.placa.compareTo(b.placa);
        });
        return list;
      });

  Future<List<RutaVehiculoDoc>> getVehiculos(String empresaId) async {
    final s = await _db
        .collection(_cVehiculos)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final list = s.docs
        .map((d) => RutaVehiculoDoc.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) {
      if (a.activo != b.activo) return a.activo ? -1 : 1;
      return a.placa.compareTo(b.placa);
    });
    return list;
  }

  Future<String> guardarVehiculo(
    RutaVehiculoDoc vehiculo, {
    required bool isNew,
  }) async {
    final placa = vehiculo.placa.trim().toUpperCase();
    final docId = isNew
        ? '${vehiculo.empresaId}_$placa'.replaceAll(
            RegExp(r'[^A-Z0-9_-]+'),
            '_',
          )
        : vehiculo.id;
    final ref = _db.collection(_cVehiculos).doc(docId);
    final previous = await ref.get();
    final previousData = previous.data();
    final wasActive = previousData?['activo'] as bool? ?? false;
    final data = vehiculo.copyWith(placa: placa).toMap();
    if (previous.exists && previousData?['createdAt'] is Timestamp) {
      data['createdAt'] = previousData!['createdAt'];
    }
    if (!vehiculo.activo && (wasActive || !previous.exists)) {
      data['inactivatedAt'] = FieldValue.serverTimestamp();
    } else if (vehiculo.activo) {
      data['inactivatedAt'] = null;
      if (previous.exists && !wasActive) {
        data['reactivatedAt'] = FieldValue.serverTimestamp();
      }
    }
    await ref.set(data, SetOptions(merge: true));
    return ref.id;
  }

  /// Retira la placa de nuevas asignaciones, conservándola como historial.
  Future<void> eliminarVehiculo(String id) =>
      _db.collection(_cVehiculos).doc(id).set({
        'activo': false,
        'inactivatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> reactivarVehiculo(String id) =>
      _db.collection(_cVehiculos).doc(id).set({
        'activo': true,
        'inactivatedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ─── EVIDENCIAS ────────────────────────────────────────────────────────────

  /// Evidencias de un establecimiento concreto en un día (para validar la secuencia).
  Future<List<RutaEvidenciaDoc>> evidenciasDePunto({
    required String empresaId,
    required String rutaId,
    required String fecha,
    required String paradaNombre,
  }) async {
    final s = await _db
        .collection(_cEvidencias)
        .where('empresaId', isEqualTo: empresaId)
        .where('rutaId', isEqualTo: rutaId)
        .where('fecha', isEqualTo: fecha)
        .where('paradaNombre', isEqualTo: paradaNombre)
        .get();
    return s.docs.map((d) => RutaEvidenciaDoc.fromMap(d.id, d.data())).toList();
  }

  /// Conjunto de comidas YA registradas y NO rechazadas en un establecimiento/día.
  /// Alimenta [RutasLogic.puedeTomarComida].
  Future<Set<String>> comidasNoRechazadasDelPunto({
    required String empresaId,
    required String rutaId,
    required String fecha,
    required String paradaNombre,
  }) async {
    final evid = await evidenciasDePunto(
      empresaId: empresaId,
      rutaId: rutaId,
      fecha: fecha,
      paradaNombre: paradaNombre,
    );
    return evid.where((e) => !e.rechazada).map((e) => e.comida).toSet();
  }

  /// Sube la evidencia (imagen ya con marca de agua) y registra el documento.
  /// Es ATÓMICO desde el punto de vista del usuario: solo retorna si la imagen
  /// quedó en Storage Y el documento en Firestore (a diferencia de FYC, donde
  /// el metadato era fire-and-forget y dejaba fotos huérfanas).
  Future<RutaEvidenciaDoc> subirEvidencia({
    required String empresaId,
    required RutaDoc ruta,
    required RutaStop parada,
    required String comida,
    required int menuNumero,
    RutaAsignacionDoc? asignacion,
    double? capturaLat,
    double? capturaLng,
    String capturaTexto = '',
    required Uint8List imagenBytes,
    Uint8List? thumbBytes,
    required String createdBy,
    String ext = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    final ahora = DateTime.now();
    final fecha = RutasLogic.fechaKey(ahora);

    final docId = RutasLogic.evidenciaDocId(
      empresaId: empresaId,
      rutaId: ruta.id,
      fecha: fecha,
      paradaNombre: parada.nombre,
      comida: comida,
    );

    RutaEvidenciaDoc? anteriorRechazada;
    final docRef = _db.collection(_cEvidencias).doc(docId);
    final existenteSnap = await docRef.get();
    if (existenteSnap.exists) {
      final existente = RutaEvidenciaDoc.fromMap(
        existenteSnap.id,
        existenteSnap.data()!,
      );
      if (!existente.rechazada) {
        throw Exception(
          'Ya existe una foto de $comida para ${parada.nombre}. '
          'Solo se puede repetir si Calidad la rechaza.',
        );
      }
      anteriorRechazada = existente;
    }

    final path = RutasLogic.storagePath(
      empresaId: empresaId,
      fecha: ahora,
      paradaNombre: parada.nombre,
      comida: comida,
      timestampMs: ahora.millisecondsSinceEpoch,
      ext: ext,
    );

    final ref = _storage.ref().child(path);
    await ref.putData(imagenBytes, SettableMetadata(contentType: contentType));
    final downloadURL = await ref.getDownloadURL();

    String? thumbPath;
    String? thumbURL;
    if (thumbBytes != null) {
      thumbPath = '$path.thumb.jpg';
      final thumbRef = _storage.ref().child(thumbPath);
      await thumbRef.putData(
        thumbBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      thumbURL = await thumbRef.getDownloadURL();
    }

    final distancia = RutasLogic.distanciaMetros(
      capturaLat,
      capturaLng,
      parada.lat,
      parada.lng,
    );

    final evidencia = RutaEvidenciaDoc(
      id: docId,
      empresaId: empresaId,
      rutaId: ruta.id,
      rutaCodigo: ruta.codigo,
      fecha: fecha,
      year: ahora.year.toString().padLeft(4, '0'),
      month: ahora.month.toString().padLeft(2, '0'),
      day: ahora.day.toString().padLeft(2, '0'),
      comida: comida,
      menuNumero: menuNumero,
      paradaNombre: parada.nombre,
      paradaDireccion: parada.direccionVisible,
      paradaLat: parada.lat,
      paradaLng: parada.lng,
      conductorCedula: asignacion?.conductorCedula ?? '',
      conductorNombre: asignacion?.conductorNombre ?? '',
      ayudanteCedula: asignacion?.ayudanteCedula ?? '',
      ayudanteNombre: asignacion?.ayudanteNombre ?? '',
      ayudante2Cedula: asignacion?.ayudante2Cedula ?? '',
      ayudante2Nombre: asignacion?.ayudante2Nombre ?? '',
      vehiculo: asignacion?.vehiculo ?? '',
      capturaLat: capturaLat,
      capturaLng: capturaLng,
      capturaTexto: capturaTexto,
      distanciaMetros: distancia,
      storagePath: path,
      downloadURL: downloadURL,
      thumbPath: thumbPath,
      thumbURL: thumbURL,
      estado: kEvidPendiente,
      createdBy: createdBy,
      createdAt: Timestamp.fromDate(ahora),
    );

    // set sin merge: una re-toma permitida por rechazo reemplaza el doc y
    // reinicia la revisión.
    await docRef.set(evidencia.toMap());
    if (anteriorRechazada != null) {
      await Future.wait([
        _deleteStoragePath(anteriorRechazada.storagePath),
        _deleteStoragePath(anteriorRechazada.thumbPath),
      ]);
    }
    return evidencia;
  }

  Future<void> _deleteStoragePath(String? path) async {
    final clean = (path ?? '').trim();
    if (clean.isEmpty) return;
    try {
      await _storage.ref().child(clean).delete();
    } catch (_) {}
  }

  /// Stream de evidencias con filtros de IGUALDAD server-side (sin índices
  /// compuestos) + orden por fecha de creación descendente en cliente.
  /// Pasa solo los filtros que el usuario seleccionó; el resto en null.
  Stream<List<RutaEvidenciaDoc>> streamEvidencias({
    required String empresaId,
    String? fecha,
    String? year,
    String? month,
    String? day,
    String? estado,
    String? rutaId,
    String? comida,
    String? paradaNombre,
    String? conductorCedula,
    int limit = 600,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection(_cEvidencias)
        .where('empresaId', isEqualTo: empresaId);

    if (fecha != null) q = q.where('fecha', isEqualTo: fecha);
    if (year != null) q = q.where('year', isEqualTo: year);
    if (month != null) q = q.where('month', isEqualTo: month);
    if (day != null) q = q.where('day', isEqualTo: day);
    if (estado != null) q = q.where('estado', isEqualTo: estado);
    if (rutaId != null) q = q.where('rutaId', isEqualTo: rutaId);
    if (comida != null) q = q.where('comida', isEqualTo: comida);
    if (paradaNombre != null) {
      q = q.where('paradaNombre', isEqualTo: paradaNombre);
    }
    if (conductorCedula != null) {
      q = q.where('conductorCedula', isEqualTo: conductorCedula);
    }
    q = q.limit(limit);

    return q.snapshots().map((s) {
      final list = s.docs
          .map((d) => RutaEvidenciaDoc.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> aprobarEvidencia({
    required String evidenciaId,
    required String revisadoPor,
  }) async {
    await _db.collection(_cEvidencias).doc(evidenciaId).update({
      'estado': kEvidAprobada,
      'revisadoPor': revisadoPor,
      'revisadoEn': Timestamp.now(),
      'motivoRechazo': '',
    });
  }

  Future<void> eliminarEvidencia(RutaEvidenciaDoc evidencia) async {
    await Future.wait([
      _deleteStoragePath(evidencia.storagePath),
      _deleteStoragePath(evidencia.thumbPath),
    ]);
    await _db.collection(_cEvidencias).doc(evidencia.id).delete();
  }

  Future<RutasCleanupResult> limpiarHistorialEvidenciasEmpresa(
    String empresaId,
  ) async {
    final eid = empresaId.trim();
    if (eid.isEmpty) {
      return const RutasCleanupResult(evidencias: 0, resumenes: 0);
    }

    Future<void> deleteStoragePath(String? path) async {
      final clean = (path ?? '').trim();
      if (clean.isEmpty) return;
      try {
        await _storage.ref().child(clean).delete();
      } catch (_) {}
    }

    final evidSnap = await _db
        .collection(_cEvidencias)
        .where('empresaId', isEqualTo: eid)
        .get();
    await Future.wait(
      evidSnap.docs.map((d) {
        final e = RutaEvidenciaDoc.fromMap(d.id, d.data());
        return Future.wait([
          deleteStoragePath(e.storagePath),
          deleteStoragePath(e.thumbPath),
        ]);
      }),
    );

    Future<void> deleteDocs(Iterable<DocumentReference> refs) async {
      var batch = _db.batch();
      var ops = 0;
      for (final ref in refs) {
        batch.delete(ref);
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    }

    await deleteDocs(evidSnap.docs.map((d) => d.reference));

    final resumenSnap = await _db
        .collection(_cResumen)
        .where('empresaId', isEqualTo: eid)
        .get();
    await deleteDocs(resumenSnap.docs.map((d) => d.reference));

    return RutasCleanupResult(
      evidencias: evidSnap.docs.length,
      resumenes: resumenSnap.docs.length,
    );
  }

  /// Rechaza una evidencia y notifica a la persona que subio la foto.
  Future<void> rechazarEvidencia({
    required RutaEvidenciaDoc evidencia,
    required String revisadoPor,
    required String revisadoPorNombre,
    required String motivo,
  }) async {
    await _db.collection(_cEvidencias).doc(evidencia.id).update({
      'estado': kEvidRechazada,
      'revisadoPor': revisadoPor,
      'revisadoEn': Timestamp.now(),
      'motivoRechazo': motivo,
    });

    final destino = evidencia.createdBy.trim().isNotEmpty
        ? evidencia.createdBy.trim()
        : evidencia.conductorCedula.trim();
    if (destino.isEmpty) return;

    await _tasks.pushNotification(
      toUserId: destino,
      title: 'Foto rechazada: ${evidencia.rutaCodigo}',
      description:
          '${evidencia.paradaNombre} · ${evidencia.comida}. Motivo: $motivo',
      type: 'rutas_evidencia_rechazada',
      fromId: revisadoPor,
      fromName: revisadoPorNombre,
      empresaId: evidencia.empresaId,
      extraData: {
        'module': 'rutas',
        'rutaId': evidencia.rutaId,
        'paradaNombre': evidencia.paradaNombre,
        'comida': evidencia.comida,
        'fecha': evidencia.fecha,
        'evidenciaId': evidencia.id,
        'uploadedBy': evidencia.createdBy,
        'conductorCedula': evidencia.conductorCedula,
      },
    );
  }

  // ─── RESUMEN DIARIO (lectura; lo escribe la Cloud Function) ─────────────────

  Future<List<RutaResumenDiarioDoc>> resumenPorRango({
    required String empresaId,
    required String fechaDesde, // yyyy-MM-dd inclusive
    required String fechaHasta, // yyyy-MM-dd inclusive
  }) async {
    // fecha es string ordenable (yyyy-MM-dd) → un solo campo admite rango.
    final s = await _db
        .collection(_cResumen)
        .where('empresaId', isEqualTo: empresaId)
        .where('fecha', isGreaterThanOrEqualTo: fechaDesde)
        .where('fecha', isLessThanOrEqualTo: fechaHasta)
        .get();
    final list = s.docs
        .map((d) => RutaResumenDiarioDoc.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) {
      final byFecha = a.fecha.compareTo(b.fecha);
      return byFecha != 0 ? byFecha : a.rutaCodigo.compareTo(b.rutaCodigo);
    });
    return list;
  }

  // ─── ROLES ─────────────────────────────────────────────────────────────────

  Future<RutaRolDoc?> getRolUsuario(String empresaId, String userId) async {
    final byUserId = await _db
        .collection(_cRoles)
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (byUserId.docs.isNotEmpty) {
      return RutaRolDoc.fromMap(
        byUserId.docs.first.id,
        byUserId.docs.first.data(),
      );
    }
    final byCedula = await _db
        .collection(_cRoles)
        .where('empresaId', isEqualTo: empresaId)
        .where('cedula', isEqualTo: userId)
        .limit(1)
        .get();
    if (byCedula.docs.isEmpty) return null;
    return RutaRolDoc.fromMap(
      byCedula.docs.first.id,
      byCedula.docs.first.data(),
    );
  }

  Stream<List<RutaRolDoc>> streamRoles(String empresaId) => _db
      .collection(_cRoles)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RutaRolDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      });

  Future<void> guardarRol(RutaRolDoc rol, {required bool isNew}) async {
    final docId = isNew ? '${rol.empresaId}_${rol.userId}' : rol.id;
    await _db
        .collection(_cRoles)
        .doc(docId)
        .set(rol.toMap(), SetOptions(merge: true));
  }

  Future<void> eliminarRol(String id) =>
      _db.collection(_cRoles).doc(id).delete();
}
