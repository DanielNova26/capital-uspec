import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../whatsapp/whatsapp_recipient_models.dart';
import 'correo_models.dart';

class CorreoService {
  CorreoService({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<List<CorreoCuenta>> streamCuentas(String empresaId) => _db
      .collection('TBL_CORREO_CUENTAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(CorreoCuenta.fromFirestore).toList();
        rows.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
        return rows;
      });

  Future<List<CorreoCuenta>> listarCuentas(String empresaId) async {
    final snap = await _db
        .collection('TBL_CORREO_CUENTAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final rows = snap.docs.map(CorreoCuenta.fromFirestore).toList();
    rows.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return rows;
  }

  Future<void> renombrarCuenta({
    required String cuentaId,
    required String empresaId,
    required String nombre,
  }) async {
    final ref = _db.collection('TBL_CORREO_CUENTAS').doc(cuentaId);
    final current = await ref.get();
    if (!current.exists ||
        current.data()?['empresaId']?.toString() != empresaId) {
      throw StateError('El buzón no pertenece a la empresa activa.');
    }
    await ref.set({
      'nombre': nombre.trim(),
      'nombrePersonalizado': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<CorreoRegla>> streamReglas(String empresaId) => _db
      .collection('TBL_CORREO_REGLAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(CorreoRegla.fromFirestore).toList();
        rows.sort((a, b) => b.prioridad.compareTo(a.prioridad));
        return rows;
      });

  Stream<List<WhatsAppListado>> streamListados(String empresaId) => _db
      .collection(kWhatsAppRecipientListsCollection)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) => snap.docs.map(WhatsAppListado.fromFirestore).toList());

  Stream<List<CorreoMensaje>> streamMensajes(String empresaId) => _db
      .collection('TBL_CORREO_MENSAJES')
      .where('empresaId', isEqualTo: empresaId)
      .orderBy('fechaCorreo', descending: true)
      .limit(250)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(CorreoMensaje.fromFirestore).toList();
        rows.sort(
          (a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)),
        );
        return rows;
      });

  Stream<List<CorreoMensaje>> streamMensajesDelDia(String empresaId) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _db
        .collection('TBL_CORREO_MENSAJES')
        .where('empresaId', isEqualTo: empresaId)
        .where('fechaCorreo', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('fechaCorreo', descending: true)
        .limit(1000)
        .snapshots()
        .map((snap) => snap.docs.map(CorreoMensaje.fromFirestore).toList());
  }

  Stream<List<CorreoAlerta>> streamAlertas(String empresaId) => _db
      .collection('TBL_CORREO_ALERTAS')
      .where('empresaId', isEqualTo: empresaId)
      .orderBy('createdAt', descending: true)
      .limit(250)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(CorreoAlerta.fromFirestore).toList();
        rows.sort(
          (a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)),
        );
        return rows;
      });

  Future<CorreoCuenta> crearCuenta({
    required String empresaId,
    required String nombre,
    required String email,
    required bool procesarHistoricos,
    String proveedor = 'gmail',
  }) async {
    final ref = _db.collection('TBL_CORREO_CUENTAS').doc();
    final cuenta = CorreoCuenta(
      id: ref.id,
      empresaId: empresaId,
      nombre: nombre.trim().isEmpty
          ? (email.trim().isEmpty ? 'Buzón Gmail' : email.trim())
          : nombre.trim(),
      email: email,
      procesarHistoricos: procesarHistoricos,
      proveedor: proveedor,
    );
    await ref.set({
      ...cuenta.toMap(),
      'estadoIntegracion': 'sin_conectar',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return cuenta;
  }

  Future<void> guardarRegla(CorreoRegla rule) async {
    final ref = _db
        .collection('TBL_CORREO_REGLAS')
        .doc(rule.id.isEmpty ? null : rule.id);
    await ref.set({
      ...rule.toMap(),
      if (rule.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> iniciarGmailOAuth({
    required String empresaId,
    required String cuentaId,
    required String userId,
  }) async {
    final result = await _functions.httpsCallable('correoGmailAuthorize').call({
      'empresaId': empresaId,
      'cuentaId': cuentaId,
      'userId': userId,
    });
    return (result.data as Map)['authorizationUrl'].toString();
  }

  Future<String> iniciarMicrosoftOAuth({
    required String empresaId,
    required String cuentaId,
    required String userId,
  }) async {
    final result = await _functions
        .httpsCallable('correoMicrosoftAuthorize')
        .call({'empresaId': empresaId, 'cuentaId': cuentaId, 'userId': userId});
    return (result.data as Map)['authorizationUrl'].toString();
  }

  Future<Map<String, dynamic>> procesar({
    required String empresaId,
    required String userId,
    String? cuentaId,
  }) async {
    final result = await _functions
        .httpsCallable(
          'correoProcesar',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
        )
        .call({
          'empresaId': empresaId,
          'userId': userId,
          'cuentaId': cuentaId ?? '',
        });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> probarRegla({
    required String empresaId,
    required String userId,
    required String reglaId,
    required String remitente,
    required String asunto,
    required String cuerpo,
  }) async {
    final result = await _functions.httpsCallable('correoProbarRegla').call({
      'empresaId': empresaId,
      'userId': userId,
      'reglaId': reglaId,
      'remitente': remitente,
      'asunto': asunto,
      'cuerpo': cuerpo,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> probarWhatsApp({
    required String empresaId,
    required String userId,
    required String telefono,
  }) async {
    final result = await _functions.httpsCallable('correoProbarWhatsApp').call({
      'empresaId': empresaId,
      'userId': userId,
      'telefono': telefono,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> estadoIntegracion({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions
        .httpsCallable('correoEstadoIntegracion')
        .call({'empresaId': empresaId, 'userId': userId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // La resolución de rol vive en `GdPermisosService` (gd_permisos.dart), que
  // devuelve el enum jerárquico compartido con Correspondencia y con el
  // backend. Antes existía una versión propia aquí que devolvía un String
  // suelto sin el nivel `clasificador`; se quitó para que no queden dos
  // fuentes de verdad del mismo rol.
}
