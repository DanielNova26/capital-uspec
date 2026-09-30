import '../gerencia/gerencia_permisos.dart';
import '../utils/user_company.dart';

const managementRolesAppId = kGerenciaAppId;

/// Rol de Gerencia creado en Admin: un conjunto de permisos del catálogo
/// [kGerenciaPermisos] que se copia en `permisosGerencia` de la ficha.
class ManagementModuleRole {
  const ManagementModuleRole({
    required this.id,
    required this.empresaId,
    required this.name,
    required this.permissions,
    this.description = '',
    this.enabled = true,
    this.revision = 1,
  });

  final String id;
  final String empresaId;
  final String name;
  final String description;
  final bool enabled;
  final int revision;
  final GerenciaPermisos permissions;

  /// Inactivo no deja ver nada: el módulo pide rol con alguna pestaña.
  GerenciaPermisos get effectivePermissions =>
      enabled ? permissions : const GerenciaPermisos.ninguno();

  static ManagementModuleRole? fromData(String id, Map<String, dynamic> data) {
    final permissions = GerenciaPermisos.fromMap(data['permissions']);
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          managementRolesAppId,
        ) ||
        permissions == null ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return ManagementModuleRole(
      id: id,
      empresaId: data['empresaId'] as String,
      name: data['nombre'] as String,
      description: (data['descripcion'] ?? '').toString(),
      enabled: data['enabled'] as bool,
      revision: data['revision'] as int,
      permissions: permissions,
    );
  }
}

String managementRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolGerenciaId'] ?? '')
        .toString()
        .trim();

bool managementRoleNeedsSync(
  Map<String, dynamic> user,
  ManagementModuleRole role,
) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  final current = GerenciaPermisos.fromMap(detail?['permisosGerencia']);
  return managementRoleIdOf(user, role.empresaId) == role.id &&
      (detail?['rolGerenciaNombre'] != role.name ||
          detail?['rolGerenciaVersion'] != role.revision ||
          current == null ||
          !current.igualA(role.effectivePermissions));
}
