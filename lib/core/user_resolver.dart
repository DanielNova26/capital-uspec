// lib/core/user_resolver.dart
//
// Helper de resolución transitoria de identidad de usuario.
//
// Orden de lookup:
//   1. Por uid  (Firebase Auth UID almacenado en TBL_USUARIOS.uid)
//   2. Por cedula (campo cedula en TBL_USUARIOS)
//   3. Por docId legacy (document ID en TBL_USUARIOS, típicamente username)
//
// No tiene lógica visual ni dependencias de plataforma.
// No toma decisiones de navegación.
// Compatible con pruebas: si uid no existe aún, cae a cedula/docId sin error.

import 'package:flutter/foundation.dart';

import '../data/firestore_user_repository.dart';

/// Estrategia que se usó para resolver al usuario.
enum UserResolutionStrategy {
  /// Resuelto por el campo 'uid' en TBL_USUARIOS.
  byUid,

  /// Resuelto por el campo 'cedula' en TBL_USUARIOS.
  byCedula,

  /// Resuelto por docId legacy (username) en TBL_USUARIOS.
  byDocId,

  /// No encontrado por ninguna estrategia.
  notFound,
}

/// Resultado de la resolución de identidad de un usuario.
class UserResolution {
  final String docId;
  final Map<String, dynamic> data;
  final UserResolutionStrategy strategy;

  /// true si el documento ya tenía el campo 'uid' cuando fue resuelto.
  /// false indica que el campo necesita backfill cuando Firebase Auth esté activo.
  final bool documentHasUid;

  const UserResolution({
    required this.docId,
    required this.data,
    required this.strategy,
    required this.documentHasUid,
  });

  bool get found => strategy != UserResolutionStrategy.notFound;

  /// true si se resolvió por docId legacy — señal de datos no migrados aún.
  bool get isLegacy => strategy == UserResolutionStrategy.byDocId;

  /// true si el documento aún no tiene el campo 'uid' — pendiente de backfill.
  bool get needsUidBackfill => !documentHasUid;
}

/// Resuelve el perfil operativo de un usuario con identidad transitoria.
///
/// Uso:
/// ```dart
/// final resolver = UserResolver();
/// final result = await resolver.resolve(cedula: '12345678');
/// if (result.found) {
///   final data = result.data;
///   if (result.needsUidBackfill) {
///     // escribir uid cuando Firebase Auth esté disponible
///   }
/// }
/// ```
class UserResolver {
  final FirestoreUserRepository _repo;

  UserResolver({FirestoreUserRepository? repo})
      : _repo = repo ?? FirestoreUserRepository.instance;

  /// Resuelve el usuario aplicando el lookup transitorio.
  ///
  /// Parámetros opcionales — al menos uno debe ser no vacío para obtener
  /// un resultado. Si todos son nulos/vacíos retorna [strategy=notFound].
  Future<UserResolution> resolve({
    String? uid,
    String? cedula,
    String? docId,
  }) async {
    // ── 1. Por uid ──────────────────────────────────────────────────────────
    if (uid != null && uid.isNotEmpty) {
      final snap = await _repo.resolveByUid(uid);
      if (snap != null) {
        debugPrint('[UserResolver] resuelto por uid → docId=${snap.id}');
        return UserResolution(
          docId: snap.id,
          data: snap.data()!,
          strategy: UserResolutionStrategy.byUid,
          documentHasUid: true,
        );
      }
      debugPrint('[UserResolver] uid=$uid no encontrado → fallback a cedula');
    }

    // ── 2. Por cedula ────────────────────────────────────────────────────────
    if (cedula != null && cedula.isNotEmpty) {
      final cleanCedula = _repo.sanitizeCedula(cedula);
      if (cleanCedula.isNotEmpty) {
        final snap = await _repo.resolveByField('cedula', cleanCedula);
        if (snap != null) {
          final hasUid =
              ((snap.data()?['uid'] as String?) ?? '').isNotEmpty;
          debugPrint(
            '[UserResolver] resuelto por cedula → docId=${snap.id} '
            'hasUid=$hasUid',
          );
          return UserResolution(
            docId: snap.id,
            data: snap.data()!,
            strategy: UserResolutionStrategy.byCedula,
            documentHasUid: hasUid,
          );
        }
        debugPrint(
          '[UserResolver] cedula=$cleanCedula no encontrada → fallback a docId',
        );
      }
    }

    // ── 3. Por docId legacy ──────────────────────────────────────────────────
    if (docId != null && docId.isNotEmpty) {
      final snap = await _repo.resolveByDocId(docId);
      if (snap != null) {
        final hasUid =
            ((snap.data()?['uid'] as String?) ?? '').isNotEmpty;
        debugPrint(
          '[UserResolver] resuelto por docId legacy → docId=${snap.id} '
          'hasUid=$hasUid',
        );
        return UserResolution(
          docId: snap.id,
          data: snap.data()!,
          strategy: UserResolutionStrategy.byDocId,
          documentHasUid: hasUid,
        );
      }
    }

    debugPrint(
      '[UserResolver] no encontrado '
      '(uid=$uid, cedula=$cedula, docId=$docId)',
    );
    return const UserResolution(
      docId: '',
      data: {},
      strategy: UserResolutionStrategy.notFound,
      documentHasUid: false,
    );
  }
}
