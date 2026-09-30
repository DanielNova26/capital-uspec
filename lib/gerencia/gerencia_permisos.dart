// lib/gerencia/gerencia_permisos.dart
//
// Qué puede ver cada persona en Gerencia (29 sep 2026). El rol lo crea Admin
// en TBL_ROLES y se materializa en la ficha de la empresa:
// `empresasDetalle.{empresa}.rolGerenciaId/Nombre/Version` y
// `permisosGerencia` (un mapa `{permiso: bool}`).
//
// Reglas que pidió el usuario:
// - Sin rol no ve nada, aunque tenga la app (Desarrollo sí entra).
// - "Solo su área" es la de su ficha (con el cargo como respaldo, igual que
//   el resto de Gerencia).
// - Los Puntos (ranking) salen de las tareas que el rol deja ver.
// - Lo que el módulo agregue después entra en [kGerenciaPermisos]: los roles
//   guardados antes no lo traen y quedan sin él hasta que Admin lo encienda.
//
// Los nombres de campo no empiezan por `rol`/`roleKey` a secas: Visitas
// detecta "Gerencia" por el rol general de la ficha y no debe confundirse.

import '../core/area_directory.dart';
import '../utils/user_company.dart';

const kGerenciaAppId = 'gerenciadashboard';

const kGerPermTodasLasAreas = 'todasLasAreas';
const kGerPermTodasLasEmpresas = 'todasLasEmpresas';
const kGerPermDashboard = 'pestanaDashboard';
const kGerPermPuntos = 'pestanaPuntos';
const kGerPermInterventoria = 'pestanaInterventoria';
const kGerPermExportar = 'exportar';

class GerenciaPermiso {
  const GerenciaPermiso(this.clave, this.etiqueta, this.descripcion);
  final String clave;
  final String etiqueta;
  final String descripcion;
}

/// Catálogo único: Admin pinta un interruptor por permiso y el módulo solo
/// consulta claves de aquí.
const kGerenciaPermisos = <GerenciaPermiso>[
  GerenciaPermiso(
    kGerPermTodasLasAreas,
    'Todas las áreas',
    'Sin este permiso solo ve el área de su ficha.',
  ),
  GerenciaPermiso(
    kGerPermTodasLasEmpresas,
    'Todas sus empresas',
    'Sin este permiso solo ve la empresa activa. En cada otra empresa '
        'necesita también un rol de Gerencia.',
  ),
  GerenciaPermiso(
    kGerPermDashboard,
    'Pestaña Dashboard',
    'Indicadores y gráficas de tareas.',
  ),
  GerenciaPermiso(
    kGerPermPuntos,
    'Pestaña Puntos',
    'Ranking de cumplimiento por persona.',
  ),
  GerenciaPermiso(
    kGerPermInterventoria,
    'Pestaña Interventoría',
    'Hallazgos y visitas de las actas, en consulta.',
  ),
  GerenciaPermiso(kGerPermExportar, 'Exportar', 'Descargar PDF y Excel.'),
];

class GerenciaPermisos {
  const GerenciaPermisos(this._valores);
  const GerenciaPermisos.ninguno() : _valores = const {};
  GerenciaPermisos.todos()
    : _valores = {for (final p in kGerenciaPermisos) p.clave: true};

  final Map<String, bool> _valores;

  bool tiene(String clave) => _valores[clave] == true;
  bool get todasLasAreas => tiene(kGerPermTodasLasAreas);
  bool get todasLasEmpresas => tiene(kGerPermTodasLasEmpresas);
  bool get dashboard => tiene(kGerPermDashboard);
  bool get puntos => tiene(kGerPermPuntos);
  bool get interventoria => tiene(kGerPermInterventoria);
  bool get exportar => tiene(kGerPermExportar);
  bool get algunaPestana => dashboard || puntos || interventoria;

  GerenciaPermisos con(String clave, bool valor) =>
      GerenciaPermisos({..._valores, clave: valor});

  /// Todas las claves del catálogo, en falso las que no traía.
  Map<String, bool> toMap() => {
    for (final p in kGerenciaPermisos) p.clave: tiene(p.clave),
  };

  bool igualA(GerenciaPermisos otro) =>
      kGerenciaPermisos.every((p) => tiene(p.clave) == otro.tiene(p.clave));

  String get descripcion {
    final activos = [
      for (final p in kGerenciaPermisos)
        if (tiene(p.clave)) p.etiqueta,
    ];
    return activos.isEmpty ? 'Sin permisos' : activos.join(' · ');
  }

