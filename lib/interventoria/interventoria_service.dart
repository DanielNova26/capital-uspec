import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../core/festivos_colombia.dart';
import '../services/org_service.dart';
import '../services/task_service.dart';
import '../utils/user_company.dart';
import 'interventoria_models.dart';
import 'interventoria_numerales_catalogo.dart';

export 'interventoria_numerales_catalogo.dart';

// Re-exportamos Area para que el dashboard no tenga que importar org_service.dart
export '../services/org_service.dart' show Area;

class InterventoriaOcrResult {
  final DateTime? fechaVisita;
  final Map<String, InterventoriaItem> items;
  final String observaciones;
  final Map<String, dynamic> raw;

  const InterventoriaOcrResult({
    this.fechaVisita,
    required this.items,
    this.observaciones = '',
    this.raw = const {},
  });
}

/// Usuario de la empresa que puede recibir un hallazgo.
///
/// Se carga una sola vez por pantalla; resolver el cargo de cada hallazgo
/// contra esta lista es sincrónico, para no disparar una consulta por tarjeta.
class InterventoriaUsuario {
  final String id;
  final String nombre;
  final String cargo;
  final String centroId;
  final String areaId;

  const InterventoriaUsuario({
    required this.id,
    required this.nombre,
    required this.cargo,
    required this.centroId,
    required this.areaId,
  });
}

/// Persona concreta a la que se resolvió un cargo de la matriz de numerales.
class InterventoriaPersona {
  /// Cédula / doc ID en TBL_USUARIOS.
  final String id;
  final String nombre;

  /// Cargo tal como está escrito en el perfil del usuario.
  final String cargo;

  /// Cargo tal como lo nombra la matriz del acta.
  final String cargoMatriz;

  /// true si la persona pertenece al centro de costo del hallazgo; false si se
  /// resolvió a nivel empresa (cargos corporativos o sin titular en el centro).
  final bool delCentro;

  const InterventoriaPersona({
    required this.id,
    required this.nombre,
    required this.cargo,
    required this.cargoMatriz,
    required this.delCentro,
  });
}

/// Resultado de aplicar la matriz de responsabilidad a un numeral.
///
/// [responsable] y [aprobador] pueden venir en null cuando la empresa todavía
/// no tiene a nadie con ese cargo: el numeral sí se reconoció, pero no hay a
/// quién asignarle. La UI debe pedir asignación manual en ese caso.
class InterventoriaAsignacionSugerida {
  final String numeral;
  final String cargoResponsable;
  final String cargoAprobador;
  final InterventoriaPersona? responsable;
  final InterventoriaPersona? aprobador;

  /// Fecha límite calculada para la tarea.
  final DateTime fechaLimite;

  const InterventoriaAsignacionSugerida({
    required this.numeral,
    required this.cargoResponsable,
    required this.cargoAprobador,
    required this.responsable,
    required this.aprobador,
    required this.fechaLimite,
  });

  bool get completa => responsable != null;
}

