// lib/compras/compras_service.dart
// ignore_for_file: unused_import
// NOTA: Todas las queries usan solo .where('empresaId') sin orderBy para evitar
// la necesidad de índices compuestos en Firestore. El ordenamiento se hace cliente.

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'compras_models.dart';
import 'compras_req_engine.dart';

class ComprasService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  ComprasService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ─── PRODUCTOS ──────────────────────────────────────────────────────────────

  Stream<List<ProductoDoc>> streamProductos(String empresaId) => _db
      .collection('TBL_COMPRAS_PRODUCTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map((d) => ProductoDoc.fromMap(d.id, d.data())).toList();
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

  Future<void> eliminarProducto(String id) =>
      _db.collection('TBL_COMPRAS_PRODUCTOS').doc(id).delete();

  // ─── PROVEEDORES ────────────────────────────────────────────────────────────

  Stream<List<ProveedorDoc>> streamProveedores(String empresaId) => _db
      .collection('TBL_COMPRAS_PROVEEDORES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map((d) => ProveedorDoc.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
        return list;
      });

  Future<String> guardarProveedor(ProveedorDoc p, {required bool isNew}) async {
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_PROVEEDORES').doc()
        : _db.collection('TBL_COMPRAS_PROVEEDORES').doc(p.id);
    await ref.set(p.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> eliminarProveedor(String id) =>
      _db.collection('TBL_COMPRAS_PROVEEDORES').doc(id).delete();

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
      for (final d in snap.docs) (d.data()['nit'] as String? ?? ''): d.id
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
        final list =
            s.docs.map((d) => RecepcionDoc.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      });

  Stream<List<RecepcionDoc>> streamRecepcionesByProveedor(
    String empresaId,
    String proveedorId,
  ) =>
      _db
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
  ) =>
      _db
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

  /// Stream de recepciones con al menos un documento por revisar en calidad.
  /// Incluye documentos con estado 'pendiente' y documentos históricos con
  /// archivo adjunto pero sin estadoCalidad explícito.
  Stream<List<RecepcionDoc>> streamPendientesRevision(String empresaId) =>
      _db
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .map((s) {
            final list = s.docs
                .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
                .where(
                  (r) => r.productos.any(
                    (p) => p.documentos.values.any(
                        (d) =>
                    d.tieneDoc &&
                        (d.estadoCalidad.isEmpty ||
                            d.estadoCalidad == 'pendiente' ||
                            d.estadoCalidad ==
                                'pendiente_revision_calidad')
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

  /// Aprueba un documento específico en una recepción.
  /// Actualiza el estadoCalidad del doc a 'aprobado'.
  Future<void> aprobarDocRecepcion({
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String revisadoPor,
  }) async {
    if (productoIdx < 0 || productoIdx >= recepcion.productos.length) return;
    final productos = List<RecepcionProducto>.from(recepcion.productos);
    final rp = productos[productoIdx];
    final docActual = rp.documentos[docKey];
    if (docActual == null) return;

    final docActualizado = docActual.copyWith(
      estadoCalidad: 'aprobado',
      revisadoPor: revisadoPor,
      fechaRevision: Timestamp.now(),
    );
    final docsActualizados = Map<String, DocAdjunto>.from(rp.documentos)
      ..[docKey] = docActualizado;
    productos[productoIdx] = rp.copyWith(documentos: docsActualizados);

    await _db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .doc(recepcion.id)
        .update({'productos': productos.map((p) => p.toMap()).toList()});
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

    await _db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .doc(recepcion.id)
        .update({'productos': productos.map((p) => p.toMap()).toList()});

    // Crear notificación al usuario que creó la recepción
    if (recepcion.creadoPor.isNotEmpty) {
      final notif = NotificacionComprasDoc(
        empresaId: recepcion.empresaId,
        userId: recepcion.creadoPor,
        recepcionId: recepcion.id,
        productoNombre: rp.nombre,
        docKey: docKey,
        docLabel: kDocRecepcionLabels[docKey] ?? docKey,
        motivo: motivo,
        createdAt: Timestamp.now(),
      );
      await _db.collection('TBL_COMPRAS_NOTIFICACIONES').add(notif.toMap());
    }
  }

  // ─── MARCAS ─────────────────────────────────────────────────────────────────

  Stream<List<MarcaDoc>> streamMarcas(String empresaId) => _db
      .collection('TBL_COMPRAS_MARCAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list =
            s.docs.map((d) => MarcaDoc.fromMap(d.id, d.data())).toList();
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
    final ref = isNew
        ? _db.collection('TBL_COMPRAS_MARCAS').doc()
        : _db.collection('TBL_COMPRAS_MARCAS').doc(m.id);
    await ref.set(m.toMap(), SetOptions(merge: true));
    return ref.id;
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

  Future<void> eliminarArchivo(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (_) {}
  }

  // ─── ROLES COMPRAS ───────────────────────────────────────────────────────────

  Stream<List<ComprasRolDoc>> streamComprasRoles(String empresaId) => _db
      .collection('TBL_COMPRAS_ROLES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => ComprasRolDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre)));

  Future<ComprasRolDoc?> getRolUsuario(
      String empresaId, String userId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .get();
    if (snap.docs.isEmpty) return null;
    return ComprasRolDoc.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  Future<void> guardarComprasRol(ComprasRolDoc r, {required bool isNew}) async {
    if (isNew) {
      // Verificar si ya existe un rol para este usuario
      final existing = await _db
          .collection('TBL_COMPRAS_ROLES')
          .where('empresaId', isEqualTo: r.empresaId)
          .where('userId', isEqualTo: r.userId)
          .get();
      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.set(r.toMap(), SetOptions(merge: true));
        return;
      }
      await _db.collection('TBL_COMPRAS_ROLES').add(r.toMap());
    } else {
      await _db.collection('TBL_COMPRAS_ROLES').doc(r.id).set(
          r.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> eliminarComprasRol(String id) =>
      _db.collection('TBL_COMPRAS_ROLES').doc(id).delete();

  // ─── NOTIFICACIONES ──────────────────────────────────────────────────────────

  Stream<List<NotificacionComprasDoc>> streamNotificaciones(
      String empresaId, String userId) =>
      _db
          .collection('TBL_COMPRAS_NOTIFICACIONES')
          .where('empresaId', isEqualTo: empresaId)
          .where('userId', isEqualTo: userId)
          .where('leida', isEqualTo: false)
          .snapshots()
          .map((s) => s.docs
              .map((d) => NotificacionComprasDoc.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Future<void> marcarNotificacionLeida(String id) => _db
      .collection('TBL_COMPRAS_NOTIFICACIONES')
      .doc(id)
      .update({'leida': true});

  Future<void> marcarTodasLeidas(String empresaId, String userId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_NOTIFICACIONES')
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .where('leida', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'leida': true});
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
      .map((s) => s.docs
          .map((d) => ReqDocumentoDoc.fromMap(d.id, d.data()))
          .toList());

  /// Reemplaza todos los requisitos documentales de la empresa con [docs].
  /// Elimina los existentes (batch) y sube los nuevos (batch de 499).
  Future<void> importarReqDocumentos(
    String empresaId,
    List<ReqDocumentoDoc> docs,
  ) async {
    const batchSize = 499;
    final col = _db.collection('TBL_COMPRAS_REQ_DOCUMENTOS');

    // Eliminar existentes
    final existentes = await col
        .where('empresaId', isEqualTo: empresaId)
        .get();

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
      String empresaId) =>
      _db
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .map((s) {
            return s.docs
                .map((d) => FichaTecnicaDoc.fromMap(d.id, d.data()))
                .where((f) {
              final doc = f.documentoActual;
              if (doc == null || !doc.tieneDoc) return false;
              return doc.estadoCalidad.isEmpty ||
                  doc.estadoCalidad == 'pendiente' ||
                  doc.estadoCalidad == 'pendiente_revision_calidad';
            }).toList()
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
    FichaTecnicaDoc fichaFinal = ficha;

    if (!isNew && ficha.documentoActual != null) {
      // Archivar versión anterior en historial
      final anterior = ficha.documentoActual!;
      final entrada = FichaTecnicaHistorial(
        url: anterior.url ?? '',
        nombre: anterior.nombre ?? '',
        path: anterior.path,
        observacion: observacion,
        actualizadoPor: actualizadoPor,
        fecha: Timestamp.now(),
        estadoCalidadFinal: anterior.estadoCalidad,
      );
      fichaFinal = ficha.copyWith(
        historial: [...ficha.historial, entrada],
      );
    }

    // Marcar el nuevo documentoActual como pendiente de calidad
    if (fichaFinal.documentoActual != null) {
      fichaFinal = fichaFinal.copyWith(
        documentoActual: fichaFinal.documentoActual!.copyWith(
          estadoCalidad: 'pendiente_revision_calidad',
          observacionActualizacion: observacion.isEmpty ? null : observacion,
        ),
      );
    }

    final ref = isNew
        ? _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc()
        : _db.collection('TBL_COMPRAS_FICHAS_TECNICAS').doc(ficha.id);
    await ref.set(fichaFinal.toMap(), SetOptions(merge: true));
    return ref.id;
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

    await ref.update({
      'documentoActual': ficha.documentoActual!
          .copyWith(
            estadoCalidad: 'aprobado',
            revisadoPor: revisadoPor,
            fechaRevision: Timestamp.now(),
          )
          .toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── DOCUMENTOS DE PROVEEDOR (revisión calidad) ──────────────────────────────

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
      );
    await ref.update({
      'documentos': actualizado.map((k, v) => MapEntry(k, v.toMap())),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rechaza un documento del proveedor (estadoCalidad = 'rechazado').
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

    // Notificar al usuario que subió la ficha
    if (creadoPor.isNotEmpty) {
      final label = marcaNombre.isEmpty
          ? 'Ficha Técnica – $productoNombre ($proveedorNombre)'
          : 'Ficha Técnica – $productoNombre / $marcaNombre ($proveedorNombre)';
      final notif = NotificacionComprasDoc(
        empresaId: empresaId,
        userId: creadoPor,
        recepcionId: 'ficha:$fichaId',
        productoNombre: productoNombre,
        docKey: 'fichaTecnica',
        docLabel: label,
        motivo: motivo,
        createdAt: Timestamp.now(),
      );
      await _db.collection('TBL_COMPRAS_NOTIFICACIONES').add(notif.toMap());
    }
  }
}