  /// `null` si no es un mapa o si algún permiso conocido no es booleano:
  /// nunca se lee un "sí" de un texto. Las claves que falten son falsas.
  static GerenciaPermisos? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final valores = <String, bool>{};
    for (final p in kGerenciaPermisos) {
      final valor = raw[p.clave];
      if (valor == null) continue;
      if (valor is! bool) return null;
      valores[p.clave] = valor;
    }
    return GerenciaPermisos(valores);
  }
}

/// Permisos de la persona en una empresa; `null` si no tiene rol ahí.
GerenciaPermisos? permisosGerenciaDe(
  Map<String, dynamic> user,
  String empresaId,
) {
  final empresa = empresaId.trim();
  if (empresa.isEmpty || !personaHabilitadaEn(user, empresa)) return null;
  if (isDeveloperUser(user, empresaId: empresa)) {
    return GerenciaPermisos.todos();
  }
  final detail = getUserCompanyDetail(user, empresa);
  if ((detail?['rolGerenciaId'] ?? '').toString().trim().isEmpty) return null;
  return GerenciaPermisos.fromMap(detail?['permisosGerencia']);
}

/// Lo que la persona puede ver en Gerencia desde la empresa activa.
class GerenciaAcceso {
  const GerenciaAcceso._({
    required this.empresaActiva,
    required this.permisos,
    required this.porEmpresa,
    this.motivo = '',
    this.areaPropia = const {},
  });

  const GerenciaAcceso.denegado(this.empresaActiva, this.motivo)
    : permisos = const GerenciaPermisos.ninguno(),
      porEmpresa = const {},
      areaPropia = const {};

  final String empresaActiva;

  /// Los del rol de la empresa activa: mandan en pestañas y exportación.
  final GerenciaPermisos permisos;

  /// Empresas que puede consultar, con el rol que tiene en cada una: el
  /// alcance de áreas de cada registro sale del rol de su empresa.
  final Map<String, GerenciaPermisos> porEmpresa;

  /// Por qué no entra; vacío si entra.
  final String motivo;

  /// Nombre legible del área de su ficha, por empresa.
  final Map<String, String> areaPropia;

  bool get permitido => porEmpresa.isNotEmpty && permisos.algunaPestana;
  Set<String> get empresas => porEmpresa.keys.toSet();

  /// ¿Alguna empresa lo deja solo en su área?
  bool get limitadoPorArea =>
      porEmpresa.values.any((permisos) => !permisos.todasLasAreas);

  GerenciaAcceso conAreaPropia(Map<String, String> areas) => GerenciaAcceso._(
    empresaActiva: empresaActiva,
    permisos: permisos,
    porEmpresa: porEmpresa,
    motivo: motivo,
    areaPropia: areas,
  );

  /// ¿Un registro de [empresaId] cuya área se lee [areaNombre] entra en lo
  /// que puede ver? Se compara por nombre normalizado (`areaClave`): la misma
  /// área existe con varias variantes de id.
  bool incluye(String empresaId, String areaNombre) {
    final rol = porEmpresa[empresaId.trim()];
    if (rol == null) return false;
    if (rol.todasLasAreas) return true;
    final propia = areaClave(areaPropia[empresaId.trim()] ?? '');
    return propia.isNotEmpty &&
        propia != areaClave('Sin área') &&
        areaClave(areaNombre) == propia;
  }
}

/// Resuelve el acceso con el rol de la empresa activa. Con "Todas sus
/// empresas" suma las demás en que también tenga rol de Gerencia.
GerenciaAcceso resolverAccesoGerencia(
  Map<String, dynamic> user,
  String empresaActiva,
) {
  final activa = empresaActiva.trim();
  final empresas = empresasSeleccionables(user);
  final propios = empresas.contains(activa)
      ? permisosGerenciaDe(user, activa)
      : null;
  if (propios == null) {
    return GerenciaAcceso.denegado(
      activa,
      'No tienes un rol de Gerencia en esta empresa. Pídele a Admin que te '
      'asigne uno.',
    );
  }
  if (!propios.algunaPestana) {
    return GerenciaAcceso.denegado(
      activa,
      'Tu rol de Gerencia no tiene pestañas habilitadas o está inactivo.',
    );
  }
  final porEmpresa = <String, GerenciaPermisos>{activa: propios};
  if (propios.todasLasEmpresas) {
    for (final empresa in empresas) {
      if (porEmpresa.containsKey(empresa)) continue;
      final otros = permisosGerenciaDe(user, empresa);
      if (otros != null && otros.algunaPestana) porEmpresa[empresa] = otros;
    }
  }
  return GerenciaAcceso._(
    empresaActiva: activa,
    permisos: propios,
    porEmpresa: porEmpresa,
  );
}
