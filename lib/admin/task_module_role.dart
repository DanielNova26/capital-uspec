import '../core/task_permissions.dart';
import '../utils/user_company.dart';

const taskRolesAppId = 'tareasdashboard';
const taskRoleType = 'module_role';

class TaskRolePermissions {
  const TaskRolePermissions({required this.allAreas, required this.viewTeam});
  final bool allAreas;
  final bool viewTeam;

  Map<String, dynamic> toMap() => {
    'crearTareasTodasAreas': allAreas,
    'puedeVerEquipo': viewTeam,
  };

  String get description =>
      '${allAreas ? 'Crear en todas las áreas' : 'Crear en su área'} · '
      '${viewTeam ? 'Ver tareas del equipo' : 'Sin vista del equipo'}';

  bool matches(TaskRolePermissions other) =>
      allAreas == other.allAreas && viewTeam == other.viewTeam;

  static TaskRolePermissions effective(
    Map<String, dynamic> user,
    String empresaId,
  ) => TaskRolePermissions(
    allAreas: canCreateTasksAcrossAreas(user, empresaId: empresaId),
    viewTeam: canViewTaskTeam(user, empresaId: empresaId),
  );
}

class TaskModuleRole {
  const TaskModuleRole({
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
  final TaskRolePermissions permissions;

  TaskRolePermissions get effectivePermissions => enabled
      ? permissions
      : const TaskRolePermissions(allAreas: false, viewTeam: false);

  static TaskModuleRole? fromData(String id, Map<String, dynamic> data) {
    if (data['type'] != taskRoleType ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          taskRolesAppId,
        )) {
      return null;
    }
    final permissions = data['permissions'];
    if (permissions is! Map ||
        permissions['crearTareasTodasAreas'] is! bool ||
        permissions['puedeVerEquipo'] is! bool ||
        data['empresaId'] is! String ||
        (data['nombre'] ?? '').toString().trim().isEmpty ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        (data['enabled'] != null && data['enabled'] is! bool)) {
      return null;
    }
    return TaskModuleRole(
      id: id,
      empresaId: data['empresaId'] as String,
      name: data['nombre'].toString(),
      description: (data['descripcion'] ?? '').toString(),
      enabled: data['enabled'] != false,
      revision: data['revision'] as int,
      permissions: TaskRolePermissions(
        allAreas: permissions['crearTareasTodasAreas'] as bool,
        viewTeam: permissions['puedeVerEquipo'] as bool,
      ),
    );
  }
}

String taskRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolTareasId'] ?? '')
        .toString()
        .trim();

bool taskRoleNeedsSync(Map<String, dynamic> user, TaskModuleRole role) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return taskRoleIdOf(user, role.empresaId) == role.id &&
      (detail?['rolTareasVersion'] != role.revision ||
          detail?['rolTareasNombre'] != role.name ||
          detail?['crearTareasTodasAreas'] !=
              role.effectivePermissions.allAreas ||
          detail?['puedeVerEquipo'] != role.effectivePermissions.viewTeam);
}

bool canManageModuleRoles(Map<String, dynamic> actor, String empresaId) =>
    personaHabilitadaEn(actor, empresaId) &&
    (isDeveloperUser(actor, empresaId: empresaId) ||
        (userBelongsToEmpresa(actor, empresaId) &&
            userHasApp(actor, 'admindashboard', empresaId: empresaId)));
