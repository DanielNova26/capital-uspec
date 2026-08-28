// lib/compras/compras_service.dart
// ignore_for_file: unused_import
// NOTA: Todas las queries usan solo .where('empresaId') sin orderBy para evitar
// la necesidad de índices compuestos en Firestore. El ordenamiento se hace cliente.

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'compras_catalog_logic.dart';
import 'compras_models.dart';
import 'compras_recepcion_logic.dart';
import 'compras_req_engine.dart';
import 'compras_validation.dart';
import '../services/task_service.dart';

class ComprasCatalogItem {
  final String code;
  final String name;

  const ComprasCatalogItem({required this.code, required this.name});
}

class ComprasService {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final TaskService _tasks;

  /// Plazo predeterminado para corregir documentos rechazados. La empresa puede
  /// modificarlo desde Administración > Compras.
  static const int kDiasCorreccionPredeterminado = 30;

  ComprasService({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _db = db ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _tasks = TaskService(db: db, storage: storage);

  Future<int> obtenerDiasPlazoRechazados(String empresaId) async {
    try {
      final snap = await _db
          .collection('TBL_COMPRAS_CONFIG')
          .doc(empresaId.trim())
          .get();
      final value = snap.data()?['diasPlazoRechazados'];
      if (value is num && value >= 1 && value <= 365) return value.toInt();
    } catch (_) {
      // Conserva el flujo operativo aun si la configuración no está disponible.
    }
    return kDiasCorreccionPredeterminado;
  }

  /// Carga exclusivamente las bodegas de la empresa activa.
  ///
  /// Fuente preferida: TBL_COMPRAS_BODEGAS con campo empresaId. Como
  /// compatibilidad, también admite un array `bodegas` dentro de TBL_EMPRESAS
  /// y, finalmente, el catálogo legado de las dos empresas iniciales.
  Future<List<String>> getBodegasEmpresa(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return const [];

    final bodegas = <String>[];
    try {
      final snap = await _db
          .collection('TBL_COMPRAS_BODEGAS')
          .where('empresaId', isEqualTo: id)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['activo'] == false) continue;
        final nombre = (data['nombre'] ?? data['bodega'] ?? data['label'] ?? '')
            .toString()
            .trim();
        if (nombre.isNotEmpty) bodegas.add(nombre);
      }
    } catch (_) {
      // Se continúa con las fuentes de compatibilidad.
    }

    String empresaNombre = '';
    if (bodegas.isEmpty) {
      try {
        final empresa = await _db.collection('TBL_EMPRESAS').doc(id).get();
        final data = empresa.data() ?? const <String, dynamic>{};
        empresaNombre = (data['nombre'] ?? data['razonSocial'] ?? '')
            .toString()
            .trim();
        final raw = data['bodegas'];
        if (raw is List) {
          for (final item in raw) {
            final nombre = item is Map
                ? (item['nombre'] ?? item['bodega'] ?? item['label'] ?? '')
                      .toString()
                      .trim()
                : item.toString().trim();
            if (nombre.isNotEmpty) bodegas.add(nombre);
          }
        }
      } catch (_) {
        // Se continúa con el catálogo legado, siempre limitado a la empresa.
      }
    }

    if (bodegas.isEmpty) {
      bodegas.addAll(
        bodegasLegacyParaEmpresa(empresaId: id, empresaNombre: empresaNombre),
      );
    }

    final unique = <String, String>{};
    for (final bodega in bodegas) {
      unique.putIfAbsent(bodega.toLowerCase(), () => bodega);
    }
    final result = unique.values.toList()..sort((a, b) => a.compareTo(b));
    return result;
  }

