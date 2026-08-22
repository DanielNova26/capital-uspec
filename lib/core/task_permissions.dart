import '../utils/user_company.dart';

String _taskPermissionKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
}

bool? _taskPermissionExplicitValue(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final key = _taskPermissionKey(value.toString());
  if (key == 'true' || key == '1' || key == 'si' || key == 'yes') {
    return true;
  }
  if (key == 'false' || key == '0' || key == 'no') return false;
  return null;
}

bool? _scopedTaskPermission(
  Map<String, dynamic> userData,
  List<String> keys,
  String? empresaId,
) {
  final detail = getUserCompanyDetail(userData, empresaId);
  for (final key in keys) {
    final value = _taskPermissionExplicitValue(detail?[key]);
    if (value != null) return value;
  }
  for (final key in keys) {
    final value = _taskPermissionExplicitValue(userData[key]);
    if (value != null) return value;
  }
  return null;
}

/// Define si un usuario puede crear tareas para cualquier área de la empresa
/// activa. El rol desarrollador mantiene el mismo bypass funcional que el
/// guard central de módulos, sin saltarse el contexto de empresa seleccionado.
bool canCreateTasksAcrossAreas(
  Map<String, dynamic> userData, {
  String cargoNombre = '',
  String? empresaId,
}) {
  final explicit = _scopedTaskPermission(userData, const [
    'crearTareasTodasAreas',
    'permiso_crear_tareas_todas_areas',
    'taskCreateAllAreas',
  ], empresaId);
  if (explicit != null) return explicit;

  final role = _taskPermissionKey(
    resolveScopedRoleKey(userData, empresaId: empresaId),
  );
  if ({
    'admin',
    'administrador',
    'superadmin',
    'desarrollador',
    'gerencia',
    'gerente',
  }.contains(role)) {
    return true;
  }

  final cargo = _taskPermissionKey(
    cargoNombre.trim().isNotEmpty
        ? cargoNombre
        : (userData['cargo'] ?? '').toString(),
  );
  return cargo == 'desarrollador' ||
      cargo.contains('gerent') ||
      cargo.contains('gerencia') ||
      cargo.contains('director general') ||
      cargo.contains('representante legal');
}

/// Define si el usuario puede abrir la vista consolidada de tareas de su
/// equipo. Un valor explícito por empresa tiene prioridad sobre la inferencia
/// por cargo o jerarquía, para que el Admin pueda auditar y corregir el acceso.
bool canViewTaskTeam(
  Map<String, dynamic> userData, {
  Map<String, dynamic>? structureData,
  String? empresaId,
}) {
  const managedFlags = ['puedeVerEquipo', 'canViewTeam', 'gestionaEquipo'];
  final explicit = _scopedTaskPermission(userData, managedFlags, empresaId);
  if (explicit != null) return explicit;

  const positivePermissionFlags = [
    'puedeVerEquipo',
    'canViewTeam',
    'gestionaEquipo',
    'esGerente',
    'isManager',
    'verTodo',
    'permiso_ver_todo',
    'viewAll',
  ];
  bool hasPositiveFlag(Map<String, dynamic>? data) {
    if (data == null) return false;
    for (final key in positivePermissionFlags) {
      if (_taskPermissionExplicitValue(data[key]) == true) return true;
    }
    return false;
  }

  if (hasPositiveFlag(getUserCompanyDetail(userData, empresaId)) ||
      hasPositiveFlag(userData) ||
      hasPositiveFlag(structureData)) {
    return true;
  }

  const teamFields = [
    'subordinates_ids',
    'subordinates_names',
    'subordinados',
    'equipo',
    'teamIds',
  ];
  bool hasTeamValues(Map<String, dynamic>? data) {
    if (data == null) return false;
    for (final key in teamFields) {
      final value = data[key];
      if (value is Iterable && value.isNotEmpty) return true;
      if (value is Map && value.isNotEmpty) return true;
      if (value != null && value.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  if (hasTeamValues(getUserCompanyDetail(userData, empresaId)) ||
      hasTeamValues(userData) ||
      hasTeamValues(structureData)) {
    return true;
  }

  bool looksLikeTeamLead(dynamic value) {
    final text = _taskPermissionKey((value ?? '').toString());
    if (text.isEmpty) return false;
    return text.contains('desarrollador') ||
        text.contains('admin') ||
        text.contains('gerent') ||
        text.contains('director') ||
        text.contains('subgerent') ||
        text.contains('coordinador') ||
        text.contains('jefe') ||
        text.contains('supervisor') ||
        text.contains('lider') ||
        text.contains('encargado') ||
        text.contains('responsable');
  }

  final role = resolveScopedRoleKey(userData, empresaId: empresaId);
  final cargo = resolveScopedStringWithFallbacks(
    userData,
    empresaId,
    const ['cargo', 'rol', 'role'],
    const ['cargo', 'rol', 'role'],
  );
  return looksLikeTeamLead(role) ||
      looksLikeTeamLead(cargo) ||
      looksLikeTeamLead(structureData?['cargo']) ||
      looksLikeTeamLead(structureData?['rol']) ||
      looksLikeTeamLead(structureData?['role']) ||
      looksLikeTeamLead(structureData?['puesto']) ||
      looksLikeTeamLead(structureData?['nivel']);
}
