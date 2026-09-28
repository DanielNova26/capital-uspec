import '../gestion_documental/correspondencia/gd_correspondencia_role_access.dart';
import '../utils/user_company.dart';

const correspondenceRolesAppId = 'correodashboard';

class CorrespondenceModuleRole {
  const CorrespondenceModuleRole({
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

  String get effectiveLevel => enabled ? level : 'visor';

  static CorrespondenceModuleRole? fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          correspondenceRolesAppId,
        ) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !correspondenceRoleLevelLabels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return CorrespondenceModuleRole(
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

String correspondenceRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolCorreoId'] ?? '')
        .toString()
        .trim();

bool correspondenceRoleNeedsSync(
  Map<String, dynamic> user,
  CorrespondenceModuleRole role, {
  String? assignedRole,
}) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return correspondenceRoleIdOf(user, role.empresaId) == role.id &&
      (assignedRole != null && assignedRole != role.effectiveLevel ||
          detail?['rolCorreoNombre'] != role.name ||
          detail?['rolCorreoVersion'] != role.revision ||
          detail?['rolCorreo'] != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              user['rolCorreo'] != role.effectiveLevel));
}
