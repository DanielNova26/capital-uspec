import '../compras/compras_role_access.dart';
import '../utils/user_company.dart';

const purchaseRolesAppId = 'comprasdashboard';

class PurchaseModuleRole {
  const PurchaseModuleRole({
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

  String get effectiveLevel => enabled ? level : 'consultas';

  static PurchaseModuleRole? fromData(String id, Map<String, dynamic> data) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          purchaseRolesAppId,
        ) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !comprasRoleLevelLabels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return PurchaseModuleRole(
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

String purchaseRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolComprasId'] ?? '')
        .toString()
        .trim();

bool purchaseRoleNeedsSync(
  Map<String, dynamic> user,
  PurchaseModuleRole role, {
  String? assignedRole,
}) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return purchaseRoleIdOf(user, role.empresaId) == role.id &&
      (assignedRole != null && assignedRole != role.effectiveLevel ||
          detail?['rolComprasNombre'] != role.name ||
          detail?['rolComprasVersion'] != role.revision ||
          detail?['rolCompras'] != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              user['rolCompras'] != role.effectiveLevel));
}
