// Quitar una empresa de la estructura organizacional de una persona
// (29 sep 2026). Un registro de TBL_ESTRUCTURA_ORGANIZACIONAL es de una
// persona en todas sus empresas: borrar el documento completo le quitaba
// también las otras.
import 'package:cloud_firestore/cloud_firestore.dart';

const _kCamposPuesto = [
  'area',
  'areaNombre',
  'areaId',
  'cargo',
  'cargoNombre',
  'cargoId',
  'centroId',
  'centroCostos',
  'centroCodigo',
  'jefeId',
  'jefeNombre',
];

/// `null`: la persona solo está en [empresaId] y el registro se borra.
/// Si está en otras, los cambios para dejar solo esas: sin el bloque de la
/// empresa y, si era su principal, con el puesto de la siguiente en la raíz.
Map<String, Object?>? estructuraSinEmpresa(
  Map<String, dynamic> data,
  String empresaId,
) {
  final detalle = data['empresasDetalle'] is Map
      ? Map<String, dynamic>.from(data['empresasDetalle'] as Map)
      : <String, dynamic>{};
  final otras = <String>[
    for (final e in (data['empresas'] as List?) ?? const [])
      if (e.toString().trim().isNotEmpty && e.toString() != empresaId)
        e.toString(),
  ];
  for (final id in detalle.keys) {
    if (id != empresaId && !otras.contains(id)) otras.add(id);
  }
  final principal = (data['empresaId'] ?? '').toString().trim();
  if (principal.isNotEmpty &&
      principal != empresaId &&
      !otras.contains(principal)) {
    otras.insert(0, principal);
  }
  if (otras.isEmpty) return null;

  final cambios = <String, Object?>{
    'empresasDetalle.$empresaId': FieldValue.delete(),
    'empresas': otras,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (principal.isEmpty || principal == empresaId) {
    final siguiente = otras.first;
    final bloque = detalle[siguiente] is Map
        ? Map<String, dynamic>.from(detalle[siguiente] as Map)
        : const <String, dynamic>{};
    cambios['empresaId'] = siguiente;
    for (final campo in _kCamposPuesto) {
      cambios[campo] = bloque.containsKey(campo)
          ? bloque[campo]
          : FieldValue.delete();
    }
  }
  return cambios;
}