class InterventoriaService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  InterventoriaService({FirebaseFirestore? db, FirebaseStorage? storage})
    : _db = db ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  Stream<List<CentroCostoRef>> streamCentrosCosto(String empresaId) => _db
      .collection('TBL_CENTROS_COSTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .where((d) => (d.data()['enabled'] as bool?) ?? true)
            .map((d) => CentroCostoRef.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          final byCode = a.codigo.compareTo(b.codigo);
          return byCode != 0 ? byCode : a.nombre.compareTo(b.nombre);
        });
        return list;
      });

  Stream<List<InterventoriaVisita>> streamVisitas(
    String empresaId, {
    String? centroId,
  }) {
    var q = _db
        .collection('TBL_INTERVENTORIA_VISITAS')
        .where('empresaId', isEqualTo: empresaId);
    if (centroId != null && centroId.isNotEmpty) {
      q = q.where('centroCostoId', isEqualTo: centroId);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => InterventoriaVisita.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
      return list;
    });
  }

  /// Actas en Fase 1 completada — esperando revisión por Digitador/Gerente/Directivo.
  Stream<List<InterventoriaVisita>> streamActasPendientesRevision(
    String empresaId,
  ) {
    return _db
        .collection('TBL_INTERVENTORIA_VISITAS')
        .where('empresaId', isEqualTo: empresaId)
        .where('faseActa', isEqualTo: 'puntajes')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => InterventoriaVisita.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
          return list;
        });
  }

  /// Fase 2 — el revisor guarda un borrador (observaciones parciales) sin
  /// marcar el acta como completa. También auto-genera hallazgos para ítems
  /// con puntaje bajo que ya tengan observaciones.
  Future<void> guardarBorradorRevision({
    required InterventoriaVisita visita,
    required Map<String, InterventoriaItem> items,
    required String obsGenerales,
    required String conclusiones,
  }) async {
    final itemsMap = items.map((k, v) => MapEntry(k, v.toMap()));
    await _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visita.id).update({
      'itemsEvaluacion': itemsMap,
      'ocrDatosDetectados': {
        'observacionesGenerales': obsGenerales.trim(),
        'conclusiones': conclusiones.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
      // faseActa se mantiene en 'puntajes' — el acta sigue pendiente de completar
    });
    await _autoCrearHallazgosDesdeItems(visita: visita, items: items);
  }

  /// Reabre un acta marcada como 'completa' y la devuelve a 'puntajes' para
  /// que vuelva a aparecer en "Por revisar". Uso: admin deshace un
  /// "Completar acta" hecho por error, sin tocar los puntajes/observaciones
  /// ya guardados.
  Future<void> reabrirActaParaRevision(String visitaId) async {
    if (visitaId.isEmpty) return;
    await _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visitaId).update({
      'faseActa': 'puntajes',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fase 2 — el revisor completa el acta con observaciones y conclusiones.
  Future<void> completarActa({
    required InterventoriaVisita visita,
    required Map<String, InterventoriaItem> items,
    required String obsGenerales,
    required String conclusiones,
    String registradoPorId = '',
    String registradoPorNombre = '',
  }) async {
    final itemsMap = items.map((k, v) => MapEntry(k, v.toMap()));
    final obsTexto = [
      if (obsGenerales.trim().isNotEmpty)
        'Observaciones:\n${obsGenerales.trim()}',
      if (conclusiones.trim().isNotEmpty)
        'Conclusiones:\n${conclusiones.trim()}',
    ].join('\n');
    await _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visita.id).update({
      'itemsEvaluacion': itemsMap,
      'observaciones': obsTexto,
      'ocrDatosDetectados': {
        'observacionesGenerales': obsGenerales.trim(),
        'conclusiones': conclusiones.trim(),
      },
      'ocrRevisado':
          obsGenerales.trim().isNotEmpty || conclusiones.trim().isNotEmpty,
      'faseActa': 'completa',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Auto-crear/actualizar hallazgos para ítems con puntaje bajo
    await _autoCrearHallazgosDesdeItems(
      visita: visita,
      items: items,
      registradoPorId: registradoPorId,
      registradoPorNombre: registradoPorNombre,
    );
  }

  /// Sincroniza TBL_INTERVENTORIA_HALLAZGOS (fuente:'acta') con las
  /// observaciones actuales del formulario.
  ///
  /// Reglas:
  ///  • Un hallazgo por OBSERVACIÓN INDIVIDUAL (no por sección).
  ///  • Sin umbral de puntaje: cualquier observación genera hallazgo.
  ///  • Los hallazgos con tareaId != '' (ya asignados) se PRESERVAN.
  ///  • Los hallazgos huérfanos sin tareaId se eliminan.
  ///  • Los hallazgos existentes sin tareaId se actualizan in-place.
  Future<void> _autoCrearHallazgosDesdeItems({
    required InterventoriaVisita visita,
    required Map<String, InterventoriaItem> items,
    String registradoPorId = '',
    String registradoPorNombre = '',
  }) async {
    // ── 1. Cargar hallazgos 'acta' existentes para esta visita ───────────────
    final snap = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('visitaId', isEqualTo: visita.id)
        .where('fuente', isEqualTo: 'acta')
        .get();

    // grupoId → {docId, tareaId}
    final existing = <String, ({String docId, String tareaId})>{
      for (final doc in snap.docs)
        if ((doc.data()['grupoId'] ?? '').toString().isNotEmpty)
          doc.data()['grupoId'].toString(): (
            docId: doc.id,
            tareaId: (doc.data()['tareaId'] ?? '').toString(),
          ),
    };

    // ── 2. Índice de categoría para número de hallazgo (1-based) ─────────────
    final catIndex = <String, int>{
      for (int i = 0; i < kInterventoriaCategorias.length; i++)
        kInterventoriaCategorias[i].key: i + 1,
    };

    // ── 3. Procesar observaciones actuales ───────────────────────────────────
    final usedGrupoIds = <String>{};
    final batch = _db.batch();
    bool hasCambios = false;
    // Hallazgos creados en esta pasada: son los únicos que se asignan solos.
    // Los que ya existían conservan su flujo manual para no generar de golpe
    // tareas y notificaciones de actas viejas.
    final nuevos = <InterventoriaHallazgo>[];

    for (final entry in items.entries) {
      final itemKey = entry.key;
      final item = entry.value;
      if (item.noEvaluado) continue;

      final obs = item.observaciones.isNotEmpty
          ? item.observaciones
          : item.observacion.trim().isNotEmpty
          ? [
              InterventoriaNota(
                texto: item.observacion.trim(),
                fuente: item.fuente,
              ),
            ]
          : <InterventoriaNota>[];

      final obsFiltradas = obs.where((n) => n.texto.trim().isNotEmpty).toList();
      if (obsFiltradas.isEmpty) continue;

      final secNum = catIndex[itemKey] ?? 0;

      for (int i = 0; i < obsFiltradas.length; i++) {
        final nota = obsFiltradas[i];
        final grupoId = '${itemKey}_obs$i';
        usedGrupoIds.add(grupoId);

        // aspecto = nombre del ítem del catálogo → columna "Hallazgo"
        // texto   = lo que el revisor escribió   → campo "observaciones"
        final aspecto = nota.aspecto.trim();
        final textoObs = nota.texto.trim();
        final descripcion = aspecto.isNotEmpty
            ? aspecto
            : textoObs; // fallback por compatibilidad

        // Numeral REAL del acta (p. ej. "2.14"). `numeroHallazgo` no sirve
        // para esto: es un ordinal categoría.observación. Vacío = no se pudo
        // determinar → el hallazgo se asigna a mano.
        final numeralActa = numeralActaDesdeAspecto(itemKey, aspecto);

        if (existing.containsKey(grupoId)) {
          final e = existing[grupoId]!;
          if (e.tareaId.isNotEmpty) {
            // Ya asignado → no modificar
            continue;
          }
          // Actualizar hallazgo sin tarea asignada
          batch.update(
            _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(e.docId),
            {
              'descripcion': descripcion,
              'observaciones': textoObs,
              'puntajeSeccion': item.valor,
              'numeroHallazgo': '$secNum.${i + 1}',
              'numeralActa': numeralActa,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        } else {
          // Crear nuevo hallazgo
          final ref = _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc();
          nuevos.add(
            InterventoriaHallazgo(
              id: ref.id,
              empresaId: visita.empresaId,
              visitaId: visita.id,
              centroCostoId: visita.centroCostoId,
              centroCostoNombre: visita.centroCostoNombre,
              grupoId: grupoId,
              tipoActa: visita.tipoActa,
              numeroHallazgo: '$secNum.${i + 1}',
              numeralActa: numeralActa,
              descripcion: descripcion,
              observaciones: textoObs,
              fechaHallazgo: visita.fechaVisita,
              puntajeSeccion: item.valor,
              fuente: 'acta',
              createdAt: Timestamp.now(),
            ),
          );
          batch.set(ref, {
            'empresaId': visita.empresaId,
            'visitaId': visita.id,
            'centroCostoId': visita.centroCostoId,
            'centroCostoNombre': visita.centroCostoNombre,
            'grupoId': grupoId,
            'estado': 'activo',
            'tipoActa': visita.tipoActa,
            'numeroHallazgo': '$secNum.${i + 1}',
            'numeralActa': numeralActa,
            'descripcion': descripcion,
            'observaciones': textoObs,
            'fechaHallazgo': visita.fechaVisita,
            'dptoEncargado': '',
            'areaId': '',
            'puntajeSeccion': item.valor,
            'fuente': 'acta',
            'tareaId': '',
            'notaRegistrador': '',
            'seguimiento': '',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        hasCambios = true;
      }
    }

    // ── 4. Eliminar hallazgos huérfanos sin tarea asignada ───────────────────
    for (final entry in existing.entries) {
      if (!usedGrupoIds.contains(entry.key) && entry.value.tareaId.isEmpty) {
        batch.delete(
          _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(entry.value.docId),
        );
        hasCambios = true;
      }
    }

    if (hasCambios) await batch.commit();

    // ── 5. Asignación automática por numeral ────────────────────────────────
    //      Solo para los hallazgos recién creados cuyo numeral se reconoció.
    //      Un fallo aquí no puede tumbar el guardado del acta: el hallazgo ya
    //      quedó registrado y se puede asignar a mano.
    for (final hallazgo in nuevos) {
      if (hallazgo.numeralParaMatriz.isEmpty) continue;
      try {
        await crearTareaYNotificarHallazgo(
          hallazgo: hallazgo,
          creadorId: registradoPorId,
          creadorNombre: registradoPorNombre,
        );
      } catch (_) {
        // Queda sin tarea; el módulo permite asignarlo manualmente.
      }
    }
  }

  /// Sincroniza el estado del hallazgo cuando la tarea vinculada cambia.
  ///
  /// Lógica:
  ///  • tarea `por_aprobar`               → hallazgo `pendiente_aprobacion`
  ///  • tarea `finalizado` + `aprobado`   → hallazgo `subsanado` directamente
  ///
  /// Solo actúa si el hallazgo está en estado `activo` o `pendiente_aprobacion`;
  /// nunca retrocede un hallazgo ya `subsanado`.
  Future<void> sincronizarEstadoDesdeTask({
    required String hallazgoId,
    required String tareaEstado,
    required String solicitudFinalizacionEstado,
  }) async {
    if (hallazgoId.isEmpty) return;

    final bool tareaFinalAprobada =
        tareaEstado == 'finalizado' &&
        solicitudFinalizacionEstado == 'aprobado';
    final bool tarearPorAprobar = tareaEstado == 'por_aprobar';

    if (!tareaFinalAprobada && !tarearPorAprobar) return;

    try {
      final doc = await _db
          .collection('TBL_INTERVENTORIA_HALLAZGOS')
          .doc(hallazgoId)
          .get();
      if (!doc.exists) return;
      final estadoActual = (doc.data()?['estado'] ?? '').toString();
      if (estadoActual == 'subsanado') return; // no retroceder

      // Determinar nuevo estado
      final nuevoEstado = tareaFinalAprobada
          ? 'subsanado' // tarea aprobada = hallazgo resuelto
          : 'pendiente_aprobacion'; // tarea por aprobar = en revisión

      if (estadoActual == nuevoEstado) return; // ya está en ese estado

      final update = <String, dynamic>{
        'estado': nuevoEstado,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // Si la tarea fue aprobada, registrar la fecha de subsanación
      if (tareaFinalAprobada) {
        update['fechaSubsanacion'] = FieldValue.serverTimestamp();
      }

      await _db
          .collection('TBL_INTERVENTORIA_HALLAZGOS')
          .doc(hallazgoId)
          .update(update);
    } catch (_) {}
  }

  /// Actualiza los campos de seguimiento de un hallazgo (observaciones,
  /// plan de mejora, fecha de subsanación, seguimiento).
  Future<void> actualizarSeguimientoHallazgo({
    required String hallazgoId,
    String? observaciones,
    String? planMejora,
    Timestamp? fechaSubsanacion,
    String? seguimiento,
  }) async {
    if (hallazgoId.isEmpty) return;
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (observaciones != null) data['observaciones'] = observaciones;
    if (planMejora != null) data['planMejora'] = planMejora;
    if (fechaSubsanacion != null) data['fechaSubsanacion'] = fechaSubsanacion;
    if (seguimiento != null) data['seguimiento'] = seguimiento;
    await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .doc(hallazgoId)
        .update(data);
  }

  /// Devuelve el centroId asignado al usuario en esta empresa.
  /// Busca primero en empresasDetalle[empresaId].centroId, luego en raíz.
  Future<String> getCentroCostoId(String empresaId, String userId) async {
    try {
      final doc = await _db.collection('TBL_USUARIOS').doc(userId).get();
      if (!doc.exists) return '';
      final data = doc.data()!;
      final detalle = data['empresasDetalle'];
      if (detalle is Map) {
        final scoped = detalle[empresaId];
        if (scoped is Map) {
          final id = (scoped['centroId'] ?? '').toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
      return (data['centroId'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> guardarVisita(InterventoriaVisita visita) async {
    final ref = visita.id.isEmpty
        ? _db.collection('TBL_INTERVENTORIA_VISITAS').doc()
        : _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visita.id);
    await ref.set(visita.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> eliminarVisita(String visitaId) async {
    // 1. Cargar hallazgos de esta visita
    final hallazgosSnap = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('visitaId', isEqualTo: visitaId)
        .get();

    // 2. Cargar visita para obtener URLs de adjuntos del acta
    final visitaDoc = await _db
        .collection('TBL_INTERVENTORIA_VISITAS')
        .doc(visitaId)
        .get();

    // 3. Borrar archivos en Storage del acta (adjuntos de la visita)
    final visitaData = visitaDoc.data() ?? {};
    final actaAdjuntos = (visitaData['adjuntos'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final adj in actaAdjuntos) {
      final url = adj['url']?.toString() ?? '';
      if (url.isNotEmpty) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    }

    // 4. Por cada hallazgo: borrar tarea asociada + adjuntos de subsanación en Storage
    final tareaIds = <String>{};
    for (final hdoc in hallazgosSnap.docs) {
      final hdata = hdoc.data();
      // Tarea asociada
      final tareaId = (hdata['tareaId'] ?? '').toString();
      if (tareaId.isNotEmpty) tareaIds.add(tareaId);
      // Adjuntos de subsanación en Storage
      final adjSubs = (hdata['adjuntosSubsanacion'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      for (final adj in adjSubs) {
        final url = adj['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {}
        }
      }
    }

    // 5. Borrar tareas asociadas en Firestore
    for (final tareaId in tareaIds) {
      try {
        await _db.collection('TBL_TAREAS').doc(tareaId).delete();
      } catch (_) {}
    }

    // 6. Batch: borrar hallazgos + visita
    final batch = _db.batch();
    for (final doc in hallazgosSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('TBL_INTERVENTORIA_VISITAS').doc(visitaId));
    await batch.commit();
  }

  Future<InterventoriaAdjunto> subirActaBytes({
    required Uint8List bytes,
    required String empresaId,
    required String visitaId,
    required String nombre,
    required String contentType,
    required String origen,
  }) async {
    final path = _actaStoragePath(
      empresaId: empresaId,
      visitaId: visitaId,
      nombre: nombre,
    );
    final ref = _storage.ref(path);
    // Web file pickers can hand us a Uint8List view backed by a JS ArrayBuffer.
    // Firebase Storage may read it after an await, so upload an owned copy.
    final metadata = SettableMetadata(contentType: contentType);
    try {
      final uploadBytes = Uint8List.fromList(bytes);
      await ref.putData(uploadBytes, metadata);
    } catch (e) {
      final msg = e.toString();
      final isTypedArrayIssue =
          msg.contains('TypedArray') ||
          msg.contains('ArrayBuffer') ||
          msg.contains('Construct');
      if (!isTypedArrayIssue) rethrow;
      await ref.putString(
        base64Encode(bytes),
        format: PutStringFormat.base64,
        metadata: metadata,
      );
    }
    final url = await ref.getDownloadURL();
    return InterventoriaAdjunto(
      url: url,
      nombre: nombre,
      path: path,
      contentType: contentType,
      origen: origen,
      fechaSubida: Timestamp.now(),
    );
  }

  Future<InterventoriaAdjunto> subirActaBase64({
    required String base64Data,
    required String empresaId,
    required String visitaId,
    required String nombre,
    required String contentType,
    required String origen,
  }) async {
    final path = _actaStoragePath(
      empresaId: empresaId,
      visitaId: visitaId,
      nombre: nombre,
    );
    final ref = _storage.ref(path);
    await ref.putString(
      base64Data,
      format: PutStringFormat.base64,
      metadata: SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return InterventoriaAdjunto(
      url: url,
      nombre: nombre,
      path: path,
      contentType: contentType,
      origen: origen,
      fechaSubida: Timestamp.now(),
    );
  }

  String _actaStoragePath({
    required String empresaId,
    required String visitaId,
    required String nombre,
  }) {
    final safeName = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'interventoria/$empresaId/visitas/$visitaId/${ts}_$safeName';
  }

  Future<void> agregarAdjuntos({
    required String visitaId,
    required List<InterventoriaAdjunto> adjuntos,
  }) async {
    if (adjuntos.isEmpty) return;
    final firstUrl = adjuntos.first.url;
    await _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visitaId).set({
      'imagenesActa': FieldValue.arrayUnion(
        adjuntos.map((a) => a.toMap()).toList(),
      ),
      if (firstUrl.isNotEmpty) 'actaOriginalUrl': firstUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<InterventoriaRolDoc>> streamRoles(String empresaId) => _db
      .collection('TBL_INTERVENTORIA_ROLES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => InterventoriaRolDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      });

  Future<InterventoriaRolDoc?> getRolUsuario(
    String empresaId,
    String userId,
  ) async {
    final byUserId = await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (byUserId.docs.isNotEmpty) {
      return InterventoriaRolDoc.fromMap(
        byUserId.docs.first.id,
        byUserId.docs.first.data(),
      );
    }
    final byCedula = await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .where('cedula', isEqualTo: userId)
        .limit(1)
        .get();
    if (byCedula.docs.isEmpty) return null;
    return InterventoriaRolDoc.fromMap(
      byCedula.docs.first.id,
      byCedula.docs.first.data(),
    );
  }

  Future<void> guardarRol(
    InterventoriaRolDoc rol, {
    required bool isNew,
  }) async {
    final docId = isNew ? '${rol.empresaId}_${rol.userId}' : rol.id;
    await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .doc(docId)
        .set(rol.toMap(), SetOptions(merge: true));
  }

  Future<void> eliminarRol(String id) =>
      _db.collection('TBL_INTERVENTORIA_ROLES').doc(id).delete();

  // ── Hallazgos ────────────────────────────────────────────────────────────

  Stream<List<InterventoriaHallazgo>> streamHallazgos(
    String empresaId, {
    String? centroId,
    String? estado,
  }) {
    var q = _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('empresaId', isEqualTo: empresaId);
    if (centroId != null && centroId.isNotEmpty) {
      q = q.where('centroCostoId', isEqualTo: centroId);
    }
    if (estado != null && estado.isNotEmpty) {
      q = q.where('estado', isEqualTo: estado);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => InterventoriaHallazgo.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
        return byFecha != 0
            ? byFecha
            : a.numeroHallazgo.compareTo(b.numeroHallazgo);
      });
      return list;
    });
  }

  Future<String> guardarHallazgo(
    InterventoriaHallazgo hallazgo, {
    bool notificarNota =
        false, // true cuando el Registrador guarda notaRegistrador
    String? guardadoPorId,
    String? guardadoPorNombre,
  }) async {
    final ref = hallazgo.id.isEmpty
        ? _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc()
        : _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgo.id);
    await ref.set(hallazgo.toMap(), SetOptions(merge: true));

    // Gap 2: notificar a Revisores/Admins cuando el Registrador agrega nota
    if (notificarNota && hallazgo.notaRegistrador.trim().isNotEmpty) {
      try {
        // Resolver nombre real del autor si llegó vacío o como cédula, para
        // que la notificación nunca muestre la cédula cruda.
        final fromId = (guardadoPorId ?? '').trim();
        String fromName = (guardadoPorNombre ?? '').trim();
        if ((fromName.isEmpty || fromName == fromId) && fromId.isNotEmpty) {
          try {
            final u = await _db.collection('TBL_USUARIOS').doc(fromId).get();
            if (u.exists) fromName = _nombreUsuario(u.data()!);
          } catch (_) {}
        }

        final revisores = await _db
            .collection('TBL_INTERVENTORIA_ROLES')
            .where('empresaId', isEqualTo: hallazgo.empresaId)
            .where(
              'rol',
              whereIn: [kRolInterventoriaRevisor, kRolInterventoriaAdmin],
            )
            .get();
        final msgCorto = hallazgo.descripcion.length > 50
            ? '${hallazgo.descripcion.substring(0, 47)}…'
            : hallazgo.descripcion;
        for (final rdoc in revisores.docs) {
          final rUserId = (rdoc.data()['userId'] ?? '').toString();
          if (rUserId.isEmpty || rUserId == guardadoPorId) continue;
          await _db
              .collection('TBL_NOTIFICACIONES')
              .doc(rUserId)
              .collection('notifications')
              .add({
                'title':
                    '📝 Nota del registrador — ${hallazgo.centroCostoNombre}',
                'description':
                    'Obs.${hallazgo.numeroHallazgo}: $msgCorto\n'
                    '"${hallazgo.notaRegistrador.trim().length > 80 ? '${hallazgo.notaRegistrador.trim().substring(0, 77)}…' : hallazgo.notaRegistrador.trim()}"',
                'type': 'nota_registrador',
                'hallazgoId': ref.id,
                'fromId': fromId,
                'fromName': fromName,
                'empresaId': hallazgo.empresaId,
                'createdAt': Timestamp.now(),
                'read': false,
              });
        }
      } catch (_) {}
    }

    return ref.id;
  }

  /// Deshace la asignación: elimina la tarea y deja el hallazgo libre.
  ///
  /// Es la salida cuando alguien se equivoca de responsable. No borra el
  /// hallazgo ni su seguimiento: solo lo devuelve a "sin asignar".
  Future<void> quitarAsignacionHallazgo({
    required String hallazgoId,
    required String tareaId,
  }) async {
    if (hallazgoId.isEmpty) return;
    if (tareaId.trim().isNotEmpty) {
      try {
        await _db.collection('TBL_TAREAS').doc(tareaId.trim()).delete();
      } catch (_) {
        // La tarea pudo borrarse antes; el hallazgo igual se libera.
      }
    }
    await _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
      'tareaId': '',
      'responsableId': '',
      'responsableNombre': '',
      'cargoResponsable': '',
      'aprobadorId': '',
      'aprobadorNombre': '',
      'cargoAprobador': '',
      'fechaLimite': null,
      'dptoEncargado': '',
      'areaId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> guardarHallazgos(List<InterventoriaHallazgo> hallazgos) async {
    final batch = _db.batch();
    for (final h in hallazgos) {
      final ref = h.id.isEmpty
          ? _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc()
          : _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(h.id);
      batch.set(ref, h.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> eliminarHallazgo(String hallazgoId) async {
    final snap = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .doc(hallazgoId)
        .get();
    if (!snap.exists) return;
    final data = snap.data()!;

    // Borrar tarea asociada en TBL_TAREAS
    final tareaId = (data['tareaId'] ?? '').toString();
    if (tareaId.isNotEmpty) {
      try {
        await _db.collection('TBL_TAREAS').doc(tareaId).delete();
      } catch (_) {}
    }

    // Borrar adjuntos de subsanación en Storage
    final adjSubs = (data['adjuntosSubsanacion'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final adj in adjSubs) {
      final url = adj['url']?.toString() ?? '';
      if (url.isNotEmpty) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    }

    await snap.reference.delete();
  }

  /// El Registrador propone la subsanación → queda en 'pendiente_aprobacion'.
  /// Un cargo superior luego llama a [aprobarSubsanacion] para confirmarla.
  Future<void> marcarSubsanado({
    required String hallazgoId,
    required DateTime fechaSubsanacion,
    String seguimiento = '',
    List<InterventoriaAdjunto> adjuntos = const [],

    /// Si true, aprueba directamente (roles superiores al Registrador).
    bool aprobarDirecto = false,
  }) => _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
    'estado': aprobarDirecto ? 'subsanado' : 'pendiente_aprobacion',
    'fechaSubsanacion': Timestamp.fromDate(fechaSubsanacion),
    if (seguimiento.isNotEmpty) 'seguimiento': seguimiento,
    if (adjuntos.isNotEmpty)
      'adjuntosSubsanacion': adjuntos.map((a) => a.toMap()).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  /// Aprueba una subsanación pendiente (Revisor / Admin / Directivo / Gerente).
  Future<void> aprobarSubsanacion(String hallazgoId) =>
      _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
        'estado': 'subsanado',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Rechaza una subsanación pendiente y la regresa a 'activo'.
  Future<void> rechazarSubsanacion(String hallazgoId) =>
      _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
        'estado': 'activo',
        'fechaSubsanacion': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> reabrirHallazgo(
    String hallazgoId, {
    String reabiertoPorId = '',
    String reabiertoPorNombre = '',
  }) async {
    final snap = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .doc(hallazgoId)
        .get();
    if (!snap.exists) return;

    // Borrar tarea anterior si existe (ya fue subsanada / rechazada)
    final prevTareaId = (snap.data()?['tareaId'] ?? '').toString();
    if (prevTareaId.isNotEmpty) {
      try {
        await _db.collection('TBL_TAREAS').doc(prevTareaId).delete();
      } catch (_) {}
    }

    // Resetear estado y limpiar tareaId
    await snap.reference.set({
      'estado': 'activo',
      'fechaSubsanacion': null,
      'tareaId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Recrear tarea si el hallazgo tiene área asignada
    final data = snap.data()!;
    final hallazgo = InterventoriaHallazgo.fromMap(hallazgoId, {
      ...data,
      'estado': 'activo',
      'fechaSubsanacion': null,
      'tareaId': '',
    });
    if (hallazgo.areaId.isNotEmpty) {
      await crearTareaYNotificarHallazgo(
        hallazgo: hallazgo,
        creadorId: reabiertoPorId,
        creadorNombre: reabiertoPorNombre,
      );
    }
  }

  // ── OCR hallazgos parser ─────────────────────────────────────────────────

  /// Toma el texto pegado/OCR y detecta hallazgos numerados (ej. "1.1 El contratista...")
  List<InterventoriaHallazgo> parseHallazgosOcr({
    required String texto,
    required String empresaId,
    required String centroCostoId,
    required String centroCostoNombre,
    String visitaId = '',
    String grupoId = '',
    String? tipoActa,
  }) {
    final hallazgos = <InterventoriaHallazgo>[];
    // Detecta líneas que empiezan por número tipo 1.1 / 10.20
    final numRx = RegExp(r'^(\d{1,2}\.\d{1,3})\s+(.+)');
    // Detecta fechas para asignar al hallazgo
    DateTime? fechaGlobal = _extractFecha(texto);

    final lines = texto.split('\n');
    String? currentNum;
    final descBuf = StringBuffer();

    void flush() {
      if (currentNum == null) return;
      final desc = descBuf.toString().trim();
      if (desc.isNotEmpty) {
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: empresaId,
            visitaId: visitaId,
            centroCostoId: centroCostoId,
            centroCostoNombre: centroCostoNombre,
            grupoId: grupoId,
            tipoActa: tipoActa,
            numeroHallazgo: currentNum!,
            descripcion: desc,
            fechaHallazgo: Timestamp.fromDate(fechaGlobal ?? DateTime.now()),
            fuente: 'ocr',
            createdAt: Timestamp.now(),
          ),
        );
      }
      currentNum = null;
      descBuf.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final m = numRx.firstMatch(line);
      if (m != null) {
        flush();
        currentNum = m.group(1)!;
        descBuf.write(m.group(2)!);
      } else if (currentNum != null) {
        if (descBuf.isNotEmpty) descBuf.write(' ');
        descBuf.write(line);
      }
    }
    flush();
    return hallazgos;
  }

  // ── Excel export ─────────────────────────────────────────────────────────

  Uint8List exportarHallazgosExcel(List<InterventoriaHallazgo> hallazgos) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Seguimiento');
    final sheet = excel['Seguimiento'];
    final fmt = DateFormat('dd/MM/yyyy');

    final headers = [
      'GRUPO',
      'ESTRUCTURA',
      'ESTADO',
      'TIPO DE ACTA',
      'N° HALLAZGO',
      'HALLAZGOS',
      'FECHA DEL HALLAZGO',
      'PERSISTE',
      'DPTO ENCARGADO',
      'OBSERVACIONES',
      'PLAN DE MEJORA',
      'VALOR DE LA CORRECCIÓN',
      'FECHA DE SUBSANACIÓN',
      'SEGUIMIENTO',
    ];
    sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

    for (final h in hallazgos) {
      sheet.appendRow([
        xl.TextCellValue(h.grupoId),
        xl.TextCellValue(h.centroCostoNombre),
        xl.TextCellValue(h.estado.toUpperCase()),
        xl.TextCellValue(h.tipoActa ?? ''),
        xl.TextCellValue(h.numeroHallazgo),
        xl.TextCellValue(h.descripcion),
        xl.TextCellValue(fmt.format(h.fechaHallazgo.toDate())),
        xl.TextCellValue(h.persiste ? 'SI' : ''),
        xl.TextCellValue(h.dptoEncargado),
        xl.TextCellValue(h.observaciones),
        xl.TextCellValue(h.planMejora),
        h.valorCorreccion != null
            ? xl.DoubleCellValue(h.valorCorreccion!)
            : xl.TextCellValue(''),
        xl.TextCellValue(
          h.fechaSubsanacion != null
              ? fmt.format(h.fechaSubsanacion!.toDate())
              : '',
        ),
        xl.TextCellValue(h.seguimiento),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Exporta la matriz de puntajes por visita/establecimiento al formato Excel.
  Uint8List exportarVisitasExcel(List<InterventoriaVisita> visitas) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Análisis');
    final sheet = excel['Análisis'];
    final fmt = DateFormat('dd/MM/yyyy');

    // Cabecera: SECCIÓN + un centro por columna
    final headers = <xl.CellValue>[
      xl.TextCellValue('SECCIÓN'),
      ...visitas.map(
        (v) => xl.TextCellValue(
          '${v.centroCostoNombre.isNotEmpty ? v.centroCostoNombre : v.centroCostoCodigo}\n${fmt.format(v.fechaVisita.toDate())}',
        ),
      ),
    ];
    sheet.appendRow(headers);

    // Filas de sección
    for (final cat in kInterventoriaCategorias) {
      final row = <xl.CellValue>[xl.TextCellValue(cat.label)];
      for (final v in visitas) {
        final item = v.items[cat.key];
        if (item == null || item.noEvaluado || item.valor == null) {
          row.add(xl.TextCellValue('NE'));
        } else {
          row.add(xl.DoubleCellValue(item.valor!));
        }
      }
      sheet.appendRow(row);
    }

    // Fila de total
    final totalRow = <xl.CellValue>[
      xl.TextCellValue('Total condiciones del servicio'),
    ];
    for (final v in visitas) {
      totalRow.add(xl.DoubleCellValue(v.porcentajeGeneral));
    }
    sheet.appendRow(totalRow);

    return Uint8List.fromList(excel.encode()!);
  }

  Future<void> asegurarConfigBase(String empresaId) async {
    await _db.collection('TBL_INTERVENTORIA_CONFIG').doc(empresaId).set({
      'empresaId': empresaId,
      'categorias': kInterventoriaCategorias
          .map((c) => {'key': c.key, 'label': c.label, 'activo': true})
          .toList(),
      'semaforo': {'verdeDesde': 90, 'amarilloDesde': 70},
      'ocr': {'modo': 'prellenado_editable', 'requiereRevision': true},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  InterventoriaOcrResult analizarTextoOcr(String texto) {
    final items = defaultInterventoriaItems();
    final normalizedText = _normalize(texto);

    for (final categoria in kInterventoriaCategorias) {
      final value = _extractValueForLabel(normalizedText, categoria.label);
      if (value == null) continue;
      items[categoria.key] = items[categoria.key]!.copyWith(
        valor: value,
        noEvaluado: false,
        fuente: 'ocr',
        confianzaOcr: 0.72,
      );
    }

    for (final categoria in kInterventoriaCategorias) {
      if (_extractNeForLabel(normalizedText, categoria.label)) {
        items[categoria.key] = items[categoria.key]!.copyWith(
          noEvaluado: true,
          clearValor: true,
          fuente: 'ocr',
          confianzaOcr: 0.68,
        );
      }
    }

    final fecha = _extractFecha(texto);
    return InterventoriaOcrResult(
      fechaVisita: fecha,
      items: items,
      observaciones: _extractObservaciones(texto),
      raw: {
        'fechaDetectada': fecha?.toIso8601String(),
        'porcentajeGeneral': calcularPorcentajeGeneral(items),
        'categoriasDetectadas': items.values
            .where((i) => i.fuente == 'ocr')
            .length,
      },
    );
  }

  double? _extractValueForLabel(String normalizedText, String label) {
    final labelTokens = _normalize(label)
        .split(' ')
        .where((token) => token.length > 2 && !RegExp(r'^\d+$').hasMatch(token))
        .take(3)
        .toList();
    if (labelTokens.isEmpty) return null;

    final lines = normalizedText.split('\n');
    for (final line in lines) {
      final matches = labelTokens.where(line.contains).length;
      if (matches < (labelTokens.length == 1 ? 1 : 2)) continue;
      final percent = RegExp(r'(\d{1,3})([,.]\d+)?\s*%?').firstMatch(line);
      if (percent == null) continue;
      final raw = percent
          .group(0)!
          .replaceAll('%', '')
          .replaceAll(',', '.')
          .trim();
      final value = double.tryParse(raw);
      if (value == null || value > 100) continue;
      return value;
    }
    return null;
  }

  bool _extractNeForLabel(String normalizedText, String label) {
    final labelTokens = _normalize(label)
        .split(' ')
        .where((token) => token.length > 2 && !RegExp(r'^\d+$').hasMatch(token))
        .take(3)
        .toList();
    for (final line in normalizedText.split('\n')) {
      if (!line.contains(' ne ') && !line.endsWith(' ne')) continue;
      final matches = labelTokens.where(line.contains).length;
      if (matches >= (labelTokens.length == 1 ? 1 : 2)) return true;
    }
    return false;
  }

  DateTime? _extractFecha(String texto) {
    final match = RegExp(
      r'(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})',
    ).firstMatch(texto);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    return DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
  }

  String _extractObservaciones(String texto) {
    final lower = texto.toLowerCase();
    final idx = lower.indexOf('observ');
    if (idx < 0) return '';
    final tail = texto.substring(idx).trim();
    return tail.length > 600 ? tail.substring(0, 600) : tail;
  }

  String _normalize(String text) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ñ': 'n',
      'Á': 'a',
      'É': 'e',
      'Í': 'i',
      'Ó': 'o',
      'Ú': 'u',
      'Ñ': 'n',
    };
    var out = text;
    accents.forEach((a, b) => out = out.replaceAll(a, b));
    return out.toLowerCase().replaceAll(RegExp(r'[^\w%,.\n ]+'), ' ');
  }

  // ── Áreas de la empresa ──────────────────────────────────────────────────

  Future<List<Area>> getAreas(String empresaId) =>
      OrgService(db: _db).listAreas(empresaId: empresaId);

  /// nombre de cargo normalizado → areaId, leído de `TBL_CARGOS`.
  ///
  /// La mayoría de usuarios NO tiene `areaId` propio en TBL_USUARIOS: el área
  /// vive en el cargo. Sin este puente, agrupar personal por área da vacío.
  /// Lo que el maestro de cargos aporta al listado de personal: el área (para
  /// el desplegable) y si ese cargo recibe trabajo operativo (para no ofrecer
  /// a Talento Humano ni a quien no usa computador).
  ///
  /// Se lee de una sola pasada porque son el mismo documento: separar los dos
  /// datos costaba dos lecturas completas de `TBL_CARGOS` por cada apertura
  /// del tablero.
  Future<Map<String, ({String areaId, bool recibeAsignaciones})>> _perfilPorCargo(
    String empresaId,
  ) async {
    final snap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <String, ({String areaId, bool recibeAsignaciones})>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final nombre = (data['nombre'] ?? data['cargoId'] ?? doc.id).toString();
      final clave = _claveCargo(nombre);
      if (clave.isEmpty) continue;
      out[clave] = (
        areaId: (data['areaId'] ?? '').toString().trim(),
        recibeAsignaciones: cargoRecibeAsignaciones(data),
      );
    }
    return out;
  }

  /// Normaliza un nombre de cargo para emparejarlo entre colecciones: los
  /// mismos cargos vienen escritos con tildes, mayúsculas y espacios
  /// distintos en TBL_USUARIOS y en TBL_CARGOS.
  static String _claveCargo(String cargo) {
    var s = cargo.toLowerCase().trim();
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  // ── Asignación automática por numeral del acta ───────────────────────────

  /// Días hábiles por defecto para subsanar un hallazgo cuando la empresa no
  /// ha configurado nada.
  ///
  /// Un día hábil por decisión operativa: el hallazgo debe atenderse de
  /// inmediato, y cuando algo no alcance se reasigna la fecha a mano en vez de
  /// nacer con semanas de holgura. Una empresa puede ampliarlo en
  /// `TBL_INTERVENTORIA_CONFIG/{empresaId}.plazoSubsanacion`.
  static const int kPlazoSubsanacionPorDefecto = 1;

  /// Usuarios de la empresa con los datos necesarios para resolver un cargo.
  ///
  /// El cargo y el centro de costo se leen primero de `empresasDetalle[empresaId]`
  /// (valor específico de esa empresa) y como respaldo del nivel raíz, igual
  /// que hace [getCentroCostoId].
  Future<List<InterventoriaUsuario>> listarUsuariosAsignables(
    String empresaId,
  ) => _usuariosDeEmpresa(empresaId);

  Future<List<InterventoriaUsuario>> _usuariosDeEmpresa(
    String empresaId,
  ) async {
    final snap = await _db.collection('TBL_USUARIOS').get();
    // El área del cargo es un respaldo, no la fuente: si el usuario ya trae
    // areaId propio ese manda. Si TBL_CARGOS falla, se sigue sin áreas en
    // vez de quedarse sin lista de personal.
    var perfilPorCargo = <String, ({String areaId, bool recibeAsignaciones})>{};
    try {
      perfilPorCargo = await _perfilPorCargo(empresaId);
    } catch (_) {}
    final rows = <InterventoriaUsuario>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      // El retiro de Talento Humano se guarda por empresa
      // (`empresasDetalle.{empresaId}.estadoLaboral`); el `estado` global solo
      // bloquea el login, así que por sí solo dejaba pasar a los retirados.
      if (!isPersonaActivaEnEmpresa(data, empresaId)) continue;
      Map<String, dynamic>? scoped;
      final detalle = data['empresasDetalle'];
      if (detalle is Map && detalle[empresaId] is Map) {
        scoped = Map<String, dynamic>.from(detalle[empresaId] as Map);
      }
      final empresas = data['empresas'];
      final pertenece =
          scoped != null ||
          (empresas is Iterable &&
              empresas.map((e) => e.toString()).contains(empresaId)) ||
          (data['empresaId'] ?? '').toString() == empresaId ||
          data['desarrollador'] == true;
      if (!pertenece) continue;

      final cargo =
          (scoped?['cargo'] ??
                  scoped?['cargoNombre'] ??
                  data['cargo'] ??
                  data['cargoNombre'] ??
                  '')
              .toString()
              .trim();
      if (cargo.isEmpty) continue;

      // Fuera de los desplegables de asignación quien esté marcado como no
      // operativo (Talento Humano, administrativos sin computador). Sigue
      // vinculado y con acceso: solo deja de ser candidato a recibir tareas.
      final perfilCargo = perfilPorCargo[_claveCargo(cargo)];
      if (!recibeAsignacionesEnEmpresa(
        data,
        empresaId,
        marcaDelCargo: perfilCargo?.recibeAsignaciones,
      )) {
        continue;
      }

      final centroId = (scoped?['centroId'] ?? data['centroId'] ?? '')
          .toString()
          .trim();
      var areaId = (scoped?['areaId'] ?? data['areaId'] ?? '')
          .toString()
          .trim();
      if (areaId.isEmpty) {
        areaId = perfilCargo?.areaId ?? '';
      }
      rows.add(
        InterventoriaUsuario(
          id: doc.id,
          nombre: _nombreUsuario(data, fallbackId: doc.id),
          cargo: cargo,
          centroId: centroId,
          areaId: areaId,
        ),
      );
    }
    rows.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return rows;
  }

  /// Elige a la persona que encarna [cargoMatriz] para el centro de costo dado.
  ///
  /// Prioridad: (1) mejor afinidad de cargo, (2) del mismo centro de costo.
  /// Así "Administrador" cae en el administrador de ESE establecimiento, y los
  /// cargos corporativos (Gerencia, Director de operaciones) se resuelven a
  /// nivel empresa porque su titular no tiene centro asignado.
  InterventoriaPersona? resolverCargo(
    String cargoMatriz,
    String centroCostoId,
    List<InterventoriaUsuario> usuarios,
  ) {
    ({InterventoriaUsuario user, int afinidad})? mejor;
    for (final user in usuarios) {
      final afinidad = afinidadCargo(cargoMatriz, user.cargo);
      if (afinidad == null) continue;
      final delCentro =
          centroCostoId.isNotEmpty && user.centroId == centroCostoId;
      final mejorDelCentro =
          mejor != null &&
          centroCostoId.isNotEmpty &&
          mejor.user.centroId == centroCostoId;
      if (mejor == null ||
          afinidad < mejor.afinidad ||
          (afinidad == mejor.afinidad && delCentro && !mejorDelCentro)) {
        mejor = (user: user, afinidad: afinidad);
      }
    }
    if (mejor == null) return null;
    return InterventoriaPersona(
      id: mejor.user.id,
      nombre: mejor.user.nombre,
      cargo: mejor.user.cargo,
      cargoMatriz: cargoMatriz,
      delCentro:
          centroCostoId.isNotEmpty && mejor.user.centroId == centroCostoId,
    );
  }

  /// Responsable que el acta asigna a este hallazgo, resuelto contra una lista
  /// de usuarios ya cargada. Sincrónico a propósito: el tablero lo llama una
  /// vez por tarjeta y no puede permitirse una consulta cada vez.
  ///
  /// Devuelve null si el numeral no se pudo identificar o si nadie en la
  /// empresa tiene el cargo que responde por él.
  InterventoriaPersona? sugerirResponsable(
    InterventoriaHallazgo hallazgo,
    List<InterventoriaUsuario> usuarios,
  ) {
    final matriz = responsabilidadDeNumeral(hallazgo.numeralParaMatriz);
    if (matriz == null) return null;
    return resolverCargo(matriz.responsable, hallazgo.centroCostoId, usuarios);
  }

  /// Días hábiles para subsanar, configurables por sección del acta en
  /// `TBL_INTERVENTORIA_CONFIG/{empresaId}.plazoSubsanacion`.
  Future<int> plazoSubsanacionDias(String empresaId, int seccion) async {
    try {
      final doc = await _db
          .collection('TBL_INTERVENTORIA_CONFIG')
          .doc(empresaId)
          .get();
      final plazo = doc.data()?['plazoSubsanacion'];
      if (plazo is Map) {
        final porSeccion = plazo['porSeccion'];
        if (porSeccion is Map) {
          final value = porSeccion['$seccion'];
          if (value is num && value > 0) return value.toInt();
        }
        final base = plazo['diasHabilesPorDefecto'];
        if (base is num && base > 0) return base.toInt();
      }
    } catch (_) {
      // Sin configuración legible se usa el plazo por defecto.
    }
    return kPlazoSubsanacionPorDefecto;
  }

  /// Suma [dias] días hábiles a [desde], saltando fines de semana y festivos
  /// colombianos. Vence al cierre del día hábil.
  static DateTime sumarDiasHabiles(DateTime desde, int dias) =>
      sumarDiasHabilesColombia(desde, dias);

  /// Aplica la matriz del acta a un numeral y devuelve a quién corresponde
  /// subsanarlo, quién lo aprueba y para cuándo.
  ///
  /// Devuelve null cuando el numeral no existe en la matriz (numeral vacío,
  /// mal leído por OCR o de un acta que no es la REGULAR): en ese caso la
  /// asignación queda manual, como hasta ahora.
  Future<InterventoriaAsignacionSugerida?> resolverAsignacionPorNumeral({
    required String empresaId,
    required String numeral,
    String centroCostoId = '',
    DateTime? desde,
  }) async {
    final clave = normalizarNumeralActa(numeral);
    final matriz = responsabilidadDeNumeral(clave);
    if (matriz == null) return null;

    final usuarios = await _usuariosDeEmpresa(empresaId);
    final seccion = int.tryParse(clave.split('.').first) ?? 0;
    final dias = await plazoSubsanacionDias(empresaId, seccion);

    return InterventoriaAsignacionSugerida(
      numeral: clave,
      cargoResponsable: matriz.responsable,
      cargoAprobador: matriz.aprobador,
      responsable: resolverCargo(matriz.responsable, centroCostoId, usuarios),
      aprobador: resolverCargo(matriz.aprobador, centroCostoId, usuarios),
      fechaLimite: sumarDiasHabiles(desde ?? DateTime.now(), dias),
    );
  }

  // ── Director de un área ──────────────────────────────────────────────────

  /// Busca en TBL_USUARIOS el usuario del área cuyo cargo contenga 'director'.
  /// Devuelve un map con los campos: id (cédula/docId), nombre, cargo, areaId.
  /// Jerarquía de cargos para seleccionar el responsable del área.
  /// El índice más bajo = mayor rango. Si el cargo contiene cualquiera de
  /// estas palabras se asigna ese nivel; de lo contrario nivel máximo (99).
  static int _nivelCargo(String cargo) {
    final c = cargo.toLowerCase();
    const niveles = [
      'director',
      'gerente',
      'subdirector',
      'coordinador',
      'jefe',
      'supervisor',
      'encargado',
      'responsable',
      'lider',
      'líder',
    ];
    for (int i = 0; i < niveles.length; i++) {
      if (c.contains(niveles[i])) return i;
    }
    return 99;
  }

  /// Retorna el responsable del área [areaId] dentro de [empresaId]:
  /// 1. Si hay una sola persona en el área → esa persona.
  /// 2. Si hay varias → la de mayor jerarquía según [_nivelCargo].
  /// 3. Usa el detalle de la empresa activa; nunca mezcla personal de otra
  ///    empresa aunque comparta el mismo identificador de área.
  Future<Map<String, dynamic>?> getDirectorDeArea(
    String empresaId,
    String areaId,
  ) async {
    if (areaId.trim().isEmpty) return null;
    final candidatos = (await _usuariosDeEmpresa(empresaId))
        .where((user) => user.areaId == areaId)
        .map(
          (user) => <String, dynamic>{
            'id': user.id,
            'nombre': user.nombre,
            'cargo': user.cargo,
            'areaId': user.areaId,
            '_nivel': _nivelCargo(user.cargo),
          },
        )
        .toList();

    if (candidatos.isEmpty) return null;

    // ── 3. Área con una sola persona → esa persona ───────────────────────────
    if (candidatos.length == 1) return candidatos.first;

    // ── 4. Varias personas → la de mayor jerarquía ───────────────────────────
    candidatos.sort(
      (a, b) => (a['_nivel'] as int).compareTo(b['_nivel'] as int),
    );
    return candidatos.first;
  }

  String _nombreUsuario(Map<String, dynamic> data, {String fallbackId = ''}) {
    final nombres = (data['nombres'] ?? data['nombre'] ?? '').toString().trim();
    final apellidos = (data['apellidos'] ?? data['apellido'] ?? '')
        .toString()
        .trim();
    if (nombres.isNotEmpty && apellidos.isNotEmpty) {
      return '$nombres $apellidos';
    }
    if (nombres.isNotEmpty) return nombres;
    return (data['displayName'] ?? data['email'] ?? data['id'] ?? fallbackId)
        .toString()
        .trim();
  }

  // ── Crear tarea + notificar al director del departamento ────────────────

  /// Crea una tarea en TBL_TAREAS asignada al director del área seleccionada,
  /// en estado PENDIENTE para que pueda revisarla y reasignarla a su equipo.
  /// Retorna el ID de la tarea creada o null si falla.
  /// [preferirAreaManual] = alguien eligió el departamento a mano y esa
  /// decisión gana sobre la matriz del acta. La matriz sigue aportando el
  /// aprobador y la fecha límite.
  ///
  /// [responsableForzado] = se eligió a una persona concreta desde el tablero.
  /// Es la de mayor prioridad: manda sobre la matriz y sobre el área. Sirve
  /// para los hallazgos cuyo numeral no se puede identificar.
  Future<String?> crearTareaYNotificarHallazgo({
    required InterventoriaHallazgo hallazgo,
    required String creadorId,
    String creadorNombre = '',
    bool preferirAreaManual = false,
    InterventoriaPersona? responsableForzado,
  }) async {
    // ── 1. Resolver nombre real del creador ──────────────────────────────────
    String creadorNombreReal = creadorNombre;
    if (creadorId.isNotEmpty) {
      try {
        final userDoc = await _db
            .collection('TBL_USUARIOS')
            .doc(creadorId)
            .get();
        if (userDoc.exists) creadorNombreReal = _nombreUsuario(userDoc.data()!);
      } catch (_) {}
    }
    if (creadorNombreReal.isEmpty) creadorNombreReal = creadorId;

    // ── 2. Asignación por numeral (matriz del acta) ──────────────────────────
    //      Si el numeral está en la matriz, manda ella: el hallazgo va al
    //      cargo que responde por ese numeral en ESE centro de costo, y el
    //      aprobador queda como jefe de la tarea.
    //      Si el numeral no se reconoce, se conserva el comportamiento
    //      anterior: la tarea va al director del área elegida a mano.
    final asignacion = await resolverAsignacionPorNumeral(
      empresaId: hallazgo.empresaId,
      numeral: hallazgo.numeralParaMatriz,
      centroCostoId: hallazgo.centroCostoId,
      desde: hallazgo.fechaHallazgo.toDate(),
    );

    String destinatarioId = responsableForzado?.id ?? '';
    String destinatarioNombre = responsableForzado?.nombre ?? '';
    if (destinatarioId.isEmpty && !preferirAreaManual) {
      destinatarioId = asignacion?.responsable?.id ?? '';
      destinatarioNombre = asignacion?.responsable?.nombre ?? '';
    }
    if (destinatarioId.isEmpty) {
      final director = await getDirectorDeArea(
        hallazgo.empresaId,
        hallazgo.areaId,
      );
      destinatarioId = director?['id']?.toString() ?? '';
      destinatarioNombre = director != null ? _nombreUsuario(director) : '';
    }
    // Elección manual sin director en esa área: antes de dejarla sin dueño,
    // vale más el responsable que indica el acta.
    if (destinatarioId.isEmpty) {
      destinatarioId = asignacion?.responsable?.id ?? '';
      destinatarioNombre = asignacion?.responsable?.nombre ?? '';
    }

    // El aprobador de la matriz es el jefe de la tarea: recibe notificación
    // cuando el responsable termina y es quien aprueba la subsanación.
    final aprobador = asignacion?.aprobador;
    final jefeId = aprobador?.id.isNotEmpty == true ? aprobador!.id : creadorId;
    final jefeNombre = aprobador?.id.isNotEmpty == true
        ? aprobador!.nombre
        : creadorNombreReal;

    final fechaLimite =
        asignacion?.fechaLimite ??
        sumarDiasHabiles(
          hallazgo.fechaHallazgo.toDate(),
          await plazoSubsanacionDias(hallazgo.empresaId, hallazgo.seccion),
        );

    // ── 3. Título: "CentroCosto · Obs.N: descripción corta" ─────────────────
    final numPart = hallazgo.numeroHallazgo.isNotEmpty
        ? ' Obs.${hallazgo.numeroHallazgo}:'
        : '';
    final descCorta = hallazgo.descripcion.length > 80
        ? '${hallazgo.descripcion.substring(0, 77)}…'
        : hallazgo.descripcion;
    final titulo = '${hallazgo.centroCostoNombre}$numPart $descCorta';

    // ── 4. Descripción completa ──────────────────────────────────────────────
    final sb = StringBuffer();
    sb.writeln('📌 OBSERVACIÓN DE INTERVENTORÍA');
    sb.writeln('Hallazgo N°: ${hallazgo.numeroHallazgo}');
    sb.writeln('Centro de costo: ${hallazgo.centroCostoNombre}');
    if (hallazgo.dptoEncargado.isNotEmpty) {
      sb.writeln('Departamento: ${hallazgo.dptoEncargado}');
    }
    if (asignacion != null) {
      sb.writeln('Responsable según acta: ${asignacion.cargoResponsable}');
      sb.writeln('Aprueba la subsanación: ${asignacion.cargoAprobador}');
    }
    sb.writeln(
      'Fecha: ${DateFormat('dd/MM/yyyy').format(hallazgo.fechaHallazgo.toDate())}',
    );
    sb.writeln(
      'Fecha límite para subsanar: ${DateFormat('dd/MM/yyyy').format(fechaLimite)}',
    );
    sb.writeln();
    sb.writeln('── Descripción ──');
    sb.writeln(hallazgo.descripcion);
    if (hallazgo.observaciones.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('── Observaciones del acta ──');
      sb.writeln(hallazgo.observaciones.trim());
    }
    if (hallazgo.notaRegistrador.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('── Contexto del registrador ──');
      sb.writeln(hallazgo.notaRegistrador.trim());
    }
    if (hallazgo.planMejora.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('── Plan de mejora ──');
      sb.writeln(hallazgo.planMejora.trim());
    }
    if (hallazgo.seguimiento.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('── Seguimiento ──');
      sb.writeln(hallazgo.seguimiento.trim());
    }
    sb.writeln();
    sb.writeln('──────────────────────────────');
    sb.writeln('ℹ️  Esta tarea fue generada automáticamente por el módulo de');
    sb.writeln(
      '   Interventoría a partir del numeral del acta. Quien la recibe puede',
    );
    sb.writeln('   reasignarla a cualquier miembro de su equipo.');
    sb.writeln('Origen: Interventoría');
    final descripcion = sb.toString().trimRight();

    // ── 5. Crear tarea vía TaskService en estado PENDIENTE ───────────────────
    //      Estado "pendiente" = tarea creada, esperando acción del responsable.
    //      El responsable la ve en su lista y puede: iniciarla, reasignarla o
    //      asignarla directamente a un miembro del equipo.
    final taskSvc = TaskService();
    final taskId = await taskSvc.createTaskEs(
      titulo: titulo,
      descripcion: descripcion,
      estado: 'pendiente', // ← estado inicial, NO en_progreso
      prioridad: 'alta',
      asignadoUid: destinatarioId.isNotEmpty ? destinatarioId : creadorId,
      asignadoNombre: destinatarioId.isNotEmpty
          ? destinatarioNombre
          : creadorNombreReal,
      creadorUid: creadorId,
      creadorNombre: creadorNombreReal,
      // El aprobador de la matriz queda como "jefe" → recibe notificación
      // cuando el responsable reasigne o finalice la tarea. Sin aprobador
      // resuelto, ese rol lo conserva quien registró el hallazgo.
      jefeUid: jefeId,
      jefeNombre: jefeNombre,
      centroId: hallazgo.centroCostoId.isNotEmpty
          ? hallazgo.centroCostoId
          : 'global',
      areaId: hallazgo.areaId,
      empresaId: hallazgo.empresaId,
      fechaLimite: fechaLimite,
      extra: {
        'hallazgoId': hallazgo.id,
        'visitaId': hallazgo.visitaId,
        'centroCostoId': hallazgo.centroCostoId,
        'origen': 'interventoria',
        'sourceModule': 'interventoria',
        'sourceType': 'hallazgo',
        'sourceEntityId': hallazgo.id,
        'sourceEntityCollection': 'TBL_INTERVENTORIA_HALLAZGOS',
        'notify': true,
        'empresas': [hallazgo.empresaId],
        'areaNombre': hallazgo.dptoEncargado,
        'numeralActa': hallazgo.numeroHallazgo,
        'cargoResponsable': asignacion?.cargoResponsable ?? '',
        'cargoAprobador': asignacion?.cargoAprobador ?? '',
        'asignacionAutomatica': asignacion?.responsable != null,
        // Marca que permite reasignación directa sin aprobación extra
        'permite_reasignacion_director': true,
      },
    );

    // Reasignación: la tarea anterior se elimina DESPUÉS de crear la nueva,
    // para no dejar el hallazgo sin tarea si la creación falla. Sin esto, cada
    // reasignación dejaba una tarea huérfana viva en la bandeja del anterior.
    final tareaAnterior = hallazgo.tareaId.trim();
    if (tareaAnterior.isNotEmpty && tareaAnterior != taskId) {
      try {
        await _db.collection('TBL_TAREAS').doc(tareaAnterior).delete();
      } catch (_) {
        // Si no se puede borrar, la nueva tarea ya quedó creada y vinculada.
      }
    }

    // ── 6. Guardar en el hallazgo el enlace a la tarea y a quién quedó ──────
    if (hallazgo.id.isNotEmpty) {
      await _db
          .collection('TBL_INTERVENTORIA_HALLAZGOS')
          .doc(hallazgo.id)
          .update({
            'tareaId': taskId,
            'responsableId': destinatarioId,
            'responsableNombre': destinatarioNombre,
            // Con responsable forzado se guarda su cargo real, no el que dictaba
            // la matriz: en la tabla debe leerse a quién quedó de verdad.
            'cargoResponsable':
                responsableForzado?.cargo ?? asignacion?.cargoResponsable ?? '',
            'aprobadorId': aprobador?.id ?? '',
            'aprobadorNombre': aprobador?.nombre ?? '',
            'cargoAprobador': asignacion?.cargoAprobador ?? '',
            'fechaLimite': Timestamp.fromDate(fechaLimite),
          });
    }

    // onTaskCreated es la única fuente de notificaciones para evitar duplicados
    // entre el cliente y Cloud Functions.
    return taskId;
  }
}
