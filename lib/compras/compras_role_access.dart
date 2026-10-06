import 'compras_models.dart';
import '../utils/user_company.dart';

const comprasRoleLevelLabels = <String, String>{
  kRolConsultas: 'Consultas',
  kRolCompras: 'Compras',
  kRolBodega: 'Bodega',
  kRolCalidad: 'Director de Calidad',
  kRolAdmin: 'Admin Documental',
};
String? comprasKnownLevel(String? value) {
  final level = normalizeComprasRol(value);
  return comprasRoleLevelLabels.containsKey(level) ? level : null;
}

String? inferComprasLevel(Map<String, dynamic> user, String empresaId) {
  final detail = getUserCompanyDetail(user, empresaId);
  if (detail?.containsKey('rolCompras') == true) {
    return comprasKnownLevel(detail!['rolCompras']?.toString());
  }
  const keys = [
    'rolCompras',
    'comprasRol',
    'rol_compras',
    'roleCompras',
    'roleKey',
    'role',
    'rol',
    'roleName',
    'cargo',
    'cargoNombre',
  ];
  for (final source in [?detail, if (raizEsDeEmpresa(user, empresaId)) user]) {
    for (final key in keys) {
      final level = comprasKnownLevel(source[key]?.toString());
      if (level != null) return level;
    }
  }
  return null;
}

String? resolveComprasLevel(
  Map<String, dynamic> user,
  String empresaId, {
  String? assignedRole,
}) {
  if (!personaHabilitadaEn(user, empresaId)) return null;
  if (isDeveloperUser(user, empresaId: empresaId)) return kRolAdmin;
  if (!userBelongsToEmpresa(user, empresaId) ||
      !userHasApp(user, 'comprasdashboard', empresaId: empresaId)) {
    return null;
  }
  if (assignedRole != null) return comprasKnownLevel(assignedRole);
  return inferComprasLevel(user, empresaId);
}

String comprasLevelDescription(String level) => switch (level) {
  kRolConsultas =>
    'Consultar proveedores, productos, recepciones y vigencias; sin gestión ni Abastecimiento.',
  kRolBodega =>
    'Registrar, completar y corregir recepciones (lotes, fechas y documentos mal cargados) y confirmar entregas. Consultar registros.',
  kRolCompras =>
    'Gestionar proveedores, productos y marcas; registrar recepciones, corregir documentos y programar Abastecimiento.',
  kRolCalidad =>
    'Gestionar catálogos y recepciones; revisar, aprobar, requerir, rechazar y revertir documentos. Exportar consultas.',
  kRolAdmin =>
    'Administrar el módulo, gestionar catálogos, recepción y Abastecimiento; revisar documentos, exportar y eliminar según las validaciones existentes.',
  _ => 'Sin acceso al módulo.',
};
