// Estado de los módulos de una empresa en TBL_APPS (30 sep 2026).
//
// Una empresa puede tener varios documentos para el mismo módulo: el
// canónico `{empresa}_{appId}` y otros viejos con el id corto o largo
// (`planillas`, `planillaspago`…), que dejaron cargas antiguas. Admin y la
// entrada al módulo (AccessGuard) leían el canónico; el Home y Talento
// Humano ocultaban el módulo si CUALQUIERA decía apagado. Con un duplicado
// viejo apagado, Admin mostraba Planillas de Pago prendido y al gerente se
// le quitaba del Home. Todos usan ahora la misma regla:
//   1. manda el documento canónico `{empresa}_{appId}`;
//   2. si no hay, el que se tocó de último (`updatedAt`);
//   3. sin fechas, prendido si alguno lo está.
// Sin ningún documento el módulo está prendido (compatibilidad).
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';

/// Id canónico de un módulo (`planillas` → `planillaspagodashboard`).
String appIdCanonico(String raw) {
  final ids = normalizeAppIdList([raw]).ids;
  return ids.isNotEmpty ? ids.first : raw.trim().toLowerCase();
}

/// Módulo al que corresponde un documento de TBL_APPS.
String appIdDeDocumento(
  String docId,
  Map<String, dynamic> data,
  String empresaId,
) {
  final raw = (data['appId'] ?? '').toString().trim();
  if (raw.isNotEmpty) return appIdCanonico(raw);
  final prefijo = '${empresaId}_';
  return appIdCanonico(
    docId.startsWith(prefijo) ? docId.substring(prefijo.length) : docId,
  );
}

/// `enabled` ausente cuenta como prendido.
bool appPrendida(Map<String, dynamic> data) =>
    (data['enabled'] as bool?) ?? true;

int? _ms(Object? value) =>
    value is Timestamp ? value.millisecondsSinceEpoch : null;

/// El documento que manda entre varios del mismo módulo (ver arriba).
T documentoQueManda<T>(
  List<T> docs, {
  required String idCanonico,
  required String Function(T) id,
  required Map<String, dynamic> Function(T) data,
}) {
  assert(docs.isNotEmpty);
  for (final d in docs) {
    if (id(d) == idCanonico) return d;
  }
  T? reciente;
  int? recienteMs;
  for (final d in docs) {
    final ms = _ms(data(d)['updatedAt']);
    if (ms != null && (recienteMs == null || ms > recienteMs)) {
      reciente = d;
      recienteMs = ms;
    }
  }
  if (reciente != null) return reciente;
  for (final d in docs) {
    if (appPrendida(data(d))) return d;
  }
  return docs.first;
}

/// Agrupa los documentos de la empresa por módulo canónico.
Map<String, List<T>> agruparAppsPorModulo<T>(
  Iterable<T> docs, {
  required String empresaId,
  required String Function(T) id,
  required Map<String, dynamic> Function(T) data,
}) {
  final grupos = <String, List<T>>{};
  for (final d in docs) {
    final appId = appIdDeDocumento(id(d), data(d), empresaId);
    if (appId.isEmpty) continue;
    grupos.putIfAbsent(appId, () => []).add(d);
  }
  return grupos;
}

/// Módulos apagados en la empresa (ids canónicos).
Set<String> appsApagadasDeEmpresa<T>(
  Iterable<T> docs, {
  required String empresaId,
  required String Function(T) id,
  required Map<String, dynamic> Function(T) data,
}) {
  final grupos = agruparAppsPorModulo(
    docs,
    empresaId: empresaId,
    id: id,
    data: data,
  );
  return {
    for (final entry in grupos.entries)
      if (!appPrendida(
        data(
          documentoQueManda(
            entry.value,
            idCanonico: '${empresaId}_${entry.key}',
            id: id,
            data: data,
          ),
        ),
      ))
        entry.key,
  };
}

/// Atajo para una consulta de Firestore.
Set<String> appsApagadasDeConsulta(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String empresaId,
) => appsApagadasDeEmpresa(
  docs,
  empresaId: empresaId,
  id: (d) => d.id,
  data: (d) => d.data(),
);
