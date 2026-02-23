// lib/compras/compras_service.dart
// NOTA: Todas las queries usan solo .where('empresaId') sin orderBy para evitar
// la necesidad de índices compuestos en Firestore. El ordenamiento se hace cliente.

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'compras_models.dart';

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
}