  Future<List<ComprasCatalogItem>> getDepartamentos() async {
    final snap = await _db.collection('TBL_DEPARTAMENTOS').get();
    final items = snap.docs
        .map((doc) {
          final data = doc.data();
          return ComprasCatalogItem(
            code: (data['cod_dane'] ?? doc.id).toString().trim(),
            name: (data['nombre'] ?? doc.id).toString().trim(),
          );
        })
        .where((item) => item.code.isNotEmpty && item.name.isNotEmpty)
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  Future<List<ComprasCatalogItem>> getCiudades(String departamentoCode) async {
    final dep = departamentoCode.trim();
    if (dep.isEmpty) return [];
    final snap = await _db
        .collection('TBL_CIUDADES')
        .where('cod_departamento', isEqualTo: dep)
        .get();
    final items = snap.docs
        .map((doc) {
          final data = doc.data();
          return ComprasCatalogItem(
            code: (data['cod_dane'] ?? doc.id).toString().trim(),
            name: (data['nombre'] ?? doc.id).toString().trim(),
          );
        })
        .where((item) => item.code.isNotEmpty && item.name.isNotEmpty)
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  // ─── PRODUCTOS ──────────────────────────────────────────────────────────────

  Stream<List<ProductoDoc>> streamProductos(String empresaId) => _db
      .collection('TBL_COMPRAS_PRODUCTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => ProductoDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      });

  Future<String> guardarProducto(ProductoDoc p, {required bool isNew}) async {
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_PRODUCTOS').doc()
        : _db.collection('TBL_COMPRAS_PRODUCTOS').doc(p.id);
    await ref.set(p.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> actualizarDocumentosAsociadosProducto({
    required String productoId,
    required Map<String, DocAdjunto> documentos,
  }) => _db.collection('TBL_COMPRAS_PRODUCTOS').doc(productoId).update({
    'documentosAsociados': documentos.map(
      (key, value) => MapEntry(key, value.toMap()),
    ),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> eliminarProducto(String id) =>
      _db.collection('TBL_COMPRAS_PRODUCTOS').doc(id).delete();

  // ─── PROVEEDORES ────────────────────────────────────────────────────────────

  Stream<List<ProveedorDoc>> streamProveedores(String empresaId) => _db
      .collection('TBL_COMPRAS_PROVEEDORES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
        return list;
      });

  Future<String> guardarProveedor(
    ProveedorDoc p, {
    required bool isNew,
    String creadoPor = '',
  }) async {
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_PROVEEDORES').doc()
        : _db.collection('TBL_COMPRAS_PROVEEDORES').doc(p.id);
    await ref.set({
      ...p.toMap(),
      // El trigger de WhatsApp escucha únicamente altas manuales. Las
      // actualizaciones y las importaciones masivas no generan mensajes.
      if (isNew) 'notificarWhatsAppNuevoProveedor': true,
      if (isNew && creadoPor.trim().isNotEmpty) 'creadoPor': creadoPor.trim(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> eliminarProveedor(String id) =>
      _db.collection('TBL_COMPRAS_PROVEEDORES').doc(id).delete();

  Future<void> cambiarEstadoProveedor({
    required String proveedorId,
    required bool activo,
    required String userId,
    String motivo = '',
  }) => _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId).update({
    'activo': activo,
    'estado': activo ? 'activo' : 'inactivo',
    'inactivadoAt': activo ? FieldValue.delete() : FieldValue.serverTimestamp(),
    'inactivadoPor': activo ? FieldValue.delete() : userId,
    'motivoInactivacion': activo ? FieldValue.delete() : motivo.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Stream<List<ComprasGrupoDoc>> streamGruposCompras(String empresaId) => _db
      .collection('TBL_COMPRAS_GRUPOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => ComprasGrupoDoc.fromMap(doc.id, doc.data()))
            .where((grupo) => grupo.activo)
            .toList();
        rows.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
        return rows;
      });

  Future<List<ComprasGrupoDoc>> getGruposCompras(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_COMPRAS_GRUPOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final rows = snapshot.docs
        .map((doc) => ComprasGrupoDoc.fromMap(doc.id, doc.data()))
        .where((grupo) => grupo.activo)
        .toList();
    rows.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return rows;
  }

  /// Importa una lista de proveedores desde Excel.
  /// Omite los que ya existen (mismo NIT para la empresa).
  /// Retorna {'importados': n, 'omitidos': n}.
  Future<Map<String, int>> importarProveedores(
    String empresaId,
    List<ProveedorDoc> proveedores,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final nitsExistentes = {
      for (final d in snap.docs) (d.data()['nit'] as String? ?? ''): d.id,
    };

    var imported = 0;
    var omitidos = 0;
    const batchSize = 400;
    var batch = _db.batch();
    var count = 0;

    for (final p in proveedores) {
      if (nitsExistentes.containsKey(p.nit)) {
        omitidos++;
        continue;
      }
      final ref = _db.collection('TBL_COMPRAS_PROVEEDORES').doc();
      batch.set(ref, p.toMap());
      imported++;
      count++;
      if (count >= batchSize) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    return {'importados': imported, 'omitidos': omitidos};
  }

  /// Importa una lista de productos desde Excel.
  /// Omite los que ya existen (mismo código para la empresa).
  /// Si el código está vacío se usa el nombre como clave de deduplicación.
  /// Retorna {'importados': n, 'omitidos': n}.
  Future<Map<String, int>> importarProductos(
    String empresaId,
    List<ProductoDoc> productos,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_PRODUCTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    // Clave de dedup: código (si existe) o nombre lowercase
    final existentes = <String>{};
    for (final d in snap.docs) {
      final data = d.data();
      final cod = (data['codigo'] as String? ?? '').trim();
      final nom = (data['nombre'] as String? ?? '').trim().toLowerCase();
      if (cod.isNotEmpty) existentes.add(cod.toLowerCase());
      if (nom.isNotEmpty) existentes.add(nom);
    }

    var imported = 0;
    var omitidos = 0;
    const batchSize = 400;
    var batch = _db.batch();
    var count = 0;

    for (final p in productos) {
      final clave = p.codigo.isNotEmpty
          ? p.codigo.toLowerCase()
          : p.nombre.toLowerCase();
      if (existentes.contains(clave)) {
        omitidos++;
        continue;
      }
      existentes.add(clave); // evita duplicados dentro del mismo archivo
      final ref = _db.collection('TBL_COMPRAS_PRODUCTOS').doc();
      batch.set(ref, p.toMap());
      imported++;
      count++;
      if (count >= batchSize) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    return {'importados': imported, 'omitidos': omitidos};
  }

  // ─── RECEPCIONES ────────────────────────────────────────────────────────────

  Stream<List<RecepcionDoc>> streamRecepciones(String empresaId) => _db
      .collection('TBL_COMPRAS_RECEPCIONES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      });

  /// Recepciones dentro de un rango de fechas, acotado en el servidor.
  ///
  /// Histórico y Rechazadas crecen sin límite; traer la colección completa y
  /// filtrar en el cliente sobrecarga la app. Requiere el índice compuesto
  /// (empresaId ASC, fecha DESC) declarado en firestore.indexes.json.
  Stream<List<RecepcionDoc>> streamRecepcionesPorRango(
    String empresaId, {
    required DateTime desde,
    required DateTime hasta,
  }) {
    // Rango inclusivo por día completo.
    final inicio = DateTime(desde.year, desde.month, desde.day);
    final fin = DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59, 999);
    return _db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .where('empresaId', isEqualTo: empresaId)
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(fin))
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.fecha.compareTo(a.fecha));
          return list;
        });
  }

  Stream<List<RecepcionDoc>> streamRecepcionesByProveedor(
    String empresaId,
    String proveedorId,
  ) => _db
      .collection('TBL_COMPRAS_RECEPCIONES')
      .where('empresaId', isEqualTo: empresaId)
      .where('proveedorId', isEqualTo: proveedorId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      });

  // Filtra client-side para evitar índice compuesto con arrayContains
  Stream<List<RecepcionDoc>> streamRecepcionesByProducto(
    String empresaId,
    String productoId,
  ) => _db
      .collection('TBL_COMPRAS_RECEPCIONES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
            .where((r) => r.productoIds.contains(productoId))
            .toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      });

  Future<void> eliminarRecepcion(String id) =>
      _db.collection('TBL_COMPRAS_RECEPCIONES').doc(id).delete();

  /// Stream de recepciones con al menos un documento por revisar en calidad.
  /// Incluye documentos con estado 'pendiente' y documentos históricos con
  /// archivo adjunto pero sin estadoCalidad explícito.
  Stream<List<RecepcionDoc>> streamPendientesRevision(String empresaId) => _db
      .collection('TBL_COMPRAS_RECEPCIONES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
            .where(
              (r) => r.productos.any(
                (p) => p.documentos.entries.any(
                  (entry) =>
                      esDocumentoPermanenteRecepcion(entry.key) &&
                      entry.value.tieneDoc &&
                      (entry.value.estadoCalidad.isEmpty ||
                          entry.value.estadoCalidad == 'pendiente' ||
                          entry.value.estadoCalidad ==
                              'pendiente_revision_calidad'),
                ),
              ),
            )
            .toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      });

  Future<String> guardarRecepcion(RecepcionDoc r) async {
    final ref = r.id.isEmpty
        ? _db.collection('TBL_COMPRAS_RECEPCIONES').doc()
        : _db.collection('TBL_COMPRAS_RECEPCIONES').doc(r.id);
    await ref.set(r.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  /// Reabre de forma controlada una recepción cerrada únicamente para
  /// reemplazar los documentos que Calidad rechazó. Encabezado, productos,
  /// marcas, lotes y documentos no rechazados permanecen intactos.
  Future<void> reenviarRecepcionCorregida({
    required String recepcionId,
    required String userId,
    required Map<String, DocAdjunto> correcciones,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcionId);
    late RecepcionDoc actualizada;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw StateError('No se encontró la recepción para corregir.');
      }
      final actual = RecepcionDoc.fromMap(snap.id, snap.data()!);
      final error = validarCorreccionesRecepcion(
        original: actual,
        correcciones: correcciones,
      );
      if (error != null) throw StateError(error);

      final productos = <RecepcionProducto>[];
      for (final producto in actual.productos) {
        final documentos = Map<String, DocAdjunto>.from(producto.documentos);
        for (final entry in producto.documentos.entries) {
          final key = claveDocumentoRecepcion(producto.productoId, entry.key);
          final corregido = correcciones[key];
          if (corregido != null) documentos[entry.key] = corregido;
        }
        productos.add(producto.copyWith(documentos: documentos));
      }
      actualizada = RecepcionDoc(
        id: actual.id,
        empresaId: actual.empresaId,
        fecha: actual.fecha,
        proveedorId: actual.proveedorId,
        nit: actual.nit,
        razonSocial: actual.razonSocial,
        ordenCompra: actual.ordenCompra,
        bodega: actual.bodega,
        grupoId: actual.grupoId,
        grupoNombre: actual.grupoNombre,
        productos: productos,
        productoIds: actual.productoIds,
        creadoPor: actual.creadoPor,
        createdAt: actual.createdAt,
      );
      tx.update(ref, {
        'productos': productos.map((producto) => producto.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _marcarCorreccionesRecepcionEnRevision(
      recepcion: actualizada,
      userId: userId,
      correcciones: correcciones,
    );
  }

  Future<void> _marcarCorreccionesRecepcionEnRevision({
    required RecepcionDoc recepcion,
    required String userId,
    required Map<String, DocAdjunto> correcciones,
  }) async {
    final tasks = await _db
        .collection(TaskService.tasksCol)
        .where('empresaId', isEqualTo: recepcion.empresaId)
        .get();
    final now = Timestamp.now();
    final batch = _db.batch();
    var cambios = 0;
    for (final task in tasks.docs) {
      final data = task.data();
      if ((data['origen'] ?? '').toString() != 'compras_correccion') continue;
      final correction = Map<String, dynamic>.from(
        (data['comprasCorreccion'] as Map?) ?? const <String, dynamic>{},
      );
      if ((correction['tipo'] ?? '').toString() != 'recepcion' ||
          (correction['entidadId'] ?? '').toString() != recepcion.id) {
        continue;
      }
      final productoId = (correction['productoId'] ?? '').toString();
      final docKey = (correction['docKey'] ?? '').toString();
      final clave = claveDocumentoRecepcion(productoId, docKey);
      final documento = correcciones[clave];
      if (documento == null) continue;
      final asignado = (data['asignado_uid'] ?? '').toString().trim();
      if (asignado.isNotEmpty && asignado != userId.trim()) continue;
      final estado = (data['estado'] ?? data['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (estado == 'finalizado') continue;

      batch.update(task.reference, {
        'estado': 'por_aprobar',
        'status': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente_revision_calidad',
        'solicitud_finalizacion_at': now,
        'solicitud_finalizacion_by_uid': userId.trim(),
        'lastEventType': 'compras_documento_corregido',
        'lastEventAt': now,
        'lastEventText': 'Documento corregido enviado a revisión de Calidad',
        'fecha_actualizacion': now,
        'updatedAt': now,
        'comprasCorreccion.estado': 'en_revision_calidad',
        'comprasCorreccion.documentoNombre':
            documento.nombre?.trim() ?? 'Documento corregido',
        'comprasCorreccion.documentoUrl': documento.url?.trim() ?? '',
        'comprasCorreccion.enviadoRevisionAt': now,
      });
      cambios++;
    }
    if (cambios > 0) await batch.commit();
  }

  /// Reemplaza un documento de una recepción ya creada sin sobrescribir los
  /// demás productos o documentos que puedan haber cambiado en paralelo.
  Future<void> actualizarDocRecepcion({
    required String recepcionId,
    required String productoId,
    required String docKey,
    required DocAdjunto doc,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcionId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw StateError('No se encontró la recepción para actualizar.');
      }
      final recepcion = RecepcionDoc.fromMap(snap.id, snap.data()!);
      final index = recepcion.productos.indexWhere(
        (producto) => producto.productoId == productoId,
      );
      if (index < 0) {
        throw StateError('No se encontró el producto de la recepción.');
      }
      final productos = List<RecepcionProducto>.from(recepcion.productos);
      final producto = productos[index];
      productos[index] = producto.copyWith(
        documentos: {...producto.documentos, docKey: doc},
      );
      tx.update(ref, {
        'productos': productos.map((producto) => producto.toMap()).toList(),
        'updatedAt': Timestamp.now(),
      });
    });
  }

  /// Aprueba un documento específico en una recepción.
  /// Actualiza el estadoCalidad del doc a 'aprobado'.
  Future<void> aprobarDocRecepcion({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String revisadoPor,
  }) async {
    if (esDocumentoTransitorioRecepcion(docKey)) {
      throw StateError(
        'Los documentos transitorios de recepción solo se pueden consultar o rechazar.',
      );
    }
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) return;
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final rp = productos[productoIdx];
    final docActual = rp.documentos[docKey];
    if (docActual == null) return;

    final docActualizado = docActual.copyWith(
      estadoCalidad: 'aprobado',
      revisadoPor: revisadoPor,
      fechaRevision: Timestamp.now(),
      requerimientoEstado: docActual.aprobadoConRequerimientos
          ? 'resuelto'
          : docActual.requerimientoEstado,
      requerimientoResueltoAt: docActual.aprobadoConRequerimientos
          ? Timestamp.now()
          : docActual.requerimientoResueltoAt,
      requerimientoResueltoPor: docActual.aprobadoConRequerimientos
          ? revisadoPor
          : docActual.requerimientoResueltoPor,
    );
    final docsActualizados = Map<String, DocAdjunto>.from(rp.documentos)
      ..[docKey] = docActualizado;
    productos[productoIdx] = rp.copyWith(documentos: docsActualizados);

    await _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcion.id).update({
      'productos': productos.map((p) => p.toMap()).toList(),
    });

    await _finalizarTareasCorreccionAprobadas(
      empresaId: recepcion.empresaId,
      tipo: 'recepcion',
      entidadId: recepcion.id,
      productoId: rp.productoId,
      docKey: docKey,
      revisadoPor: revisadoPor,
    );
  }

  Future<void> aprobarConRequerimientosDocRecepcion({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
    required String revisadoPor,
  }) async {
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) return;
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final producto = productos[productoIdx];
    final actual = producto.documentos[docKey];
    if (actual == null || !actual.tieneDoc) return;
    productos[productoIdx] = producto.copyWith(
      documentos: {
        ...producto.documentos,
        docKey: _conRequerimiento(
          actual,
          nota: nota,
          requiereAdjunto: requiereAdjunto,
          fechaLimite: fechaLimite,
          revisadoPor: revisadoPor,
        ),
      },
    );
    await _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcion.id).update({
      'productos': productos.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _notificarYTareaRequerimiento(
      empresaId: recepcion.empresaId,
      responsableId: actual.subidoPor ?? recepcion.creadoPor,
      revisadoPor: revisadoPor,
      entidadId: recepcion.id,
      tipo: 'recepcion',
      productoId: producto.productoId,
      productoNombre: producto.nombre,
      docKey: docKey,
      docLabel: kDocRecepcionLabels[docKey] ?? docKey,
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
    );
  }

  /// Revierte la aprobación de un documento de recepción.
  ///
  /// Acción excepcional del Admin Documental para corregir una aprobación dada
  /// por error, sin obligar a descargar y volver a subir el archivo.
  ///
  /// Con [rechazar] en false el documento vuelve a la cola de Calidad; con true
  /// queda rechazado, se notifica a quien lo subió y se crea la tarea de
  /// corrección, igual que un rechazo normal.
  ///
  /// El [motivo] es obligatorio y queda registrado en el documento junto con
  /// quién revirtió y cuándo.
  Future<void> revertirAprobacionDocRecepcion({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String motivo,
    required String revertidoPor,
    bool rechazar = false,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      throw StateError('Debes indicar el motivo de la reversión.');
    }
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) {
      throw StateError('El producto ya no existe en la recepción.');
    }
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final rp = productos[productoIdx];
    final docActual = rp.documentos[docKey];
    if (docActual == null || !docActual.tieneDoc) {
      throw StateError('El documento ya no existe en la recepción.');
    }
    if (!docActual.aprobado) {
      throw StateError(
        'Solo se puede revertir un documento aprobado. '
        'Estado actual: ${docActual.estadoCalidad}',
      );
    }

    // Al volver a revisión respetamos la naturaleza del documento: los
    // transitorios regresan a 'consulta_calidad' y los permanentes a
    // 'pendiente_revision_calidad'.
    final nuevoEstado = rechazar
        ? 'rechazado'
        : estadoInicialDocumentoRecepcion(docKey);

    final docActualizado = docActual.copyWith(
      estadoCalidad: nuevoEstado,
      observacionCalidad: rechazar ? motivoLimpio : null,
      revertidoPor: revertidoPor,
      fechaReversion: Timestamp.now(),
      motivoReversion: motivoLimpio,
      estadoAnteriorReversion: docActual.estadoCalidad,
    );
    final docsActualizados = Map<String, DocAdjunto>.from(rp.documentos)
      ..[docKey] = docActualizado;
    productos[productoIdx] = rp.copyWith(documentos: docsActualizados);

    await _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcion.id).update({
      'productos': productos.map((p) => p.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!rechazar) return;

    // Rechazo: mismo camino que rechazarDocRecepcion para que el subidor reciba
    // la notificación y la tarea con el plazo configurado por la empresa.
    final subidoPor = (docActual.subidoPor?.trim().isNotEmpty ?? false)
        ? docActual.subidoPor!.trim()
        : recepcion.creadoPor;
    final label = kDocRecepcionLabels[docKey] ?? docKey;
    await _notificarYTareaRechazo(
      empresaId: recepcion.empresaId,
      subidoPor: subidoPor,
      revisadoPor: revertidoPor,
      title: 'Aprobación revertida - documento rechazado',
      descripcionSubidor:
          'La aprobación del documento "$label" de ${rp.nombre} fue revertida y '
          'el documento quedó rechazado. Motivo: $motivoLimpio. '
          'Por favor corrígelo y vuelve a cargarlo.',
      type: 'recepcion_doc_rechazado',
      taskKey: 'recepcion:${recepcion.id}',
      recepcionId: recepcion.id,
      tipoCorreccion: 'recepcion',
      productoNombre: rp.nombre,
      productoId: rp.productoId,
      docKey: docKey,
      docLabel: label,
      motivo: motivoLimpio,
    );
  }

  /// Marca un documento transitorio como revisado sin convertirlo en una
  /// aprobación documental permanente.
  Future<void> marcarDocRecepcionConsultado({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String revisadoPor,
  }) async {
    if (!esDocumentoTransitorioRecepcion(docKey)) {
      throw StateError(
        'Solo los documentos transitorios pueden marcarse como consultados.',
      );
    }
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) return;
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final producto = productos[productoIdx];
    final actual = producto.documentos[docKey];
    if (actual == null || !actual.tieneDoc) return;
    productos[productoIdx] = producto.copyWith(
      documentos: {
        ...producto.documentos,
        docKey: actual.copyWith(
          estadoCalidad: 'consultado',
          revisadoPor: revisadoPor,
          fechaRevision: Timestamp.now(),
        ),
      },
    );
    await _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcion.id).update({
      'productos': productos.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rechaza un documento específico en una recepción y crea notificación.
  Future<void> rechazarDocRecepcion({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String motivo,
    required String revisadoPor,
  }) async {
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) return;
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final rp = productos[productoIdx];
    final docActual = rp.documentos[docKey];
    if (docActual == null) return;

    final docActualizado = docActual.copyWith(
      estadoCalidad: 'rechazado',
      observacionCalidad: motivo,
      revisadoPor: revisadoPor,
      fechaRevision: Timestamp.now(),
    );
    final docsActualizados = Map<String, DocAdjunto>.from(rp.documentos)
      ..[docKey] = docActualizado;
    productos[productoIdx] = rp.copyWith(documentos: docsActualizados);

    await _db.collection('TBL_COMPRAS_RECEPCIONES').doc(recepcion.id).update({
      'productos': productos.map((p) => p.toMap()).toList(),
    });

    // Notificar (subidor + todo Calidad) y crear la tarea de corrección.
    // El destinatario "subidor" es quien cargó el doc; si no consta, se usa el
    // creador de la recepción.
    final subidoPor = (docActual.subidoPor?.trim().isNotEmpty ?? false)
        ? docActual.subidoPor!.trim()
        : recepcion.creadoPor;
    final label = kDocRecepcionLabels[docKey] ?? docKey;
    await _notificarYTareaRechazo(
      empresaId: recepcion.empresaId,
      subidoPor: subidoPor,
      revisadoPor: revisadoPor,
      title: 'Documento de recepción rechazado',
      descripcionSubidor:
          'El documento "$label" de ${rp.nombre} fue rechazado. Motivo: $motivo. Por favor corrígelo y vuelve a cargarlo.',
      type: 'recepcion_doc_rechazado',
      taskKey: 'recepcion:${recepcion.id}',
      recepcionId: recepcion.id,
      tipoCorreccion: 'recepcion',
      productoNombre: rp.nombre,
      productoId: rp.productoId,
      docKey: docKey,
      docLabel: label,
      motivo: motivo,
    );
  }

  // ─── MARCAS ─────────────────────────────────────────────────────────────────

  Stream<List<MarcaDoc>> streamMarcas(String empresaId) => _db
      .collection('TBL_COMPRAS_MARCAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => MarcaDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.descripcion.compareTo(b.descripcion));
        return list;
      });

  Future<String> generarCodigoMarca(String empresaId) async {
    final configRef = _db.collection('TBL_COMPRAS_CONFIG').doc(empresaId);
    int seq = 1;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(configRef);
      seq = ((snap.data()?['marcaSeq'] as int?) ?? 0) + 1;
      tx.set(configRef, {'marcaSeq': seq}, SetOptions(merge: true));
    });
    return 'MRC-${seq.toString().padLeft(4, '0')}';
  }

  Future<String> guardarMarca(MarcaDoc m, {required bool isNew}) async {
    final existentesSnap = await _db
        .collection('TBL_COMPRAS_MARCAS')
        .where('empresaId', isEqualTo: m.empresaId)
        .get();
    final existentes = existentesSnap.docs
        .map((doc) => MarcaDoc.fromMap(doc.id, doc.data()))
        .toList();
    final duplicada = buscarMarcaDuplicada(
      existentes,
      codigo: m.codigo,
      descripcion: m.descripcion,
      excluirId: isNew ? '' : m.id,
    );
    if (duplicada != null) {
      throw StateError(
        'Ya existe la marca ${duplicada.descripcion} (${duplicada.codigo}) en esta empresa.',
      );
    }
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_MARCAS').doc()
        : _db.collection('TBL_COMPRAS_MARCAS').doc(m.id);
    await ref.set(m.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> actualizarDocumentosAsociadosMarca({
    required String marcaId,
    required Map<String, DocAdjunto> documentos,
  }) => _db.collection('TBL_COMPRAS_MARCAS').doc(marcaId).update({
    'documentosAsociados': documentos.map(
      (key, value) => MapEntry(key, value.toMap()),
    ),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Recupera documentos vinculados a una marca que quedaron almacenados por
  /// modelos anteriores. Es solo una vista consolidada: no modifica Firestore
  /// ni duplica archivos en Storage.
  Future<List<DocumentoMarcaVinculado>> getDocumentosVinculadosMarca(
    String empresaId,
    String marcaId, {
    String marcaNombre = '',
  }) async {
    final resultados = await Future.wait([
      _db
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    final productosSnap = resultados[0];
    final fichasSnap = resultados[1];
    final productos = productosSnap.docs
        .map((doc) => ProductoDoc.fromMap(doc.id, doc.data()))
        .toList();
    final fichas = fichasSnap.docs
        .map((doc) => FichaTecnicaDoc.fromMap(doc.id, doc.data()))
        .toList();
    return consolidarDocumentosMarcaVinculados(
      marcaId: marcaId,
      marcaNombre: marcaNombre,
      productos: productos,
      fichasTecnicas: fichas,
    );
  }

  Future<void> aprobarDocMarca({
    required String marcaId,
    required String docKey,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_MARCAS').doc(marcaId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final marca = MarcaDoc.fromMap(snap.id, snap.data()!);
    final actual = marca.documentosAsociados[docKey];
    if (actual == null || !actual.tieneDoc) return;
    if (documentoRequiereVigencia(docKey) && actual.fechaVencimiento == null) {
      throw StateError(
        'Indica “Vigente hasta” antes de aprobar '
        '${kDocumentosAsociadosLabels[docKey] ?? docKey}.',
      );
    }
    final documentos = Map<String, DocAdjunto>.from(marca.documentosAsociados)
      ..[docKey] = actual.copyWith(
        estadoCalidad: 'aprobado',
        observacionCalidad: '',
        revisadoPor: revisadoPor,
        fechaRevision: Timestamp.now(),
        requerimientoEstado: actual.aprobadoConRequerimientos
            ? 'resuelto'
            : actual.requerimientoEstado,
        requerimientoResueltoAt: actual.aprobadoConRequerimientos
            ? Timestamp.now()
            : actual.requerimientoResueltoAt,
        requerimientoResueltoPor: actual.aprobadoConRequerimientos
            ? revisadoPor
            : actual.requerimientoResueltoPor,
      );
    await actualizarDocumentosAsociadosMarca(
      marcaId: marcaId,
      documentos: documentos,
    );
    await _finalizarTareasCorreccionAprobadas(
      empresaId: marca.empresaId,
      tipo: 'marca',
      entidadId: marcaId,
      docKey: docKey,
      revisadoPor: revisadoPor,
    );
  }

  Future<void> aprobarConRequerimientosDocMarca({
    required String marcaId,
    required String docKey,
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_MARCAS').doc(marcaId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final marca = MarcaDoc.fromMap(snap.id, snap.data()!);
    final actual = marca.documentosAsociados[docKey];
    if (actual == null || !actual.tieneDoc) return;
    await actualizarDocumentosAsociadosMarca(
      marcaId: marcaId,
      documentos: {
        ...marca.documentosAsociados,
        docKey: _conRequerimiento(
          actual,
          nota: nota,
          requiereAdjunto: requiereAdjunto,
          fechaLimite: fechaLimite,
          revisadoPor: revisadoPor,
        ),
      },
    );
    await _notificarYTareaRequerimiento(
      empresaId: marca.empresaId,
      responsableId: actual.subidoPor ?? '',
      revisadoPor: revisadoPor,
      entidadId: marcaId,
      tipo: 'marca',
      productoNombre: marca.descripcion,
      docKey: docKey,
      docLabel: kDocumentosAsociadosLabels[docKey] ?? docKey,
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
    );
  }

  Future<void> rechazarDocMarca({
    required String marcaId,
    required String docKey,
    required String motivo,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_MARCAS').doc(marcaId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final marca = MarcaDoc.fromMap(snap.id, snap.data()!);
    final actual = marca.documentosAsociados[docKey];
    if (actual == null || !actual.tieneDoc) return;
    final documentos = Map<String, DocAdjunto>.from(marca.documentosAsociados)
      ..[docKey] = actual.copyWith(
        estadoCalidad: 'rechazado',
        observacionCalidad: motivo.trim(),
        revisadoPor: revisadoPor,
        fechaRevision: Timestamp.now(),
      );
    await actualizarDocumentosAsociadosMarca(
      marcaId: marcaId,
      documentos: documentos,
    );

    final label = kDocumentosAsociadosLabels[docKey] ?? docKey;
    await _notificarYTareaRechazo(
      empresaId: marca.empresaId,
      subidoPor: actual.subidoPor ?? '',
      revisadoPor: revisadoPor,
      title: 'Documento de marca rechazado',
      descripcionSubidor:
          'El documento "$label" de la marca ${marca.descripcion} fue rechazado. '
          'Motivo: ${motivo.trim()}. Reemplázalo para enviarlo nuevamente a Calidad.',
      type: 'marca_doc_rechazado',
      taskKey: 'marca:$marcaId',
      recepcionId: 'marca:$marcaId',
      tipoCorreccion: 'marca',
      productoNombre: marca.descripcion,
      docKey: docKey,
      docLabel: label,
      motivo: motivo.trim(),
    );
  }

  Future<void> eliminarMarca(String id) =>
      _db.collection('TBL_COMPRAS_MARCAS').doc(id).delete();

  // ─── STORAGE ────────────────────────────────────────────────────────────────

  Future<DocAdjunto> subirBytes({
    required Uint8List bytes,
    required String empresaId,
    required String carpeta,
    required String nombre,
    required String contentType,

    /// Si es true, el doc se marca como 'pendiente' de revisión calidad
    bool pendienteCalidad = false,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'compras/$empresaId/$carpeta/${ts}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    return DocAdjunto(
      url: url,
      nombre: nombre,
      path: path,
      fechaSubida: Timestamp.now(),
      estadoCalidad: pendienteCalidad ? 'pendiente' : '',
    );
  }

  /// Adjunta la evidencia solicitada por Calidad sin reemplazar el documento
  /// original. El archivo se conserva por separado y una Cloud Function crea
  /// una versión PDF consolidada para consulta. El requerimiento continúa
  /// abierto hasta que Calidad apruebe expresamente el consolidado.
  Future<DocAdjunto> agregarSoporteRequerimiento({
    required String empresaId,
    required String tipo,
    required String entidadId,
    required String docKey,
    required String userId,
    required Uint8List bytes,
    required String nombre,
    required String contentType,
    String productoId = '',
  }) async {
    final empresa = empresaId.trim();
    final entidad = entidadId.trim();
    final usuario = userId.trim();
    if (empresa.isEmpty || entidad.isEmpty || docKey.trim().isEmpty) {
      throw StateError(
        'No se pudo identificar el documento del requerimiento.',
      );
    }

    DocAdjunto? actual;
    MarcaDoc? marca;
    FichaTecnicaDoc? ficha;
    ProveedorDoc? proveedor;
    RecepcionDoc? recepcion;

    switch (tipo) {
      case 'marca':
        final snap = await _db
            .collection('TBL_COMPRAS_MARCAS')
            .doc(entidad)
            .get();
        if (snap.exists && snap.data() != null) {
          marca = MarcaDoc.fromMap(snap.id, snap.data()!);
          actual = marca.documentosAsociados[docKey];
        }
        break;
      case 'ficha':
        final snap = await _db
            .collection('TBL_COMPRAS_FICHAS_TECNICAS')
            .doc(entidad)
            .get();
        if (snap.exists && snap.data() != null) {
          ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
          actual = ficha.documentoActual;
        }
        break;
      case 'proveedor':
        final snap = await _db
            .collection('TBL_COMPRAS_PROVEEDORES')
            .doc(entidad)
            .get();
        if (snap.exists && snap.data() != null) {
          proveedor = ProveedorDoc.fromMap(snap.id, snap.data()!);
          actual = proveedor.documentos[docKey];
        }
        break;
      case 'recepcion':
        final snap = await _db
            .collection('TBL_COMPRAS_RECEPCIONES')
            .doc(entidad)
            .get();
        if (snap.exists && snap.data() != null) {
          recepcion = RecepcionDoc.fromMap(snap.id, snap.data()!);
          final producto = recepcion.productos
              .where((item) => item.productoId == productoId)
              .firstOrNull;
          actual = producto?.documentos[docKey];
        }
        break;
      default:
        throw StateError('Tipo de documento de Compras no soportado: $tipo.');
    }

    if (actual == null || !actual.tieneDoc) {
      throw StateError('El documento original ya no está disponible.');
    }
    if (!actual.aprobadoConRequerimientos || !actual.requerimientoAbierto) {
      throw StateError('Este documento no tiene un requerimiento abierto.');
    }
    if (!actual.requerimientoRequiereAdjunto) {
      throw StateError('Este requerimiento no solicita un archivo adjunto.');
    }
    final responsable = actual.requerimientoResponsableId?.trim() ?? '';
    if (responsable.isNotEmpty &&
        usuario.isNotEmpty &&
        responsable != usuario) {
      throw StateError(
        'Solo el responsable asignado puede adjuntar el soporte.',
      );
    }

    final soporteSubido = await subirBytes(
      bytes: bytes,
      empresaId: empresa,
      carpeta: 'requerimientos/$tipo/$entidad/$docKey',
      nombre: nombre,
      contentType: contentType,
    );

    final originalPath =
        actual.documentoConsolidadoPath?.trim().isNotEmpty == true
        ? actual.documentoConsolidadoPath!
        : (actual.documentoOriginalPath ?? actual.path ?? '');
    final originalUrl =
        actual.documentoConsolidadoUrl?.trim().isNotEmpty == true
        ? actual.documentoConsolidadoUrl!
        : (actual.documentoOriginalUrl ?? actual.url ?? '');
    final originalName =
        actual.documentoConsolidadoPath?.trim().isNotEmpty == true
        ? 'documento_consolidado.pdf'
        : (actual.documentoOriginalNombre ?? actual.nombre ?? 'documento.pdf');

    try {
      final response = await _functions
          .httpsCallable('comprasConsolidarRequerimiento')
          .call({
            'empresaId': empresa,
            'originalPath': originalPath,
            'originalUrl': originalUrl,
            'originalName': originalName,
            'soportePath': soporteSubido.path ?? '',
            'soporteUrl': soporteSubido.url ?? '',
            'soporteName': nombre,
          });
      final result = Map<String, dynamic>.from(response.data as Map);
      final consolidadoUrl = (result['url'] ?? '').toString().trim();
      final consolidadoPath = (result['path'] ?? '').toString().trim();
      if (consolidadoUrl.isEmpty || consolidadoPath.isEmpty) {
        throw StateError('La consolidación no devolvió un archivo válido.');
      }

      final soporte = DocSoporteRequerimiento(
        url: soporteSubido.url ?? '',
        nombre: nombre,
        path: soporteSubido.path ?? '',
        subidoPor: usuario,
        fechaSubida: Timestamp.now(),
      );
      final actualizado = actual.copyWith(
        url: consolidadoUrl,
        path: consolidadoPath,
        nombre: 'documento_consolidado_${docKey.trim()}.pdf',
        requerimientoEstado: 'en_revision',
        soportesRequerimiento: [...actual.soportesRequerimiento, soporte],
        documentoOriginalUrl: actual.documentoOriginalUrl ?? actual.url,
        documentoOriginalPath: actual.documentoOriginalPath ?? actual.path,
        documentoOriginalNombre:
            actual.documentoOriginalNombre ?? actual.nombre,
        documentoConsolidadoUrl: consolidadoUrl,
        documentoConsolidadoPath: consolidadoPath,
      );

      switch (tipo) {
        case 'marca':
          await actualizarDocumentosAsociadosMarca(
            marcaId: entidad,
            documentos: {...marca!.documentosAsociados, docKey: actualizado},
          );
          break;
        case 'ficha':
          await _db
              .collection('TBL_COMPRAS_FICHAS_TECNICAS')
              .doc(entidad)
              .update({
                'documentoActual': actualizado.toMap(),
                'documentoAprobado': actualizado.toMap(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
          break;
        case 'proveedor':
          await actualizarDocProveedor(
            proveedorId: entidad,
            docKey: docKey,
            doc: actualizado,
          );
          break;
        case 'recepcion':
          await actualizarDocRecepcion(
            recepcionId: entidad,
            productoId: productoId,
            docKey: docKey,
            doc: actualizado,
          );
          break;
      }

      await _marcarTareaRequerimientoEnRevision(
        empresaId: empresa,
        tipo: tipo,
        entidadId: entidad,
        productoId: productoId,
        docKey: docKey,
        userId: usuario,
        documento: actualizado,
      );
      return actualizado;
    } catch (_) {
      // Si falla la consolidación, el soporte continúa preservado en Storage,
      // pero no se altera el documento aprobado ni su trazabilidad.
      rethrow;
    }
  }

  Future<void> _marcarTareaRequerimientoEnRevision({
    required String empresaId,
    required String tipo,
    required String entidadId,
    required String productoId,
    required String docKey,
    required String userId,
    required DocAdjunto documento,
  }) async {
    final tasks = await _db
        .collection(TaskService.tasksCol)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final matching = tasks.docs.where((task) {
      final data = task.data();
      if ((data['origen'] ?? '').toString() != 'compras_correccion') {
        return false;
      }
      final correction = Map<String, dynamic>.from(
        (data['comprasCorreccion'] as Map?) ?? const <String, dynamic>{},
      );
      if (correction['esRequerimiento'] != true ||
          (correction['tipo'] ?? '').toString() != tipo ||
          (correction['entidadId'] ?? '').toString() != entidadId ||
          (correction['docKey'] ?? '').toString() != docKey) {
        return false;
      }
      if (tipo == 'recepcion' &&
          (correction['productoId'] ?? '').toString() != productoId) {
        return false;
      }
      final asignado = (data['asignado_uid'] ?? '').toString().trim();
      return asignado.isEmpty || userId.isEmpty || asignado == userId;
    }).toList();
    if (matching.isEmpty) return;

    final now = Timestamp.now();
    final batch = _db.batch();
    for (final task in matching) {
      batch.update(task.reference, {
        'estado': 'por_aprobar',
        'status': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente_revision_calidad',
        'solicitud_finalizacion_at': now,
        'solicitud_finalizacion_by_uid': userId,
        'lastEventType': 'compras_requerimiento_atendido',
        'lastEventAt': now,
        'lastEventText': 'Soporte enviado a revisión de Calidad',
        'fecha_actualizacion': now,
        'updatedAt': now,
        'comprasCorreccion.estado': 'en_revision_calidad',
        'comprasCorreccion.documentoNombre': documento.nombre ?? '',
        'comprasCorreccion.documentoUrl': documento.url ?? '',
        'comprasCorreccion.enviadoRevisionAt': now,
      });
    }
    await batch.commit();
  }

  Future<void> eliminarArchivo(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (_) {}
  }

  Future<int> limpiarRechazadosExpirados(
    String empresaId, {
    Duration? maxAge,
  }) async {
    final effectiveAge =
        maxAge ?? Duration(days: await obtenerDiasPlazoRechazados(empresaId));
    final limite = DateTime.now().subtract(effectiveAge);
    var eliminados = 0;

    eliminados += await _limpiarRecepcionesRechazadasExpiradas(
      empresaId,
      limite,
    );
    eliminados += await _limpiarProveedoresRechazadosExpirados(
      empresaId,
      limite,
    );
    eliminados += await _limpiarFichasRechazadasExpiradas(empresaId, limite);

    return eliminados;
  }

  bool _esRechazadoExpirado(DocAdjunto? doc, DateTime limite) {
    if (doc == null || !doc.tieneDoc || !doc.rechazado) return false;
    final fechaRevision = doc.fechaRevision?.toDate();
    if (fechaRevision == null) return false;
    return !fechaRevision.isAfter(limite);
  }

  Future<int> _limpiarRecepcionesRechazadasExpiradas(
    String empresaId,
    DateTime limite,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    var eliminados = 0;
    for (final doc in snap.docs) {
      final recepcion = RecepcionDoc.fromMap(doc.id, doc.data());
      var huboCambios = false;
      final productosActualizados = <RecepcionProducto>[];

      for (final producto in recepcion.productos) {
        var cambioProducto = false;
        final docsActualizados = <String, DocAdjunto>{};

        for (final entry in producto.documentos.entries) {
          final actual = entry.value;
          if (_esRechazadoExpirado(actual, limite)) {
            if (actual.path?.isNotEmpty == true) {
              await eliminarArchivo(actual.path!);
            }
            docsActualizados[entry.key] = const DocAdjunto();
            cambioProducto = true;
            eliminados++;
          } else {
            docsActualizados[entry.key] = actual;
          }
        }

        productosActualizados.add(
          cambioProducto
              ? producto.copyWith(documentos: docsActualizados)
              : producto,
        );
        if (cambioProducto) huboCambios = true;
      }

      if (huboCambios) {
        await doc.reference.update({
          'productos': productosActualizados.map((p) => p.toMap()).toList(),
        });
      }
    }

    return eliminados;
  }

  Future<int> _limpiarProveedoresRechazadosExpirados(
    String empresaId,
    DateTime limite,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    var eliminados = 0;
    for (final doc in snap.docs) {
      final proveedor = ProveedorDoc.fromMap(doc.id, doc.data());
      var huboCambios = false;
      final docsActualizados = <String, DocAdjunto>{};

      for (final entry in proveedor.documentos.entries) {
        final actual = entry.value;
        if (_esRechazadoExpirado(actual, limite)) {
          if (actual.path?.isNotEmpty == true) {
            await eliminarArchivo(actual.path!);
          }
          docsActualizados[entry.key] = const DocAdjunto();
          huboCambios = true;
          eliminados++;
        } else {
          docsActualizados[entry.key] = actual;
        }
      }

      if (huboCambios) {
        await doc.reference.update({
          'documentos': docsActualizados.map((k, v) => MapEntry(k, v.toMap())),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    return eliminados;
  }

  Future<int> _limpiarFichasRechazadasExpiradas(
    String empresaId,
    DateTime limite,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    var eliminados = 0;
    for (final doc in snap.docs) {
      final ficha = FichaTecnicaDoc.fromMap(doc.id, doc.data());
      final actual = ficha.documentoActual;
      if (!_esRechazadoExpirado(actual, limite)) continue;

      if (actual?.path?.isNotEmpty == true) {
        await eliminarArchivo(actual!.path!);
      }
      await doc.reference.update({
        'documentoActual': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      eliminados++;
    }

    return eliminados;
  }

  // ─── ROLES COMPRAS ───────────────────────────────────────────────────────────

  Stream<List<ComprasRolDoc>> streamComprasRoles(String empresaId) => _db
      .collection('TBL_COMPRAS_ROLES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => ComprasRolDoc.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.nombre.compareTo(b.nombre)),
      );

  Future<ComprasRolDoc?> getRolUsuario(String empresaId, String userId) async {
    // Query single-field only (no composite index needed) + client filter
    final snap = await _db
        .collection('TBL_COMPRAS_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final identity = userId.trim();
    final match = snap.docs.where((d) {
      final data = d.data();
      return (data['userId'] ?? '').toString().trim() == identity ||
          (data['cedula'] ?? '').toString().trim() == identity;
    });
    if (match.isEmpty) return null;
    return ComprasRolDoc.fromMap(match.first.id, match.first.data());
  }

  Future<ComprasRolDoc?> resolveRolUsuario(
    String empresaId,
    String userId,
  ) async {
    final explicit = await getRolUsuario(empresaId, userId);
    if (explicit != null) return explicit;

    final userSnap = await _resolveUserDoc(userId);
    final data = userSnap?.data();
    if (userSnap == null || data == null) return null;

    final rol = _inferComprasRolFromUserData(data, empresaId);
    if (rol == null) return null;

    final cedula = (data['cedula'] ?? userId).toString().trim();
    final nombre = [
      (data['nombres'] ?? data['primerNombre'] ?? '').toString().trim(),
      (data['apellidos'] ?? data['primerApellido'] ?? '').toString().trim(),
    ].where((part) => part.isNotEmpty).join(' ').trim();

    return ComprasRolDoc(
      empresaId: empresaId,
      userId: userSnap.id,
      cedula: cedula.isEmpty ? userId : cedula,
      nombre: nombre.isEmpty
          ? (data['nombre'] ?? data['usuario'] ?? userSnap.id).toString()
          : nombre,
      rol: rol,
      createdAt: Timestamp.now(),
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveUserDoc(
    String userId,
  ) async {
    if (userId.trim().isEmpty) return null;

    final direct = await _db.collection('TBL_USUARIOS').doc(userId).get();
    if (direct.exists) return direct;

    final byCedula = await _db
        .collection('TBL_USUARIOS')
        .where('cedula', isEqualTo: userId)
        .limit(1)
        .get();
    if (byCedula.docs.isNotEmpty) return byCedula.docs.first;

    return null;
  }

  String? _inferComprasRolFromUserData(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final scoped = data['empresasDetalle'];
    if (scoped is Map) {
      final rawDetail = scoped[empresaId];
      if (rawDetail is Map) {
        final detail = rawDetail.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final scopedRol = _firstNormalizedComprasRol(detail);
        if (scopedRol != null) return scopedRol;
      }
    }
    return _firstNormalizedComprasRol(data);
  }

  String? _firstNormalizedComprasRol(Map<String, dynamic> data) {
    const keys = [
      'rolCompras',
      'comprasRol',
      'rol_compras',
      'roleCompras',
      'roleKey',
      'role',
      'rol',
      'roleName',
      'cargo',
      'cargoNombre',
    ];
    for (final key in keys) {
      final rol = normalizeComprasRol(data[key]?.toString());
      if (rol == null) continue;
      if (rol == kRolCalidad ||
          rol == kRolAdmin ||
          rol == kRolCompras ||
          rol == kRolBodega ||
          rol == kRolConsultas) {
        return rol;
      }
    }
    return null;
  }

  Future<void> guardarComprasRol(ComprasRolDoc r, {required bool isNew}) async {
    if (isNew) {
      // ID determinístico {empresaId}_{userId} — evita query compuesto y duplicados
      final docId = '${r.empresaId}_${r.userId}';
      await _db
          .collection('TBL_COMPRAS_ROLES')
          .doc(docId)
          .set(r.toMap(), SetOptions(merge: true));
    } else {
      await _db
          .collection('TBL_COMPRAS_ROLES')
          .doc(r.id)
          .set(r.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> eliminarComprasRol(String id) =>
      _db.collection('TBL_COMPRAS_ROLES').doc(id).delete();

  // ─── NOTIFICACIONES ──────────────────────────────────────────────────────────

  // Centro de notificaciones ÚNICO: la campana de Compras es ahora una vista
  // filtrada del centro global (TBL_NOTIFICACIONES/{userId}/notifications) por
  // module == 'compras_bodega'. No existe colección interna paralela.
  // El filtro es client-side para no requerir índices compuestos nuevos
  // (la subcolección de notifs de un usuario es pequeña).
  Stream<List<NotificacionComprasDoc>> streamNotificaciones(
    String empresaId,
    String userId,
  ) {
    if (userId.trim().isEmpty) {
      return Stream<List<NotificacionComprasDoc>>.value(const []);
    }
    final eid = empresaId.trim();
    return _db
        .collection('TBL_NOTIFICACIONES')
        .doc(userId.trim())
        .collection('notifications')
        .snapshots()
        .map((s) {
          final list =
              s.docs
                  .where((d) {
                    final m = d.data();
                    if ((m['module'] ?? '') != 'compras_bodega') return false;
                    if (m['read'] == true) return false;
                    final notifEmpresa = (m['empresaId'] ?? '')
                        .toString()
                        .trim();
                    if (eid.isNotEmpty &&
                        notifEmpresa.isNotEmpty &&
                        notifEmpresa != eid) {
                      return false;
                    }
                    return true;
                  })
                  .map((d) => NotificacionComprasDoc.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Marca como leída en el centro global. Requiere el userId destinatario
  /// (incluido en el payload de la notificación de Compras).
  Future<void> marcarNotificacionLeida(String userId, String id) {
    if (userId.trim().isEmpty || id.trim().isEmpty) return Future.value();
    return _db
        .collection('TBL_NOTIFICACIONES')
        .doc(userId.trim())
        .collection('notifications')
        .doc(id.trim())
        .update({'read': true});
  }

  Future<void> marcarTodasLeidas(String empresaId, String userId) async {
    if (userId.trim().isEmpty) return;
    final col = _db
        .collection('TBL_NOTIFICACIONES')
        .doc(userId.trim())
        .collection('notifications');
    final snap = await col.get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      final m = d.data();
      if ((m['module'] ?? '') != 'compras_bodega') continue;
      if (m['read'] == true) continue;
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _crearNotificacionGlobalCompras({
    required String userId,
    required String empresaId,
    required String title,
    required String description,
    required String type,
    required String taskId,
    required String fromId,
    required String fromName,
    String? recepcionId,
    String? productoNombre,
    String? docKey,
    String? docLabel,
    String? motivo,
  }) async {
    if (userId.trim().isEmpty) return;

    final notifRef = _db
        .collection('TBL_NOTIFICACIONES')
        .doc(userId.trim())
        .collection('notifications')
        .doc();

    await notifRef.set({
      'id': notifRef.id,
      'title': title,
      'description': description,
      'type': type,
      'taskId': taskId,
      'fromId': fromId,
      'fromName': fromName,
      'module': 'compras_bodega',
      // userId destinatario embebido para poder marcar-leída desde la campana
      // de Compras sin reconsultar el path padre.
      'userId': userId.trim(),
      // Campos ricos que la campana de Compras muestra (producto, motivo, doc).
      if (recepcionId != null) 'recepcionId': recepcionId,
      if (productoNombre != null) 'productoNombre': productoNombre,
      if (docKey != null) 'docKey': docKey,
      if (docLabel != null) 'docLabel': docLabel,
      if (motivo != null) 'motivo': motivo,
      // Timestamp.now() (no serverTimestamp): el centro de notificaciones y el
      // badge ordenan por createdAt; serverTimestamp deja createdAt=null por un
      // instante en el snapshot local y desordena la campana. Igual que el
      // método canónico TaskService.pushNotification.
      'createdAt': Timestamp.now(),
      'read': false,
      if (empresaId.trim().isNotEmpty) 'empresaId': empresaId.trim(),
    });
  }

  /// Usuarios de la empresa que tienen un rol de Compras específico (p.ej. calidad).
  /// Devuelve los ComprasRolDoc; usa el doc.id / cédula como destinatario de notificaciones.
  Future<List<ComprasRolDoc>> getUsuariosPorRol(
    String empresaId,
    String rol,
  ) async {
    final objetivo = normalizeComprasRol(rol);
    if (objetivo == null) return const [];
    final snap = await _db
        .collection('TBL_COMPRAS_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) => ComprasRolDoc.fromMap(d.id, d.data()))
        .where((r) => normalizeComprasRol(r.rol) == objetivo)
        .toList();
  }

  /// Identificador de notificación/tarea para un usuario de Compras (cédula > userId).
  String _destinatario(ComprasRolDoc r) {
    final ced = r.cedula.trim();
    if (ced.isNotEmpty) return ced;
    return r.userId.trim();
  }

  DocAdjunto _conRequerimiento(
    DocAdjunto actual, {
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
    required String revisadoPor,
  }) {
    final clean = nota.trim();
    if (clean.isEmpty) {
      throw StateError('Debes indicar qué hace falta en el documento.');
    }
    return actual.copyWith(
      estadoCalidad: 'aprobado_con_requerimientos',
      observacionCalidad: clean,
      revisadoPor: revisadoPor,
      fechaRevision: Timestamp.now(),
      requerimientoNota: clean,
      requerimientoRequiereAdjunto: requiereAdjunto,
      requerimientoEstado: 'abierto',
      requerimientoResponsableId: actual.subidoPor ?? '',
      requerimientoFechaLimite: Timestamp.fromDate(fechaLimite),
      requerimientoCreadoAt: Timestamp.now(),
      requerimientoCreadoPor: revisadoPor,
      documentoOriginalUrl: actual.documentoOriginalUrl ?? actual.url,
      documentoOriginalPath: actual.documentoOriginalPath ?? actual.path,
      documentoOriginalNombre: actual.documentoOriginalNombre ?? actual.nombre,
    );
  }

  Future<void> _notificarYTareaRequerimiento({
    required String empresaId,
    required String responsableId,
    required String revisadoPor,
    required String entidadId,
    required String tipo,
    required String productoNombre,
    String productoId = '',
    required String docKey,
    required String docLabel,
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
  }) async {
    final responsable = responsableId.trim();
    if (responsable.isEmpty) return;
    final taskKey = '$tipo:$entidadId';
    await _crearNotificacionGlobalCompras(
      userId: responsable,
      empresaId: empresaId,
      title: 'Documento aprobado con requerimientos',
      description:
          'El documento "$docLabel" de $productoNombre puede utilizarse, pero '
          'Calidad solicitó: ${nota.trim()}',
      type: 'compras_doc_con_requerimientos',
      taskId: taskKey,
      fromId: revisadoPor,
      fromName: 'Revisión de Calidad',
      recepcionId: taskKey,
      productoNombre: productoNombre,
      docKey: docKey,
      docLabel: docLabel,
      motivo: nota.trim(),
    );
    await _tasks.createTaskEs(
      titulo: 'Completar requerimiento: $docLabel',
      descripcion:
          'Calidad aceptó el documento "$docLabel" de $productoNombre con '
          'requerimientos.\nRequerimiento: ${nota.trim()}.\n'
          '${requiereAdjunto ? 'Debes adjuntar el soporte solicitado; el sistema lo consolidará con el PDF original.' : 'Atiende el requerimiento y deja la evidencia correspondiente.'}',
      prioridad: 'alta',
      asignadoUid: responsable,
      creadorUid: revisadoPor.trim().isEmpty ? responsable : revisadoPor.trim(),
      creadorNombre: 'Revisión de Calidad',
      empresaId: empresaId,
      fechaLimite: fechaLimite,
      extra: {
        'origen': 'compras_correccion',
        'module': 'compras_bodega',
        'requiere_adjunto': requiereAdjunto,
        'recepcionId': taskKey,
        'docKey': docKey,
        'docLabel': docLabel,
        'comprasCorreccion': {
          'tipo': tipo,
          'entidadId': entidadId,
          'productoId': productoId,
          'docKey': docKey,
          'estado': 'requerimiento_abierto',
          'esRequerimiento': true,
        },
      },
    );
  }

  /// Flujo unificado cuando Calidad RECHAZA un documento:
  /// 1. Notifica al usuario que lo subió (mensaje "corrígelo y vuelve a cargarlo").
  /// 2. Notifica a TODO el equipo de Calidad de la empresa (copia informativa),
  ///    excluyendo al revisor que hizo el rechazo.
  /// 3. Crea una tarea de corrección con el plazo configurado por la empresa.
  ///
  /// Todas las notificaciones van al centro global (TBL_NOTIFICACIONES) con
  /// module='compras_bodega', por lo que aparecen tanto en la campana de Compras
  /// como en el centro de notificaciones del Home.
  Future<void> _notificarYTareaRechazo({
    required String empresaId,
    required String subidoPor,
    required String revisadoPor,
    required String title,
    required String descripcionSubidor,
    required String type,
    required String taskKey,
    required String recepcionId,
    required String tipoCorreccion,
    required String productoNombre,
    String productoId = '',
    required String docKey,
    required String docLabel,
    required String motivo,
    String? areaId,
  }) async {
    final subidor = subidoPor.trim();
    final diasCorreccion = await obtenerDiasPlazoRechazados(empresaId);

    // 1) Notificación al que subió el documento.
    if (subidor.isNotEmpty) {
      await _crearNotificacionGlobalCompras(
        userId: subidor,
        empresaId: empresaId,
        title: title,
        description: descripcionSubidor,
        type: type,
        taskId: taskKey,
        fromId: revisadoPor,
        fromName: 'Revisión de Calidad',
        recepcionId: recepcionId,
        productoNombre: productoNombre,
        docKey: docKey,
        docLabel: docLabel,
        motivo: motivo,
      );
    }

    // 2) Copia informativa a todo el equipo de Calidad (menos el revisor y el subidor,
    //    que ya fue notificado arriba).
    try {
      final calidad = await getUsuariosPorRol(empresaId, kRolCalidad);
      final ya = {revisadoPor.trim(), subidor};
      for (final r in calidad) {
        final dest = _destinatario(r);
        if (dest.isEmpty || ya.contains(dest)) continue;
        ya.add(dest);
        await _crearNotificacionGlobalCompras(
          userId: dest,
          empresaId: empresaId,
          title: 'Documento rechazado (Calidad)',
          description:
              '"$docLabel" de $productoNombre fue rechazado. Motivo: $motivo.',
          type: type,
          taskId: taskKey,
          fromId: revisadoPor,
          fromName: 'Revisión de Calidad',
          recepcionId: recepcionId,
          productoNombre: productoNombre,
          docKey: docKey,
          docLabel: docLabel,
          motivo: motivo,
        );
      }
    } catch (_) {
      // No bloquear el rechazo si falla el fan-out a Calidad.
    }

    // 3) Tarea de corrección asignada al que subió.
    if (subidor.isNotEmpty) {
      try {
        await _tasks.createTaskEs(
          titulo: 'Corregir documento: $docLabel',
          descripcion:
              'El documento "$docLabel" de $productoNombre fue rechazado por Calidad.\n'
              'Motivo: $motivo.\n'
              'Corrígelo y vuelve a cargarlo antes del vencimiento '
              '($diasCorreccion días).',
          prioridad: 'alta',
          asignadoUid: subidor,
          creadorUid: revisadoPor.trim().isEmpty ? subidor : revisadoPor.trim(),
          creadorNombre: 'Revisión de Calidad',
          empresaId: empresaId,
          areaId: areaId,
          fechaLimite: DateTime.now().add(Duration(days: diasCorreccion)),
          extra: {
            'origen': 'compras_correccion',
            'module': 'compras_bodega',
            'requiere_adjunto': true,
            'recepcionId': recepcionId,
            'docKey': docKey,
            'docLabel': docLabel,
            'comprasCorreccion': {
              'tipo': tipoCorreccion,
              'entidadId': _correccionEntidadId(
                tipoCorreccion: tipoCorreccion,
                recepcionId: recepcionId,
              ),
              'productoId': productoId,
              'docKey': docKey,
              'estado': 'pendiente_correccion',
            },
          },
        );
      } catch (_) {
        // La tarea es complementaria; no bloquear el rechazo si falla.
      }
    }
  }

  /// Marca la tarea de corrección como enviada a Calidad después de que el
  /// documento corregido ya quedó guardado en el módulo de Compras.
  ///
  /// Se valida que la tarea pertenezca al usuario asignado y que siga siendo
  /// una corrección de Compras. Así una carga ajena no puede cerrar ni mover
  /// otra tarea a revisión.
  Future<void> enviarTareaCorreccionARevision({
    required String taskId,
    required String subidoPor,
    required String nombreDocumento,
    String? urlDocumento,
  }) async {
    final ref = _db.collection(TaskService.tasksCol).doc(taskId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('La tarea de corrección ya no existe.');
      }
      final task = snap.data() ?? <String, dynamic>{};
      if ((task['origen'] ?? '').toString() != 'compras_correccion') {
        throw StateError(
          'Esta tarea no corresponde a una corrección de Compras.',
        );
      }
      final asignado = (task['asignado_uid'] ?? '').toString().trim();
      if (asignado.isNotEmpty && asignado != subidoPor.trim()) {
        throw StateError(
          'Solo el responsable asignado puede enviar esta corrección.',
        );
      }

      final estado = (task['estado'] ?? task['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (estado == 'finalizado') return;

      final now = Timestamp.now();
      tx.update(ref, {
        'estado': 'por_aprobar',
        'status': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente_revision_calidad',
        'solicitud_finalizacion_at': now,
        'solicitud_finalizacion_by_uid': subidoPor.trim(),
        'lastEventType': 'compras_documento_corregido',
        'lastEventAt': now,
        'lastEventText': 'Documento corregido enviado a revisión de Calidad',
        'fecha_actualizacion': now,
        'updatedAt': now,
        'comprasCorreccion.estado': 'en_revision_calidad',
        'comprasCorreccion.documentoNombre': nombreDocumento.trim(),
        'comprasCorreccion.documentoUrl': (urlDocumento ?? '').trim(),
        'comprasCorreccion.enviadoRevisionAt': now,
      });
    });
  }

  String _correccionEntidadId({
    required String tipoCorreccion,
    required String recepcionId,
  }) {
    final prefix = '$tipoCorreccion:';
    return recepcionId.startsWith(prefix)
        ? recepcionId.substring(prefix.length).trim()
        : recepcionId.trim();
  }

  /// Al aprobar Calidad el documento corregido, finaliza la tarea vinculada.
  /// La búsqueda se hace por empresa y se filtra en cliente para no exigir un
  /// índice compuesto sobre los campos de trazabilidad anidados.
  Future<void> _finalizarTareasCorreccionAprobadas({
    required String empresaId,
    required String tipo,
    required String entidadId,
    required String docKey,
    required String revisadoPor,
    String productoId = '',
  }) async {
    final empresa = empresaId.trim();
    if (empresa.isEmpty || entidadId.trim().isEmpty) return;

    final tasks = await _db
        .collection(TaskService.tasksCol)
        .where('empresaId', isEqualTo: empresa)
        .get();
    final matching = tasks.docs.where((doc) {
      final data = doc.data();
      if ((data['origen'] ?? '').toString() != 'compras_correccion') {
        return false;
      }
      final correction = Map<String, dynamic>.from(
        (data['comprasCorreccion'] as Map?) ?? const <String, dynamic>{},
      );
      final currentStatus = (data['estado'] ?? data['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (currentStatus == 'finalizado') return false;
      if ((correction['tipo'] ?? '').toString() != tipo ||
          (correction['entidadId'] ?? '').toString() != entidadId ||
          (correction['docKey'] ?? '').toString() != docKey) {
        return false;
      }
      if (tipo == 'recepcion' &&
          productoId.trim().isNotEmpty &&
          (correction['productoId'] ?? '').toString() != productoId) {
        return false;
      }
      final correctionStatus = (correction['estado'] ?? '').toString();
      return correctionStatus == 'en_revision_calidad' ||
          (correction['esRequerimiento'] == true &&
              correctionStatus == 'requerimiento_abierto');
    }).toList();

    if (matching.isEmpty) return;
    final now = Timestamp.now();
    final batch = _db.batch();
    for (final task in matching) {
      batch.update(task.reference, {
        'estado': 'finalizado',
        'status': 'finalizado',
        'fecha_completada': now,
        'fecha_actualizacion': now,
        'updatedAt': now,
        'solicitud_finalizacion_estado': 'aprobada_calidad',
        'lastEventType': 'compras_correccion_aprobada',
        'lastEventAt': now,
        'lastEventText': 'Documento corregido aprobado por Calidad',
        'comprasCorreccion.estado': 'aprobada_calidad',
        'comprasCorreccion.aprobadoPor': revisadoPor.trim(),
        'comprasCorreccion.aprobadoAt': now,
      });
    }
    await batch.commit();
  }

  // ─── REQ_DOCUMENTOS ─────────────────────────────────────────────────────────

  /// Carga (one-time) el motor de requisitos documentales para la empresa.
  Future<ReqEngine> cargarReqEngine(String empresaId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_REQ_DOCUMENTOS')
        .where('empresaId', isEqualTo: empresaId)
        .where('activo', isEqualTo: true)
        .get();
    final docs = snap.docs
        .map((d) => ReqDocumentoDoc.fromMap(d.id, d.data()))
        .toList();
    return ReqEngine(docs);
  }

  /// Stream de requisitos documentales activos para la empresa.
  /// Sin orderBy: todo el ordenamiento se hace en cliente.
  Stream<List<ReqDocumentoDoc>> streamReqDocumentos(String empresaId) => _db
      .collection('TBL_COMPRAS_REQ_DOCUMENTOS')
      .where('empresaId', isEqualTo: empresaId)
      .where('activo', isEqualTo: true)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => ReqDocumentoDoc.fromMap(d.id, d.data())).toList(),
      );

  /// Reemplaza todos los requisitos documentales de la empresa con [docs].
  /// Elimina los existentes (batch) y sube los nuevos (batch de 499).
  Future<void> importarReqDocumentos(
    String empresaId,
    List<ReqDocumentoDoc> docs,
  ) async {
    const batchSize = 499;
    final col = _db.collection('TBL_COMPRAS_REQ_DOCUMENTOS');

    // Eliminar existentes
    final existentes = await col.where('empresaId', isEqualTo: empresaId).get();

    for (int i = 0; i < existentes.docs.length; i += batchSize) {
      final batch = _db.batch();
      for (final d in existentes.docs.skip(i).take(batchSize)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // Insertar nuevos
    for (int i = 0; i < docs.length; i += batchSize) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(batchSize)) {
        batch.set(col.doc(), doc.toMap());
      }
      await batch.commit();
    }
  }

  // ─── FICHAS TÉCNICAS (Proveedor + Producto + Marca) ─────────────────────────

  /// Todas las fichas técnicas de la empresa (para pantalla de Calidad y Producto).
  Stream<List<FichaTecnicaDoc>> streamFichasTecnicas(String empresaId) => _db
      .collection('TBL_COMPRAS_FICHAS_TECNICAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .map((d) => FichaTecnicaDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.productoNombre.compareTo(b.productoNombre));
        return list;
      });

  /// Fichas con documentoActual pendiente de revisión de calidad.
  Stream<List<FichaTecnicaDoc>> streamFichasTecnicasPendientes(
    String empresaId,
  ) => _db
      .collection('TBL_COMPRAS_FICHAS_TECNICAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        return s.docs.map((d) => FichaTecnicaDoc.fromMap(d.id, d.data())).where(
            (f) {
              final doc = f.documentoActual;
              if (doc == null || !doc.tieneDoc) return false;
              return doc.estadoCalidad.isEmpty ||
                  doc.estadoCalidad == 'pendiente' ||
                  doc.estadoCalidad == 'pendiente_revision_calidad' ||
                  doc.estadoCalidad == 'aprobado_con_requerimientos';
            },
          ).toList()
          ..sort((a, b) => a.productoNombre.compareTo(b.productoNombre));
      });

  /// Carga (one-time) todas las fichas técnicas para lookup en recepción.
  Future<List<FichaTecnicaDoc>> getFichasTecnicas(String empresaId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) => FichaTecnicaDoc.fromMap(d.id, d.data()))
        .toList();
  }

  Future<List<FichaTecnicaDoc>> getFichasTecnicasPorMarca(
    String empresaId,
    String marcaId,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .where('empresaId', isEqualTo: empresaId)
        .where('marcaId', isEqualTo: marcaId)
        .get();
    return snap.docs
        .map((d) => FichaTecnicaDoc.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.productoNombre.compareTo(b.productoNombre));
  }

  Future<List<ProductoDoc>> getProductosPorMarca(
    String empresaId,
    String marcaId,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_PRODUCTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) => ProductoDoc.fromMap(d.id, d.data()))
        .where((p) => p.marcas.any((r) => r.marcaId == marcaId))
        .toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  Future<List<RecepcionDoc>> getRecepcionesPorMarca(
    String empresaId,
    String marcaId,
  ) async {
    final snap = await _db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
        .where((r) => r.productos.any((p) => p.marcaId == marcaId))
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  /// Crea o actualiza una ficha técnica.
  /// Al actualizar (isNew=false), mueve documentoActual al historial y marca el
  /// nuevo documento como 'pendiente_revision_calidad'.
  /// [observacion] es obligatorio cuando isNew=false.
  Future<String> guardarFichaTecnica(
    FichaTecnicaDoc ficha, {
    required bool isNew,
    String observacion = '',
    String actualizadoPor = '',
  }) async {
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc()
        : _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(ficha.id);
    FichaTecnicaDoc fichaFinal = ficha;

    if (!isNew && ficha.documentoActual != null) {
      // La versión anterior debe leerse de Firestore: [ficha.documentoActual]
      // ya contiene el archivo nuevo que llega desde el formulario.
      final stored = await ref.get();
      if (stored.exists) {
        final anterior = FichaTecnicaDoc.fromMap(stored.id, stored.data()!);
        final historial = [...anterior.historial];
        final documentoAnterior = anterior.documentoActual;
        if (documentoAnterior != null && documentoAnterior.tieneDoc) {
          historial.add(
            FichaTecnicaHistorial(
              url: documentoAnterior.url ?? '',
              nombre: documentoAnterior.nombre ?? '',
              path: documentoAnterior.path,
              observacion: observacion,
              actualizadoPor: actualizadoPor,
              fecha: Timestamp.now(),
              estadoCalidadFinal: documentoAnterior.estadoCalidad,
            ),
          );
        }
        fichaFinal = ficha.copyWith(
          historial: historial,
          documentoAprobado: anterior.documentoAprobado,
          createdAt: anterior.createdAt,
        );
      }
    }

    // Marcar el nuevo documentoActual como pendiente de calidad
    if (fichaFinal.documentoActual != null) {
      fichaFinal = fichaFinal.copyWith(
        documentoActual: prepararDocumentoPendienteCalidad(
          fichaFinal.documentoActual!,
          subidoPor: fichaFinal.documentoActual!.subidoPor,
          fechaVencimiento: fichaFinal.documentoActual!.fechaVencimiento,
          observacionActualizacion: observacion.isEmpty ? null : observacion,
        ),
      );
    }

    await ref.set(fichaFinal.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  /// Elimina completamente una ficha técnica:
  /// borra archivo(s) en Storage (doc actual + historial) y el doc en Firestore.
  Future<void> eliminarFichaTecnica(FichaTecnicaDoc ficha) async {
    // 1. Borrar archivo del documentoActual
    final doc = ficha.documentoActual;
    if (doc != null && doc.path != null && doc.path!.isNotEmpty) {
      try {
        await _storage.ref(doc.path!).delete();
      } catch (_) {}
    }
    // 2. Borrar archivos del historial
    for (final h in ficha.historial) {
      if (h.path != null && h.path!.isNotEmpty) {
        try {
          await _storage.ref(h.path!).delete();
        } catch (_) {}
      }
    }
    // 3. Eliminar documento de Firestore
    await _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(ficha.id).delete();
  }

  /// Aprueba la ficha técnica (documentoActual.estadoCalidad = 'aprobado').
  Future<void> aprobarFichaTecnica({
    required String fichaId,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(fichaId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
    if (ficha.documentoActual == null) return;

    final documentoAprobado = ficha.documentoActual!.copyWith(
      estadoCalidad: 'aprobado',
      revisadoPor: revisadoPor,
      fechaRevision: Timestamp.now(),
      requerimientoEstado: ficha.documentoActual!.aprobadoConRequerimientos
          ? 'resuelto'
          : ficha.documentoActual!.requerimientoEstado,
      requerimientoResueltoAt: ficha.documentoActual!.aprobadoConRequerimientos
          ? Timestamp.now()
          : ficha.documentoActual!.requerimientoResueltoAt,
      requerimientoResueltoPor: ficha.documentoActual!.aprobadoConRequerimientos
          ? revisadoPor
          : ficha.documentoActual!.requerimientoResueltoPor,
    );

    await ref.update({
      'documentoActual': documentoAprobado.toMap(),
      'documentoAprobado': documentoAprobado.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _finalizarTareasCorreccionAprobadas(
      empresaId: ficha.empresaId,
      tipo: 'ficha',
      entidadId: fichaId,
      docKey: 'fichaTecnica',
      revisadoPor: revisadoPor,
    );
  }

  Future<void> aprobarConRequerimientosFichaTecnica({
    required String fichaId,
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(fichaId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
    final actual = ficha.documentoActual;
    if (actual == null || !actual.tieneDoc) return;
    final actualizado = _conRequerimiento(
      actual,
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
      revisadoPor: revisadoPor,
    );
    await ref.update({
      'documentoActual': actualizado.toMap(),
      // Es utilizable, por eso también es la última versión aceptada.
      'documentoAprobado': actualizado.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _notificarYTareaRequerimiento(
      empresaId: ficha.empresaId,
      responsableId: actual.subidoPor ?? ficha.creadoPor,
      revisadoPor: revisadoPor,
      entidadId: fichaId,
      tipo: 'ficha',
      productoNombre: ficha.productoNombre,
      docKey: 'fichaTecnica',
      docLabel: ficha.marcaNombre.isEmpty
          ? 'Ficha técnica – ${ficha.productoNombre}'
          : 'Ficha técnica – ${ficha.productoNombre} / ${ficha.marcaNombre}',
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
    );
  }

  // ─── DOCUMENTOS DE PROVEEDOR (revisión calidad) ──────────────────────────────

  /// Guarda/actualiza un único documento del proveedor en Firestore
  /// usando la sintaxis de campo anidado (documentos.<key>) para no pisar
  /// el resto del map.
  Future<void> actualizarDocProveedor({
    required String proveedorId,
    required String docKey,
    required DocAdjunto doc,
  }) => _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId).update({
    'documentos.$docKey': doc.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Aprueba un documento del proveedor (estadoCalidad = 'aprobado').
  Future<void> aprobarDocProveedor({
    required String proveedorId,
    required String docKey,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final prov = ProveedorDoc.fromMap(snap.id, snap.data()!);
    final docActual = prov.documentos[docKey];
    if (docActual == null || !docActual.tieneDoc) return;
    final actualizado = Map<String, DocAdjunto>.from(prov.documentos)
      ..[docKey] = docActual.copyWith(
        estadoCalidad: 'aprobado',
        revisadoPor: revisadoPor,
        fechaRevision: Timestamp.now(),
        requerimientoEstado: docActual.aprobadoConRequerimientos
            ? 'resuelto'
            : docActual.requerimientoEstado,
        requerimientoResueltoAt: docActual.aprobadoConRequerimientos
            ? Timestamp.now()
            : docActual.requerimientoResueltoAt,
        requerimientoResueltoPor: docActual.aprobadoConRequerimientos
            ? revisadoPor
            : docActual.requerimientoResueltoPor,
      );
    await ref.update({
      'documentos': actualizado.map((k, v) => MapEntry(k, v.toMap())),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _finalizarTareasCorreccionAprobadas(
      empresaId: prov.empresaId,
      tipo: 'proveedor',
      entidadId: proveedorId,
      docKey: docKey,
      revisadoPor: revisadoPor,
    );
  }

  Future<void> aprobarConRequerimientosDocProveedor({
    required String proveedorId,
    required String docKey,
    required String nota,
    required bool requiereAdjunto,
    required DateTime fechaLimite,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final proveedor = ProveedorDoc.fromMap(snap.id, snap.data()!);
    final actual = proveedor.documentos[docKey];
    if (actual == null || !actual.tieneDoc) return;
    final actualizado = _conRequerimiento(
      actual,
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
      revisadoPor: revisadoPor,
    );
    await actualizarDocProveedor(
      proveedorId: proveedorId,
      docKey: docKey,
      doc: actualizado,
    );
    await _notificarYTareaRequerimiento(
      empresaId: proveedor.empresaId,
      responsableId: actual.subidoPor ?? '',
      revisadoPor: revisadoPor,
      entidadId: proveedorId,
      tipo: 'proveedor',
      productoNombre: proveedor.razonSocial,
      docKey: docKey,
      docLabel: kDocProveedorLabels[docKey] ?? docKey,
      nota: nota,
      requiereAdjunto: requiereAdjunto,
      fechaLimite: fechaLimite,
    );
  }

  /// Rechaza un documento del proveedor, lo deja visible en Calidad y
  /// notifica al usuario que debe reemplazarlo.
  Future<void> rechazarDocProveedor({
    required String proveedorId,
    required String docKey,
    required String motivo,
    required String revisadoPor,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final prov = ProveedorDoc.fromMap(snap.id, snap.data()!);
    final docActual = prov.documentos[docKey];
    if (docActual == null || !docActual.tieneDoc) return;

    // Lo conservamos como rechazado para que Calidad lo muestre en su
    // pestaña dedicada y el proveedor pueda entender qué debe reemplazar.
    final actualizado = Map<String, DocAdjunto>.from(prov.documentos)
      ..[docKey] = docActual.copyWith(
        estadoCalidad: 'rechazado',
        observacionCalidad: motivo,
        revisadoPor: revisadoPor,
        fechaRevision: Timestamp.now(),
      );
    await ref.update({
      'documentos': actualizado.map((k, v) => MapEntry(k, v.toMap())),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notificar (subidor + todo Calidad) y crear la tarea de corrección.
    final subidoPor = docActual.subidoPor ?? '';
    final label = kDocProveedorLabels[docKey] ?? docKey;
    await _notificarYTareaRechazo(
      empresaId: prov.empresaId,
      subidoPor: subidoPor,
      revisadoPor: revisadoPor,
      title: 'Documento rechazado - ${prov.razonSocial}',
      descripcionSubidor:
          'El documento "$label" fue rechazado. Motivo: $motivo. Por favor corrígelo y vuelve a cargarlo.',
      type: 'doc_rechazado',
      taskKey: 'proveedor:$proveedorId',
      recepcionId: 'proveedor:$proveedorId',
      tipoCorreccion: 'proveedor',
      productoNombre: prov.razonSocial,
      docKey: docKey,
      docLabel: label,
      motivo: motivo,
    );
  }

  /// Revierte la aprobación de un documento del proveedor.
  ///
  /// Mismo criterio que [revertirAprobacionDocRecepcion]: acción excepcional del
  /// Admin Documental, con motivo obligatorio y trazabilidad en el documento.
  Future<void> revertirAprobacionDocProveedor({
    required String proveedorId,
    required String docKey,
    required String motivo,
    required String revertidoPor,
    bool rechazar = false,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      throw StateError('Debes indicar el motivo de la reversión.');
    }
    final ref = _db.collection('TBL_COMPRAS_PROVEEDORES').doc(proveedorId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('El proveedor ya no existe.');
    }
    final prov = ProveedorDoc.fromMap(snap.id, snap.data()!);
    final docActual = prov.documentos[docKey];
    if (docActual == null || !docActual.tieneDoc) {
      throw StateError('El documento ya no existe en el proveedor.');
    }
    if (!docActual.aprobado) {
      throw StateError(
        'Solo se puede revertir un documento aprobado. '
        'Estado actual: ${docActual.estadoCalidad}',
      );
    }

    final actualizado = Map<String, DocAdjunto>.from(prov.documentos)
      ..[docKey] = docActual.copyWith(
        estadoCalidad: rechazar ? 'rechazado' : 'pendiente_revision_calidad',
        observacionCalidad: rechazar ? motivoLimpio : null,
        revertidoPor: revertidoPor,
        fechaReversion: Timestamp.now(),
        motivoReversion: motivoLimpio,
        estadoAnteriorReversion: docActual.estadoCalidad,
      );
    await ref.update({
      'documentos': actualizado.map((k, v) => MapEntry(k, v.toMap())),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!rechazar) return;

    final subidoPor = docActual.subidoPor ?? '';
    final label = kDocProveedorLabels[docKey] ?? docKey;
    await _notificarYTareaRechazo(
      empresaId: prov.empresaId,
      subidoPor: subidoPor,
      revisadoPor: revertidoPor,
      title: 'Aprobación revertida - ${prov.razonSocial}',
      descripcionSubidor:
          'La aprobación del documento "$label" fue revertida y el documento '
          'quedó rechazado. Motivo: $motivoLimpio. '
          'Por favor corrígelo y vuelve a cargarlo.',
      type: 'doc_rechazado',
      taskKey: 'proveedor:$proveedorId',
      recepcionId: 'proveedor:$proveedorId',
      tipoCorreccion: 'proveedor',
      productoNombre: prov.razonSocial,
      docKey: docKey,
      docLabel: label,
      motivo: motivoLimpio,
    );
  }

  /// Revierte la aprobación de una ficha técnica y conserva la trazabilidad.
  Future<void> revertirAprobacionFichaTecnica({
    required String fichaId,
    required String motivo,
    required String revertidoPor,
    bool rechazar = false,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      throw StateError('Debes indicar el motivo de la reversión.');
    }
    final ref = _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(fichaId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('La ficha técnica ya no existe.');
    }
    final ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
    final actual = ficha.documentoActual;
    if (actual == null || !actual.tieneDoc) {
      throw StateError('La ficha técnica ya no tiene un documento vigente.');
    }
    if (!actual.aprobado) {
      throw StateError(
        'Solo se puede revertir una ficha aprobada. '
        'Estado actual: ${actual.estadoCalidad}',
      );
    }

    final revertido = actual.copyWith(
      estadoCalidad: rechazar ? 'rechazado' : 'pendiente_revision_calidad',
      observacionCalidad: rechazar ? motivoLimpio : null,
      revertidoPor: revertidoPor,
      fechaReversion: Timestamp.now(),
      motivoReversion: motivoLimpio,
      estadoAnteriorReversion: actual.estadoCalidad,
    );
    await ref.update({
      'documentoActual': revertido.toMap(),
      // Una aprobación revertida no puede seguir disponible para nuevas
      // recepciones a través de documentoAprobado.
      'documentoAprobado': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!rechazar) return;
    final subidoPor = (actual.subidoPor?.trim().isNotEmpty ?? false)
        ? actual.subidoPor!.trim()
        : ficha.creadoPor.trim();
    final label = ficha.marcaNombre.isEmpty
        ? 'Ficha Técnica – ${ficha.productoNombre} (${ficha.proveedorNombre})'
        : 'Ficha Técnica – ${ficha.productoNombre} / ${ficha.marcaNombre} '
              '(${ficha.proveedorNombre})';
    await _notificarYTareaRechazo(
      empresaId: ficha.empresaId,
      subidoPor: subidoPor,
      revisadoPor: revertidoPor,
      title: 'Aprobación de ficha técnica revertida',
      descripcionSubidor:
          'La aprobación de "$label" fue revertida y la ficha quedó '
          'rechazada. Motivo: $motivoLimpio. Corrígela y vuelve a cargarla.',
      type: 'ficha_rechazada',
      taskKey: 'ficha:$fichaId',
      recepcionId: 'ficha:$fichaId',
      tipoCorreccion: 'ficha',
      productoNombre: ficha.productoNombre,
      docKey: 'fichaTecnica',
      docLabel: label,
      motivo: motivoLimpio,
    );
  }

  /// Rechaza la ficha técnica y envía notificación al subidor.
  Future<void> rechazarFichaTecnica({
    required String fichaId,
    required String motivo,
    required String revisadoPor,
    required String creadoPor,
    required String empresaId,
    required String productoNombre,
    required String marcaNombre,
    required String proveedorNombre,
  }) async {
    final ref = _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(fichaId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
    if (ficha.documentoActual == null) return;

    await ref.update({
      'documentoActual': ficha.documentoActual!
          .copyWith(
            estadoCalidad: 'rechazado',
            observacionCalidad: motivo,
            revisadoPor: revisadoPor,
            fechaRevision: Timestamp.now(),
          )
          .toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notificar (subidor + todo Calidad) y crear la tarea de corrección.
    // Preferimos subidoPor del documento; si no consta, el creadoPor recibido.
    final subidoPor =
        (ficha.documentoActual!.subidoPor?.trim().isNotEmpty ?? false)
        ? ficha.documentoActual!.subidoPor!.trim()
        : creadoPor;
    final label = marcaNombre.isEmpty
        ? 'Ficha Técnica – $productoNombre ($proveedorNombre)'
        : 'Ficha Técnica – $productoNombre / $marcaNombre ($proveedorNombre)';
    await _notificarYTareaRechazo(
      empresaId: empresaId,
      subidoPor: subidoPor,
      revisadoPor: revisadoPor,
      title: 'Ficha técnica rechazada',
      descripcionSubidor:
          'El documento "$label" fue rechazado. Motivo: $motivo. Por favor corrígelo y vuelve a cargarlo.',
      type: 'ficha_rechazada',
      taskKey: 'ficha:$fichaId',
      recepcionId: 'ficha:$fichaId',
      tipoCorreccion: 'ficha',
      productoNombre: productoNombre,
      docKey: 'fichaTecnica',
      docLabel: label,
      motivo: motivo,
    );
  }
}
