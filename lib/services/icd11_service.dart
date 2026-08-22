import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';

/// Resultado de una búsqueda ICD-11.
/// Permite al llamador distinguir entre éxito real, fallback servidor y
/// fallback cliente, en lugar de recibir siempre una lista vacía opaca.
class Icd11SearchResult {
  /// Diagnósticos encontrados. Vacío si hubo error o no hay resultados reales.
  final List<DiagnosticoMedico> resultados;

  /// true = la Cloud Function respondió correctamente (aunque resultados sea vacío).
  final bool exitoServidor;

  /// true = la Cloud Function indicó explícitamente que activó su fallback.
  /// Normalmente significa credenciales no configuradas o error OMS.
  final bool fallbackServidor;

  /// Detalle del error reportado por el servidor (si [fallbackServidor] es true).
  final String? errorDetalleServidor;

  /// true = no llegamos al servidor (timeout, error de red, auth Flutter, etc.).
  final bool fallbackCliente;

  /// Excepción capturada en cliente (si [fallbackCliente] es true).
  final String? errorDetalleCliente;

  const Icd11SearchResult({
    required this.resultados,
    this.exitoServidor = false,
    this.fallbackServidor = false,
    this.errorDetalleServidor,
    this.fallbackCliente = false,
    this.errorDetalleCliente,
  });

  bool get tieneResultados => resultados.isNotEmpty;

  @override
  String toString() {
    if (exitoServidor && tieneResultados) {
      return '[ICD11] OK — ${resultados.length} resultados WHO ICD-11';
    }
    if (exitoServidor && !tieneResultados) {
      return '[ICD11] OK — 0 resultados genuinos de la OMS';
    }
    if (fallbackServidor) {
      return '[ICD11] fallback servidor: $errorDetalleServidor';
    }
    if (fallbackCliente) {
      return '[ICD11] fallback cliente: $errorDetalleCliente';
    }
    return '[ICD11] estado desconocido';
  }
}

/// Cliente Flutter para la Cloud Function [icd11Search].
///
/// Las credenciales OMS viven en [functions/.env] en el servidor.
/// El client_secret nunca llega al cliente Flutter.
///
/// Retorna [Icd11SearchResult] en lugar de una lista opaca, para que
/// [DiagnosticosService] pueda loguear la causa exacta del fallback.
class Icd11Service {
  /// Feature flag global.
  /// false = omite la Cloud Function y retorna fallbackCliente directamente.
  static bool enabled = true;

  static const _timeout = Duration(seconds: 10);

  /// Llama a [icd11Search] y retorna un [Icd11SearchResult] descriptivo.
  static Future<Icd11SearchResult> buscarConDetalle(
    String query, {
    String language = 'es',
    String? userId,
    String? empresaId,
  }) async {
    if (!enabled) {
      return const Icd11SearchResult(
        resultados: [],
        fallbackCliente: true,
        errorDetalleCliente: 'Icd11Service.enabled = false',
      );
    }

    if (query.trim().length < 2) {
      return const Icd11SearchResult(
        resultados: [],
        fallbackCliente: true,
        errorDetalleCliente: 'query demasiado corto',
      );
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'icd11Search',
        options: HttpsCallableOptions(timeout: _timeout),
      );

      final result = await callable.call<Map<dynamic, dynamic>>({
        'query': query.trim(),
        'language': language,
        if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
        if ((empresaId ?? '').trim().isNotEmpty) 'empresaId': empresaId!.trim(),
      });

      final data = Map<String, dynamic>.from(result.data);
      final isFallback = data['fallback'] == true;
      final errorDetail = data['errorDetail']?.toString();
      final raw = (data['results'] as List?) ?? [];

      final diagnosticos = raw
          .cast<Map>()
          .map(
            (r) => DiagnosticoMedico(
              codigoCie11: r['icdCode']?.toString() ?? '',
              nombre: r['icdTitle']?.toString() ?? '',
              icdUri: r['icdUri']?.toString(),
              source: 'who_icd11',
              language: language,
              icdRelease: r['icdRelease']?.toString(),
            ),
          )
          .where((dx) => dx.codigoCie11.isNotEmpty && dx.nombre.isNotEmpty)
          .toList();

      return Icd11SearchResult(
        resultados: diagnosticos,
        exitoServidor: !isFallback,
        fallbackServidor: isFallback,
        errorDetalleServidor: isFallback ? errorDetail : null,
      );
    } on FirebaseFunctionsException catch (e) {
      return Icd11SearchResult(
        resultados: [],
        fallbackCliente: true,
        errorDetalleCliente:
            'FirebaseFunctionsException [${e.code}]: ${e.message}',
      );
    } catch (e) {
      return Icd11SearchResult(
        resultados: [],
        fallbackCliente: true,
        errorDetalleCliente: e.toString(),
      );
    }
  }

  /// Variante simplificada que solo retorna la lista de diagnósticos.
  /// Usa [buscarConDetalle] internamente y loguea el resultado en debug.
  static Future<List<DiagnosticoMedico>> buscar(
    String query, {
    String language = 'es',
    String? userId,
    String? empresaId,
  }) async {
    final resultado = await buscarConDetalle(
      query,
      language: language,
      userId: userId,
      empresaId: empresaId,
    );

    if (kDebugMode) {
      debugPrint(resultado.toString());
    }

    return resultado.resultados;
  }
}
