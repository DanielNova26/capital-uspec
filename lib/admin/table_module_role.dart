import '../compras/compras_models.dart';
import '../interventoria/interventoria_models.dart';
import '../rutas/rutas_models.dart';
import '../utils/user_company.dart';
import '../visitas/visitas_models.dart';

/// Módulos cuyo rol vive en una tabla propia, un documento por persona y
/// empresa (`{tabla}/{empresaId}_{userId}` con `empresaId`, `userId` y `rol`):
/// Compras, Rutas, Interventoría y Visitas comparten el contrato de tabla.
/// El panel compartido usa estas configuraciones para Rutas, Interventoría y
/// Visitas; Compras tiene su panel de consolidación histórica específico.
///
/// Igual que Correspondencia: la definición vive en
/// `TBL_ROLES/{empresaId}_mod_{slug}_{nombre}` y asignarla materializa su
/// nivel en la tabla del módulo (lo que consumen el módulo y las reglas de
/// Firestore) y deja el vínculo en la ficha de la empresa.
class TableModuleRoleConfig {
  const TableModuleRoleConfig({
    required this.moduleKey,
    required this.appId,
    required this.slug,
    required this.moduleName,
    required this.collection,
    required this.fichaField,
    required this.levels,
    required this.levelDescriptions,
    required this.inactiveLevel,
    required this.adminLevels,
    required this.inactiveDescription,
    this.removeAppOnClear = false,
  });

  /// Clave del módulo en la matriz de Admin.
  final String moduleKey;
  final String appId;

  /// Segmento del id de la definición: `{empresaId}_mod_{slug}_{nombre}`.
  final String slug;
  final String moduleName;

  /// Tabla canónica del módulo.
  final String collection;

  /// Campo de la ficha por empresa: `rolCompras`, `rolComprasId`,
  /// `rolComprasNombre` y `rolComprasVersion`.
  final String fichaField;

  /// Niveles que se pueden crear, en orden, con su nombre visible. No incluye
  /// Desarrollador: es una excepción, no un nivel del formulario.
  final Map<String, String> levels;
  final Map<String, String> levelDescriptions;

  /// Lo que queda al inactivar un rol. Compras no puede quedar vacío: sin
  /// tabla, el módulo vuelve a deducir el rol del cargo y podría devolver
  /// uno mayor. Rutas e Interventoría no deducen nada: vacío es "sin rol".
  final String inactiveLevel;
  final String inactiveDescription;

  /// Retirar el nivel individual también retira la app; evita que accesos
  /// históricos sin fila canónica vuelvan a habilitar el módulo.
  final bool removeAppOnClear;

  /// Niveles que administran los roles del módulo, además de Admin y
  /// Desarrollo.
  final Set<String> adminLevels;

  String get idField => '${fichaField}Id';
  String get nameField => '${fichaField}Nombre';
  String get versionField => '${fichaField}Version';

  String levelLabel(String level) =>
      levels[level] ?? (level.isEmpty ? 'Sin rol' : level);

  String levelDescription(String level) =>
      levelDescriptions[level] ??
      (level == inactiveLevel ? inactiveDescription : '');
}

const comprasTableRoles = TableModuleRoleConfig(
  moduleKey: 'compras',
  appId: 'comprasdashboard',
  slug: 'compras',
  moduleName: 'Compras',
  collection: 'TBL_COMPRAS_ROLES',
  fichaField: 'rolCompras',
  levels: {
    kRolConsultas: 'Consultas',
    kRolBodega: 'Bodega',
    kRolCompras: 'Compras',
    kRolCalidad: 'Director de Calidad',
    kRolAdmin: 'Admin Documental',
  },
  levelDescriptions: {
    kRolConsultas: 'Solo consulta: no crea ni cambia nada.',
    kRolBodega: 'Recibe mercancía y consulta.',
    kRolCompras:
        'Gestiona proveedores, productos y recepciones; lo que sube requiere '
        'la aprobación de Calidad.',
    kRolCalidad:
        'Aprueba o rechaza fichas técnicas y documentos, además de gestionar.',
    kRolAdmin:
        'Acceso total: ve y puede eliminar recepciones, marcas, fichas '
        'técnicas y documentos, y administra los roles de Compras.',
  },
  inactiveLevel: kRolConsultas,
  inactiveDescription: 'Solo consulta: no crea ni cambia nada.',
  adminLevels: {kRolAdmin},
);

