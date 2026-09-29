import '../../utils/user_company.dart';
import 'pp_models.dart';

const ppRoleLevelLabels = <String, String>{
  PpRoles.tesoreria: 'Tesorería',
  PpRoles.auditoria: 'Auditoría',
  PpRoles.gerencia: 'Gerencia',
  PpRoles.adminDoc: 'Administrador documental',
};

const ppActionLabels = <String, String>{
  'confirmar_carga': 'Cargar y generar planillas',
  'enviar_auditoria': 'Enviar a auditoría',
  'reenviar': 'Corregir y reenviar',
  'editar_nombre_planilla': 'Editar nombre',
  'observar': 'Registrar observaciones',
  'aprobar_auditoria': 'Aprobar auditoría',
  'rechazar_auditoria': 'Rechazar en auditoría',
  'enviar_gerencia': 'Enviar a gerencia',
  'firmar': 'Firmar en gerencia',
  'rechazar_gerencia': 'Rechazar en gerencia',
  'anular': 'Anular',
  'eliminar_planilla': 'Eliminar planillas',
  'eliminar_logo': 'Eliminar logos',
  'ver_lote': 'Consultar lotes',
  'gestionar_beneficiarios':
      'Gestionar beneficiarios y cuentas según sus reglas',
};

List<String> ppActionsForLevel(String level) => [
  for (final action in PpRoles.permisosAccion.keys)
    if (PpRoles.puedeEjecutar(action, level)) action,
];

String ppLevelDescription(String level) {
  final actions = ppActionsForLevel(level);
  return actions.isEmpty
      ? 'Sin acceso al flujo de Planillas.'
      : '${actions.map((a) => ppActionLabels[a] ?? a).join(', ')}. Las etapas de firma y las reglas de datos bancarios siguen aplicando.';
}

/// Vacío explícito y valores desconocidos no recuperan un nivel raíz anterior.
String? resolvePpPlanillasRole(Map<String, dynamic>? user, String empresaId) {
  if (user == null || !personaHabilitadaEn(user, empresaId)) return null;
  if (isDeveloperUser(user, empresaId: empresaId)) return PpRoles.desarrollador;
  final detail = getUserCompanyDetail(user, empresaId);
  final raw = detail?.containsKey('rolPlanillas') == true
      ? detail!['rolPlanillas']
      : raizEsDeEmpresa(user, empresaId)
      ? user['rolPlanillas']
      : null;
  final role = (raw ?? '').toString().trim().toLowerCase();
  return ppRoleLevelLabels.containsKey(role) ? role : null;
}

bool ppCanAccess(Map<String, dynamic>? user, String empresaId) {
  if (resolvePpPlanillasRole(user, empresaId) == null) return false;
  if (isDeveloperUser(user!, empresaId: empresaId)) return true;
  return userBelongsToEmpresa(user, empresaId) &&
      userHasApp(user, 'planillaspagodashboard', empresaId: empresaId);
}

bool ppIsNotificationRecipient(
  Map<String, dynamic> user,
  String empresaId,
  String expectedRole,
) =>
    ppCanAccess(user, empresaId) &&
    resolvePpPlanillasRole(user, empresaId) == expectedRole;
