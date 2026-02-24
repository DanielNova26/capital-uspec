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

  Future<String> guardarRecepcion(RecepcionDoc r) async {
    final ref = r.id.isEmpty
        ? _db.collection('TBL_COMPRAS_RECEPCIONES').doc()
        : _db.collection('TBL_COMPRAS_RECEPCIONES').doc(r.id);
    await ref.set(r.toMap(), SetOptions(merge: true));
    return ref.id;
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
    );
  }

  Future<void> eliminarArchivo(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (_) {}
  }

  // ─── REQ_DOCUMENTOS ─────────────────────────────────────────────────────────

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
}