const rutasTableRoles = TableModuleRoleConfig(
  moduleKey: 'rutas',
  appId: kRutasAppId,
  slug: 'rutas',
  moduleName: 'Rutas',
  collection: 'TBL_RUTAS_ROLES',
  fichaField: 'rolRutas',
  levels: {
    kRutasRolConductor: 'Conductor',
    kRutasRolCalidad: 'Calidad',
    kRutasRolAdmin: 'Administrador',
    kRutasRolAdminCalidad: 'Administrador y Calidad',
  },
  levelDescriptions: {
    kRutasRolConductor:
        'Toma la evidencia fotográfica desde la app móvil (cámara y '
        'ubicación).',
    kRutasRolCalidad:
        'Revisa, aprueba o rechaza evidencias y consulta asignaciones.',
    kRutasRolAdmin:
        'Establecimientos, rutas, asignaciones, centro de control, estudio '
        'de movilidad y configuración; administra los roles de Rutas.',
    kRutasRolAdminCalidad: 'Administración y Calidad de Rutas.',
  },
  inactiveLevel: '',
  inactiveDescription: 'Sin rol en Rutas: no entra a ningún perfil.',
  adminLevels: {kRutasRolAdmin, kRutasRolAdminCalidad},
);

const interventoriaTableRoles = TableModuleRoleConfig(
  moduleKey: 'interventoria',
  appId: kInterventoriaAppId,
  slug: 'interventoria',
  moduleName: 'Interventoría',
  collection: 'TBL_INTERVENTORIA_ROLES',
  fichaField: 'rolInterventoria',
  levels: {
    kRolInterventoriaRegistrador: 'Registrador',
    kRolInterventoriaRevisor: 'Revisor',
    kRolInterventoriaCalidad: 'Calidad',
    kRolInterventoriaGerente: 'Gerente',
    kRolInterventoriaDirectivo: 'Directivo',
    kRolInterventoriaAdmin: 'Administrador',
  },
  levelDescriptions: {
    kRolInterventoriaRegistrador:
        'Registra el número de acta y los porcentajes; puede adjuntar el PDF del acta.',
    kRolInterventoriaRevisor:
        'Revisa y corrige actas en "Por revisar" y aprueba eliminaciones.',
    kRolInterventoriaCalidad:
        'Gestiona planes de mejora: revisa compromisos y soportes, devuelve '
        'entregas y prepara su presentación en K2. Consulta histórico y análisis; '
        'no reasigna responsables ni edita las actas.',
    kRolInterventoriaGerente:
        'Revisa actas, ve el análisis, aprueba eliminaciones y gestiona los '
        'planes de mejora K2 igual que Calidad.',
    kRolInterventoriaDirectivo:
        'Ve el análisis y el histórico y aprueba eliminaciones; no revisa '
        'actas.',
    kRolInterventoriaAdmin:
        'Administra el módulo: actas, revisión, responsables, análisis y '
        'roles de Interventoría.',
  },
  inactiveLevel: '',
  inactiveDescription: 'Sin rol en Interventoría: no entra al módulo.',
  adminLevels: {kRolInterventoriaAdmin},
);

/// Visitas guarda además el área de Jefe y Profesional (`areaId`), que pone
/// el repositorio al asignar. Gerencia no es un nivel del creador: la da
/// Desarrollo o sale del cargo (`resolverRolVisitas`).
const visitasTableRoles = TableModuleRoleConfig(
  moduleKey: 'visitas',
  appId: kVisitasAppId,
  slug: 'visitas',
  moduleName: 'Visitas',
  collection: kVisitasRolesCol,
  fichaField: 'rolVisitas',
  levels: {
    kVisitasRolConsulta: 'Consulta',
    kVisitasRolFirmante: 'Firmante del establecimiento',
    kVisitasRolProfesional: 'Profesional',
    kVisitasRolJefe: 'Jefe inmediato (director)',
  },
  levelDescriptions: {
    kVisitasRolConsulta:
        'Consulta las visitas y el consolidado sin programar ni diligenciar.',
    kVisitasRolFirmante:
        'Firma el acta desde su propio módulo cuando el profesional lo '
        'designa en la visita.',
    kVisitasRolProfesional:
        'Hace las visitas de su área: las inicia, diligencia el formato y la '
        'cierra el día programado.',
    kVisitasRolJefe:
        'Director del área: arma los grupos, programa las visitas y responde '
        'los cambios de fecha de su área.',
  },
  inactiveLevel: '',
  inactiveDescription: 'Sin rol en Visitas (salvo Gerencia por su cargo).',
  adminLevels: {kVisitasRolGerencia},
);

const dianTokensTableRoles = TableModuleRoleConfig(
  moduleKey: 'tokens_dian',
  appId: 'tokensdiandashboard',
  slug: 'tokens_dian',
  moduleName: 'Tokens DIAN',
  collection: 'TBL_DIAN_TOKEN_ROLES',
  fichaField: 'rolTokensDian',
  levels: {
    'consulta': 'Consulta',
    'operador': 'Operador',
    'administrador': 'Administrador',
  },
  levelDescriptions: {
    'consulta':
        'Ve los metadatos y el historial de accesos, sin abrir enlaces.',
    'operador': 'Abre tokens y solicita nuevas lecturas del buzón.',
    'administrador': 'Configura el buzón, administra estados y roles.',
  },
  inactiveLevel: 'consulta',
  inactiveDescription: 'Solo consulta; no abre enlaces ni configura el buzón.',
  adminLevels: {'administrador'},
  removeAppOnClear: true,
);

