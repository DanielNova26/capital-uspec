// lib/core/user_directory.dart
//
// Directorio de usuarios con caché en memoria para resolución visual
// (nombre completo, foto y cargo) a partir de la cédula / docId.
//
// Orden de lookup (mismo criterio que app_drawer):
//   1. TBL_USUARIOS por docId (la cédula es el doc ID)
//   2. TBL_USUARIOS por campo 'cedula'
//   3. TBL_ESTRUCTURA_ORGANIZACIONAL por docId (fallback de nombre/foto/cargo)
//
// La caché vive durante la sesión: cada usuario se lee de Firestore una sola
// vez sin importar cuántos widgets lo muestren. No tiene lógica visual.
// Para la parte visual ver lib/widgets/user_avatar.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Datos mínimos de presentación de un usuario.
class UserDisplayInfo {
  final String id;
  final String nombre;
  final String fotoUrl;
  final String cargo;

  const UserDisplayInfo({
    required this.id,
    this.nombre = '',
    this.fotoUrl = '',
    this.cargo = '',
  });

  static const empty = UserDisplayInfo(id: '');

  bool get hasFoto => fotoUrl.isNotEmpty;

  /// true si se resolvió un nombre real (no vacío y distinto de la cédula).
  bool get hasNombre => nombre.isNotEmpty && nombre != id;

  /// Nombre a mostrar: nombre real, o la cédula como último recurso.
  String get displayName => hasNombre ? nombre : id;

  /// Iniciales (máx. 2 letras) para avatar sin foto. Vacío si el nombre
  /// no es resoluble (p. ej. solo cédula numérica).
  String get iniciales {
    if (!hasNombre) return '';
    final words = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (w) => w.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(w[0]),
        )
        .take(2);
    return words.map((w) => w[0].toUpperCase()).join();
  }
}

/// Caché global de usuarios para mostrar nombre + foto en toda la app.
class UserDirectory {
  UserDirectory._();
  static final UserDirectory instance = UserDirectory._();

  static const String _usuarios = 'TBL_USUARIOS';
  static const String _estructura = 'TBL_ESTRUCTURA_ORGANIZACIONAL';

  final Map<String, UserDisplayInfo> _cache = {};
  final Map<String, Future<UserDisplayInfo>> _inflight = {};

  /// Acceso síncrono si el usuario ya está en caché (evita parpadeo).
  UserDisplayInfo? peek(String id) => _cache[id.trim()];

  /// Invalida un usuario (p. ej. tras actualizar su foto de perfil).
  void invalidate(String id) => _cache.remove(id.trim());

  /// Invalida todo el directorio después de una migración administrativa.
  void clear() {
    _cache.clear();
    _inflight.clear();
  }

  /// Resuelve nombre/foto/cargo de un usuario. Nunca lanza: ante error
  /// retorna un info con solo la cédula (sin cachear, para reintentar luego).
  Future<UserDisplayInfo> resolve(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return Future.value(UserDisplayInfo.empty);
    final hit = _cache[id];
    if (hit != null) return Future.value(hit);
    return _inflight.putIfAbsent(
      id,
      () => _load(id).whenComplete(() => _inflight.remove(id)),
    );
  }

  /// Pre-carga en lote (chunks de 10 por límite de whereIn) para listas.
  Future<void> warm(Iterable<String> rawIds) async {
    final ids = rawIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_cache.containsKey(e))
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
        final q = await db
            .collection(_usuarios)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in q.docs) {
          _cache[d.id] = _fromUsuario(d.id, d.data());
        }
      }
    } catch (e) {
      debugPrint('[UserDirectory] warm falló: $e');
    }
  }

  Future<UserDisplayInfo> _load(String id) async {
    try {
      final db = FirebaseFirestore.instance;
      Map<String, dynamic>? data;

      final doc = await db.collection(_usuarios).doc(id).get();
      if (doc.exists) data = doc.data();

      if (data == null) {
        final q = await db
            .collection(_usuarios)
            .where('cedula', isEqualTo: id)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) data = q.docs.first.data();
      }

      var info = data != null
          ? _fromUsuario(id, data)
          : UserDisplayInfo(id: id);

      // Fallback a estructura organizacional si falta nombre o foto.
      if (!info.hasNombre || !info.hasFoto) {
        final e = await db.collection(_estructura).doc(id).get();
        final ed = e.data();
        if (ed != null) {
          info = UserDisplayInfo(
            id: id,
            nombre: info.hasNombre
                ? info.nombre
                : (ed['nombre'] as String? ?? '').trim(),
            fotoUrl: info.hasFoto
                ? info.fotoUrl
                : (ed['fotoUrl'] as String? ?? '').trim(),
            cargo: info.cargo.isNotEmpty
                ? info.cargo
                : (ed['cargo'] as String? ?? '').trim(),
          );
        }
      }

      _cache[id] = info;
      return info;
    } catch (e) {
      debugPrint('[UserDirectory] resolve($id) falló: $e');
      return UserDisplayInfo(id: id);
    }
  }

  UserDisplayInfo _fromUsuario(String id, Map<String, dynamic> u) {
    final nombres =
        (u['nombres'] as String? ?? u['primerNombre'] as String? ?? '').trim();
    final apellidos =
        (u['apellidos'] as String? ?? u['primerApellido'] as String? ?? '')
            .trim();
    var nombre = '$nombres $apellidos'.trim();
    if (nombre.isEmpty) nombre = (u['nombre'] as String? ?? '').trim();
    return UserDisplayInfo(
      id: id,
      nombre: nombre,
      fotoUrl: (u['fotoUrl'] as String? ?? '').trim(),
      cargo: (u['cargo'] as String? ?? '').trim(),
    );
  }
}
