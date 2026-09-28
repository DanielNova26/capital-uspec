import '../gestion_documental/gd_role_access.dart';
import '../utils/user_company.dart';

const libraryRolesAppId = 'bibliotecadocumentaldashboard';

class LibraryModuleRole {
  const LibraryModuleRole({
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

  String get effectiveLevel => enabled ? level : '';

  static LibraryModuleRole? fromData(String id, Map<String, dynamic> data) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          libraryRolesAppId,
        ) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !gdRoleLevelLabels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return LibraryModuleRole(
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

String libraryRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolBibliotecaId'] ?? '')
        .toString()
        .trim();

bool libraryRoleNeedsSync(Map<String, dynamic> user, LibraryModuleRole role) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return libraryRoleIdOf(user, role.empresaId) == role.id &&
      (detail?['rolBibliotecaNombre'] != role.name ||
          detail?['rolBibliotecaVersion'] != role.revision ||
          detail?['rolDocumental'] != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              user['rolDocumental'] != role.effectiveLevel));
}
