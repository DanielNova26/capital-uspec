import 'package:cloud_functions/cloud_functions.dart';

import 'dian_tokens_models.dart';

class DianTokensService {
  DianTokensService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<List<DianTokenRecord>> listar({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions.httpsCallable('dianTokensListar').call({
      'empresaId': empresaId,
      'userId': userId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['tokens'];
    if (raw is! Iterable) return const [];
    return raw
        .whereType<Map>()
        .map((row) => DianTokenRecord.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<DianTokenAccess>> listarAccesos({
    required String empresaId,
    required String userId,
    required String tokenId,
  }) async {
    final result = await _functions.httpsCallable('dianTokenAccesos').call({
      'empresaId': empresaId,
      'userId': userId,
      'tokenId': tokenId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['accesses'];
    if (raw is! Iterable) return const [];
    return raw
        .whereType<Map>()
        .map((row) => DianTokenAccess.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Uri> abrir({
    required String empresaId,
    required String userId,
    required String tokenId,
  }) async {
    final result = await _functions.httpsCallable('dianTokenAbrir').call({
      'empresaId': empresaId,
      'userId': userId,
      'tokenId': tokenId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final uri = Uri.tryParse((data['url'] ?? '').toString());
    if (uri == null || uri.host != 'catalogo-vpfe.dian.gov.co') {
      throw StateError('El servidor no devolvió un enlace DIAN válido.');
    }
    return uri;
  }

  /// Estado del buzón propio del módulo (nunca devuelve la contraseña).
  Future<DianBuzonEstado> estadoBuzon({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions.httpsCallable('dianBuzonEstado').call({
      'empresaId': empresaId,
      'userId': userId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['buzon'];
    if (raw is! Map) return DianBuzonEstado.sinConectar;
    return DianBuzonEstado.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Conecta el buzón Yahoo. La contraseña de aplicación viaja una sola vez,
  /// se prueba contra el servidor IMAP y queda cifrada en el backend.
  Future<DianBuzonEstado> conectarBuzon({
    required String empresaId,
    required String userId,
    required String email,
    required String appPassword,
    bool procesarHistoricos = false,
  }) async {
    final result = await _functions
        .httpsCallable(
          'dianBuzonConectar',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        )
        .call({
          'empresaId': empresaId,
          'userId': userId,
          'email': email,
          'appPassword': appPassword,
          'procesarHistoricos': procesarHistoricos,
        });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['buzon'];
    if (raw is! Map) return DianBuzonEstado.sinConectar;
    return DianBuzonEstado.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Lee el buzón ahora mismo y devuelve el conteo de la corrida.
  Future<DianBuzonResumen> sincronizarBuzon({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions
        .httpsCallable(
          'dianBuzonSincronizar',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
        )
        .call({'empresaId': empresaId, 'userId': userId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['resumen'];
    if (raw is! Map) {
      return const DianBuzonResumen(
        revisados: 0,
        registrados: 0,
        duplicados: 0,
        descartados: 0,
        sinEnlace: 0,
      );
    }
    return DianBuzonResumen.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> desconectarBuzon({
    required String empresaId,
    required String userId,
  }) async {
    await _functions.httpsCallable('dianBuzonDesconectar').call({
      'empresaId': empresaId,
      'userId': userId,
    });
  }

  Future<void> cambiarEstado({
    required String empresaId,
    required String userId,
    required String tokenId,
    required String estado,
  }) async {
    await _functions.httpsCallable('dianTokenCambiarEstado').call({
      'empresaId': empresaId,
      'userId': userId,
      'tokenId': tokenId,
      'estado': estado,
    });
  }
}
