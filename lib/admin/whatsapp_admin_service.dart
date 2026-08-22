import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../whatsapp/whatsapp_recipient_models.dart';

String _normalizarBusqueda(String value) {
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  var result = value.trim().toLowerCase();
  replacements.forEach((source, target) {
    result = result.replaceAll(source, target);
  });
  return result.replaceAll(RegExp(r'\s+'), ' ');
}

class WhatsAppDirectorioPersona {
  const WhatsAppDirectorioPersona({
    required this.id,
    required this.cedula,
    required this.nombre,
    required this.telefono,
    required this.email,
    required this.cargo,
    required this.tieneTelefonoValido,
  });

  final String id;
  final String cedula;
  final String nombre;
  final String telefono;
  final String email;
  final String cargo;
  final bool tieneTelefonoValido;

  factory WhatsAppDirectorioPersona.fromMap(dynamic value) {
    final map = value is Map ? value : const {};
    return WhatsAppDirectorioPersona(
      id: (map['id'] ?? '').toString(),
      cedula: (map['cedula'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      telefono: (map['telefono'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      cargo: (map['cargo'] ?? '').toString(),
      tieneTelefonoValido: map['tieneTelefonoValido'] == true,
    );
  }

  bool coincide(String query) {
    final normalized = _normalizarBusqueda(query);
    if (normalized.isEmpty) return true;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    final searchable = _normalizarBusqueda('$nombre $cedula $email $cargo');
    final words = normalized.split(' ').where((word) => word.isNotEmpty);
    return words.every(searchable.contains) ||
        (digits.isNotEmpty && telefono.contains(digits));
  }
}

class WhatsAppAdminService {
  WhatsAppAdminService({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> estado({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions.httpsCallable('whatsappAdminEstado').call({
      'empresaId': empresaId,
      'userId': userId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> guardar({
    required String empresaId,
    required String userId,
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String sessionId,
    required String defaultCountryCode,
    required bool enabled,
    required bool correoEnabled,
    required bool comprasEnabled,
    required bool planillasEnabled,
    required bool interventoriaEnabled,
    required bool facturacionEnabled,
    required bool showCompanyEmoji,
    required bool showCompanyName,
    required String companyEmoji,
    required Map<String, Map<String, dynamic>> messageTemplates,
  }) async {
    await _functions.httpsCallable('whatsappAdminGuardar').call({
      'empresaId': empresaId,
      'userId': userId,
      'provider': provider,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'sessionId': sessionId,
      'defaultCountryCode': defaultCountryCode,
      'enabled': enabled,
      'modules': {
        'correo': correoEnabled,
        'compras': comprasEnabled,
        'planillas_pago': planillasEnabled,
        'interventoria': interventoriaEnabled,
        'facturacion': facturacionEnabled,
      },
      'branding': {
        'showEmoji': showCompanyEmoji,
        'showCompanyName': showCompanyName,
        'emoji': companyEmoji.trim(),
      },
      'messageTemplates': messageTemplates,
    });
  }

  Future<List<WhatsAppDirectorioPersona>> cargarDirectorio({
    required String empresaId,
    required String userId,
    bool incluirDetalles = false,
  }) async {
    final result = await _functions
        .httpsCallable('whatsappAdminDirectorio')
        .call({
          'empresaId': empresaId,
          'userId': userId,
          'includeDetails': incluirDetalles,
        });
    final payload = Map<String, dynamic>.from(result.data as Map);
    final people = payload['personas'] is List
        ? (payload['personas'] as List)
              .map(WhatsAppDirectorioPersona.fromMap)
              .toList()
        : <WhatsAppDirectorioPersona>[];
    people.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return people;
  }

  Future<Map<String, dynamic>> probar({
    required String empresaId,
    required String userId,
    required String telefono,
    String mensaje = '',
  }) async {
    final result = await _functions.httpsCallable('whatsappAdminProbar').call({
      'empresaId': empresaId,
      'userId': userId,
      'telefono': telefono,
      'mensaje': mensaje,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Stream<List<WhatsAppListado>> streamListados(String empresaId) => _db
      .collection(kWhatsAppRecipientListsCollection)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs.map(WhatsAppListado.fromFirestore).toList();
        rows.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
        return rows;
      });

  Stream<List<Map<String, dynamic>>> streamReglasCorreo(String empresaId) => _db
      .collection('TBL_CORREO_REGLAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => {'id': document.id, ...document.data()})
            .toList(),
      );

  Future<String> guardarListado({
    required String empresaId,
    required String userId,
    required String listadoId,
    required String nombre,
    required bool activo,
    required List<String> modulos,
    required List<WhatsAppDestinatario> destinatarios,
  }) async {
    final result = await _functions
        .httpsCallable('whatsappAdminGuardarListado')
        .call({
          'empresaId': empresaId,
          'userId': userId,
          'listadoId': listadoId,
          'nombre': nombre,
          'activo': activo,
          'modulos': modulos,
          'destinatarios': destinatarios.map((item) => item.toMap()).toList(),
        });
    return (result.data as Map)['listadoId'].toString();
  }

  Future<void> asignarListado({
    required String empresaId,
    required String userId,
    required String routeId,
    required String listadoId,
  }) async {
    await _functions.httpsCallable('whatsappAdminAsignarListado').call({
      'empresaId': empresaId,
      'userId': userId,
      'routeId': routeId,
      'listadoId': listadoId,
    });
  }

  Stream<List<Map<String, dynamic>>> streamEnvios(String empresaId) => _db
      .collection('TBL_CORREO_ALERTAS')
      .where('empresaId', isEqualTo: empresaId)
      .limit(100)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        rows.sort(
          (a, b) =>
              _timestamp(b['createdAt']).compareTo(_timestamp(a['createdAt'])),
        );
        return rows;
      });

  Stream<List<Map<String, dynamic>>> streamAuditoria(String empresaId) => _db
      .collection('TBL_WHATSAPP_AUDITORIA')
      .where('empresaId', isEqualTo: empresaId)
      .limit(50)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        rows.sort(
          (a, b) =>
              _timestamp(b['createdAt']).compareTo(_timestamp(a['createdAt'])),
        );
        return rows;
      });

  static DateTime _timestamp(dynamic value) => value is Timestamp
      ? value.toDate()
      : DateTime.fromMillisecondsSinceEpoch(0);
}
