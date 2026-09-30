import '../facturacion/fac_role_access.dart';
import '../facturacion/facturacion_models.dart';
import '../utils/user_company.dart';

const billingRolesAppId = kFacAppId;

/// Rol de Facturación creado en Admin. Materializa uno de los tres niveles
/// que ya consume el módulo (`rolFac` en la ficha de la empresa).
class BillingModuleRole {
  const BillingModuleRole({
    required this.id,
    required this.empresaId,
    required this.name,
    required this.level,
    this.description = '',
    this.enabled = true,
    this.revision = 1,
  });
  final String id;
  final String empresaId;
  final String name;
  final String description;
  final String level;
  final bool enabled;
  final int revision;

  /// Inactivo deja Visor, explícito: un `rolFac` vacío también consulta,
  /// pero Visor se lee sin ambigüedad en Admin y en el módulo.
  String get effectiveLevel => enabled ? level : kRolFacVisor;

  static BillingModuleRole? fromData(String id, Map<String, dynamic> data) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          billingRolesAppId,
        ) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !facRoleLevelLabels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return BillingModuleRole(
      id: id,
      empresaId: data['empresaId'] as String,
      name: data['nombre'] as String,
      description: (data['descripcion'] ?? '').toString(),
      level: level,
      enabled: data['enabled'] as bool,
      revision: data['revision'] as int,
    );
  }
}

String billingRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolFacId'] ?? '')
        .toString()
        .trim();

bool billingRoleNeedsSync(Map<String, dynamic> user, BillingModuleRole role) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return billingRoleIdOf(user, role.empresaId) == role.id &&
      (detail?['rolFacNombre'] != role.name ||
          detail?['rolFacVersion'] != role.revision ||
          detail?['rolFac'] != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              user['rolFac'] != role.effectiveLevel));
}
