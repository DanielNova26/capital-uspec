import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'compras_models.dart';
import 'compras_role_access.dart';

class ComprasAccessService {
  ComprasAccessService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Future<DocumentSnapshot<Map<String, dynamic>>?> userDocument(
    String identity,
  ) async {
    if (identity.trim().isEmpty) return null;
    final direct = await _db.collection('TBL_USUARIOS').doc(identity).get();
    if (direct.exists) return direct;
    final byCedula = await _db
        .collection('TBL_USUARIOS')
        .where('cedula', isEqualTo: identity)
        .get();
    return byCedula.docs.firstOrNull;
  }

  Future<ComprasRolDoc?> explicitRole(String empresaId, String identity) async {
    final user = await userDocument(identity);
    if (user == null) return null;
    final canonical = await _db
        .collection('TBL_COMPRAS_ROLES')
        .doc('${empresaId}_${user.id}')
        .get();
    if (canonical.exists &&
        (canonical.data()?['empresaId'] != empresaId ||
            canonical.data()?['userId'] != user.id)) {
      throw StateError('La asignación canónica de Compras es inválida.');
    }
    if (canonical.exists &&
        canonical.data()?['empresaId'] == empresaId &&
        canonical.data()?['userId'] == user.id) {
      return ComprasRolDoc.fromMap(canonical.id, canonical.data()!);
    }
    final legacy = await _db
        .collection('TBL_COMPRAS_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final cedula = (user.data()?['cedula'] ?? identity).toString();
    for (final doc in legacy.docs) {
      final data = doc.data();
      if (data['userId'] == user.id ||
          (cedula.isNotEmpty && data['cedula'] == cedula)) {
        return ComprasRolDoc.fromMap(doc.id, data);
      }
    }
    return null;
  }

  Future<ComprasRolDoc?> resolve(String empresaId, String identity) async {
    final user = await userDocument(identity);
    if (user == null || user.data() == null) return null;
    final explicit = await explicitRole(empresaId, user.id);
    final level = resolveComprasLevel(
      user.data()!,
      empresaId,
      assignedRole: explicit?.rol,
    );
    if (level == null) return null;
    final data = user.data()!;
    return ComprasRolDoc(
      id: explicit?.id ?? '',
      empresaId: empresaId,
      userId: user.id,
      cedula: (data['cedula'] ?? user.id).toString(),
      nombre:
          (data['nombre'] ??
                  '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}')
              .toString()
              .trim(),
      rol: level,
      createdAt: explicit?.createdAt ?? Timestamp.now(),
    );
  }

  Future<String> require(
    String empresaId,
    String actorId,
    Set<String> allowed,
  ) async {
    final current = await resolve(empresaId, actorId);
    if (current == null || !allowed.contains(current.rol)) {
      throw StateError(
        'Tu acceso o nivel de Compras cambió o no permite esta acción. Actualiza la pantalla.',
      );
    }
    return current.rol;
  }

  Stream<ComprasRolDoc?> watch(String empresaId, String identity) {
    late StreamController<ComprasRolDoc?> controller;
    final subscriptions = <StreamSubscription>[];
    var revision = 0;
    var active = true;
    Future<void> refresh() async {
      final requested = ++revision;
      try {
        final role = await resolve(empresaId, identity);
        if (active && !controller.isClosed && requested == revision) {
          controller.add(role);
        }
      } catch (_) {
        if (active && !controller.isClosed && requested == revision) {
          controller.add(null);
        }
      }
    }

    controller = StreamController(
      onListen: () async {
        try {
          final user = await userDocument(identity);
          if (!active || controller.isClosed) return;
          if (user == null) {
            controller.add(null);
            return;
          }
          subscriptions.add(
            user.reference.snapshots().listen(
              (_) => refresh(),
              onError: (Object _) => refresh(),
            ),
          );
          // Includes legacy edits while migration is being completed.
          subscriptions.add(
            _db
                .collection('TBL_COMPRAS_ROLES')
                .where('empresaId', isEqualTo: empresaId)
                .snapshots()
                .listen((_) => refresh(), onError: (Object _) => refresh()),
          );
          refresh();
        } catch (_) {
          if (active && !controller.isClosed) controller.add(null);
        }
      },
      onCancel: () async {
        active = false;
        revision++;
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }
}