const talentoHumanoTableRoles = TableModuleRoleConfig(
  moduleKey: 'talento',
  appId: 'talentohumanodashboard',
  slug: 'talento_humano',
  moduleName: 'Talento Humano',
  collection: 'TBL_TALENTO_HUMANO_ROLES',
  fichaField: 'rolTalentoHumano',
  levels: {
    'consulta': 'Consulta',
    'solicitante': 'Solicitante',
    'reclutador': 'Reclutamiento',
    'gestor': 'Gestión de personal',
    'administrador': 'Administrador',
  },
  levelDescriptions: {
    'consulta': 'Consulta indicadores y requerimientos sin modificar datos.',
    'solicitante': 'Crea requerimientos de personal y consulta su avance.',
    'reclutador': 'Gestiona selección, candidatos y hojas de vida.',
    'gestor':
        'Gestiona personal, estructura, documentos, disciplina y comunicados.',
    'administrador': 'Gestiona todo Talento Humano, incluidos accesos y roles.',
  },
  inactiveLevel: 'consulta',
  inactiveDescription: 'Solo consulta; no modifica información del personal.',
  adminLevels: {'administrador'},
  removeAppOnClear: true,
);

const nutricionTableRoles = TableModuleRoleConfig(
  moduleKey: 'nutricion',
  appId: 'nutriciondashboard',
  slug: 'nutricion',
  moduleName: 'Nutrición',
  collection: 'TBL_NUTRICION_ROLES',
  fichaField: 'rolNutricion',
  levels: {
    'consulta': 'Consulta y reportes',
    'clinico': 'Atención clínica',
    'menus': 'Menús e ingredientes',
    'coordinador': 'Coordinación',
    'administrador': 'Administrador',
  },
  levelDescriptions: {
    'consulta': 'Consulta información y genera reportes sin modificar datos.',
    'clinico': 'Atiende pacientes, registra valoraciones, controles y firmas.',
    'menus': 'Diseña menús, dietas, plantillas e ingredientes.',
    'coordinador': 'Gestiona atención clínica y menús, además de reportes.',
    'administrador': 'Gestiona todo Nutrición, incluidos accesos y roles.',
  },
  inactiveLevel: 'consulta',
  inactiveDescription: 'Solo consulta y reportes; no modifica datos.',
  adminLevels: {'administrador'},
  removeAppOnClear: true,
);

const tableModuleRoleConfigs = <TableModuleRoleConfig>[
  rutasTableRoles,
  interventoriaTableRoles,
  visitasTableRoles,
  dianTokensTableRoles,
  talentoHumanoTableRoles,
  nutricionTableRoles,
];

TableModuleRoleConfig? tableModuleRoleConfigFor(String moduleKey) {
  for (final config in tableModuleRoleConfigs) {
    if (config.moduleKey == moduleKey) return config;
  }
  return null;
}

class TableModuleRole {
  const TableModuleRole({
    required this.config,
    required this.id,
    required this.empresaId,
    required this.name,
    required this.level,
    this.description = '',
    this.enabled = true,
    this.revision = 1,
  });

  final TableModuleRoleConfig config;
  final String id;
  final String empresaId;
  final String name;
  final String description;
  final String level;
  final bool enabled;
  final int revision;

  String get effectiveLevel => enabled ? level : config.inactiveLevel;

  static TableModuleRole? fromData(
    TableModuleRoleConfig config,
    String id,
    Map<String, dynamic> data,
  ) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent((data['moduleId'] ?? '').toString(), config.appId) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !config.levels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return TableModuleRole(
      config: config,
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

/// Id del rol configurable al que está vinculada la persona en [empresaId];
/// vacío si maneja un nivel individual.
String tableRoleIdOf(
  TableModuleRoleConfig config,
  Map<String, dynamic> user,
  String empresaId,
) => (getUserCompanyDetail(user, empresaId)?[config.idField] ?? '')
    .toString()
    .trim();

/// ¿La persona sigue vinculada a [role] pero su ficha o la tabla del módulo
/// ([assignedLevel]) no tienen todavía la versión vigente?
bool tableRoleNeedsSync(
  Map<String, dynamic> user,
  TableModuleRole role, {
  String? assignedLevel,
}) {
  final config = role.config;
  final detail = getUserCompanyDetail(user, role.empresaId);
  return tableRoleIdOf(config, user, role.empresaId) == role.id &&
      ((assignedLevel ?? '') != role.effectiveLevel ||
          detail?[config.nameField] != role.name ||
          detail?[config.versionField] != role.revision ||
          (detail?[config.fichaField] ?? '') != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              (user[config.fichaField] ?? '') != role.effectiveLevel));
}
