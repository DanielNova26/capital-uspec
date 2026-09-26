import 'interventoria_actas_catalogo.dart';
import 'interventoria_models.dart';
import 'interventoria_numerales_catalogo.dart';
import 'interventoria_service.dart'
    show
        InterventoriaPersona,
        InterventoriaUsuario,
        resolverPrimerCargoQueResuelva;

/// Revisión del maestro de subsanaciones (25 sep 2026).
///
/// Pedido: "una pestaña interna en el maestro que me salga cuáles son los
/// cargos que sí existen, cuáles no, como para poder comparar... y para esos
/// mismos corregirlos o generar la asignación correspondiente, para no revisar
/// uno por uno". Aquí vive la lógica, sin Firestore, para que Web y Móvil
/// muestren lo mismo y se pueda probar.

/// Una regla efectiva del maestro, con el acta a la que pertenece.
class ReglaEfectiva {
  final String tipoActa;
  final InterventoriaMaestroSubsanacion fila;

  const ReglaEfectiva(this.tipoActa, this.fila);

  String get clave => claveRegla(tipoActa, fila.numeral);

  /// "Regular 2.14".
  String get etiqueta => '${etiquetaTipoActa(tipoActa)} ${fila.numeral}';
}

/// Lo que asigna hoy cada numeral de cada acta del maestro: la regla guardada
/// de la empresa o, en la regular, la matriz incluida.
List<ReglaEfectiva> maestroEfectivo(Map<String, dynamic> reglas) => [
  for (final tipo in kActasConMaestro)
    for (final fila in aplicarReglasSubsanacion(
      construirMaestroSubsanaciones(tipoActa: tipo),
      reglas,
      tipoActa: tipo,
    ))
      ReglaEfectiva(tipo, fila),
];

/// Regla efectiva por clave (`FAMILIA::numeral`).
Map<String, ReglaEfectiva> indiceMaestroEfectivo(Map<String, dynamic> reglas) =>
    {for (final r in maestroEfectivo(reglas)) r.clave: r};

// ── 1. Cargos del maestro ──────────────────────────────────────────────────

enum EstadoCargoMaestro {
  /// No está en TBL_CARGOS y nadie tiene un cargo que encaje.
  noExiste,

  /// Existe en el catálogo, pero ninguna persona activa lo tiene.
  sinPersonas,

  /// Lo tienen personas, pero ninguna recibe tareas: como responsable no
  /// resuelve a nadie.
  sinAsignables,

  ok,
}

String etiquetaEstadoCargo(EstadoCargoMaestro estado) => switch (estado) {
  EstadoCargoMaestro.noExiste => 'No existe',
  EstadoCargoMaestro.sinPersonas => 'Nadie lo tiene',
  EstadoCargoMaestro.sinAsignables => 'Nadie recibe tareas',
  EstadoCargoMaestro.ok => 'Existe',
};

class RevisionCargoMaestro {
  /// Cargo tal como está escrito en las reglas.
  final String cargo;

  /// El nombre exacto (sin tildes ni mayúsculas) está en TBL_CARGOS.
  final bool enCatalogo;

  /// Personas activas cuyo cargo encaja (misma regla que la asignación real,
  /// `afinidadCargo`).
  final List<InterventoriaUsuario> personas;

  /// De [personas], las que reciben tareas.
  final List<InterventoriaUsuario> asignables;

  /// Numerales donde responde ("Regular 2.14").
  final List<String> comoResponsable;

  /// Numerales donde aprueba.
  final List<String> comoAprobador;

  const RevisionCargoMaestro({
    required this.cargo,
    required this.enCatalogo,
    required this.personas,
    required this.asignables,
    required this.comoResponsable,
    required this.comoAprobador,
  });

  EstadoCargoMaestro get estado {
    if (personas.isEmpty) {
      return enCatalogo
          ? EstadoCargoMaestro.sinPersonas
          : EstadoCargoMaestro.noExiste;
    }
    if (comoResponsable.isNotEmpty && asignables.isEmpty) {
      return EstadoCargoMaestro.sinAsignables;
    }
    return EstadoCargoMaestro.ok;
  }

  bool get conProblema => estado != EstadoCargoMaestro.ok;

  int get usos => comoResponsable.length + comoAprobador.length;
}

/// Todos los cargos que nombra el maestro, con su estado. Primero los que no
/// resuelven a nadie; dentro de cada estado, los más usados.
List<RevisionCargoMaestro> revisarCargosDelMaestro({
  required Map<String, dynamic> reglas,
  required Iterable<String> cargosCatalogo,
  required List<InterventoriaUsuario> usuariosActivos,
  required List<InterventoriaUsuario> usuariosAsignables,
}) {
  final catalogo = cargosCatalogo.map(normalizarCargo).toSet();
  final asignablesIds = usuariosAsignables.map((u) => u.id).toSet();
  final nombre = <String, String>{};
  final resp = <String, List<String>>{};
  final aprob = <String, List<String>>{};
  for (final regla in maestroEfectivo(reglas)) {
    for (final cargo in regla.fila.responsables) {
      final clave = normalizarCargo(cargo);
      if (clave.isEmpty) continue;
      nombre.putIfAbsent(clave, () => cargo.trim());
      resp.putIfAbsent(clave, () => []).add(regla.etiqueta);
    }
    for (final cargo in regla.fila.aprobadores) {
      final clave = normalizarCargo(cargo);
      if (clave.isEmpty) continue;
      nombre.putIfAbsent(clave, () => cargo.trim());
      aprob.putIfAbsent(clave, () => []).add(regla.etiqueta);
    }
  }
  final out = <RevisionCargoMaestro>[];
  nombre.forEach((clave, cargo) {
    final personas = usuariosActivos
        .where((u) => afinidadCargo(cargo, u.cargo) != null)
        .toList();
    out.add(
      RevisionCargoMaestro(
        cargo: cargo,
        enCatalogo: catalogo.contains(clave),
        personas: personas,
        asignables: personas
            .where((u) => asignablesIds.contains(u.id))
            .toList(),
        comoResponsable: resp[clave] ?? const [],
        comoAprobador: aprob[clave] ?? const [],
      ),
    );
  });
  out.sort((a, b) {
    final porEstado = a.estado.index.compareTo(b.estado.index);
    if (porEstado != 0) return porEstado;
    final porUso = b.usos.compareTo(a.usos);
    if (porUso != 0) return porUso;
    return a.cargo.toLowerCase().compareTo(b.cargo.toLowerCase());
  });
  return out;
}

/// Reglas que cambian al reemplazar [cargoActual] por [cargoNuevo] en todo el
/// maestro, listas para guardar en `reglasSubsanacion` (mismo formato que
/// `InterventoriaService.guardarReglaSubsanacion`).
///
/// Recorre el maestro EFECTIVO: un numeral de la regular que todavía usa la
/// matriz incluida queda guardado como regla propia con el cargo corregido.
/// Si el cargo nuevo ya estaba en la misma regla no se repite.
Map<String, Map<String, dynamic>> reglasConCargoReemplazado({
  required Map<String, dynamic> reglas,
  required String cargoActual,
  required String cargoNuevo,
  required String actualizadoPor,
  required Object actualizadoEn,
}) {
  final objetivo = normalizarCargo(cargoActual);
  final nuevo = cargoNuevo.trim();
  if (objetivo.isEmpty || nuevo.isEmpty) return const {};
  if (normalizarCargo(nuevo) == objetivo && nuevo == cargoActual.trim()) {
    return const {};
  }

  List<String>? reemplazar(List<String> cargos) {
    if (!cargos.any((c) => normalizarCargo(c) == objetivo)) return null;
    final vistos = <String>{};
    final out = <String>[];
    for (final cargo in cargos) {
      final valor = normalizarCargo(cargo) == objetivo ? nuevo : cargo.trim();
      if (valor.isEmpty || !vistos.add(normalizarCargo(valor))) continue;
      out.add(valor);
    }
    return out;
  }

  final cambios = <String, Map<String, dynamic>>{};
  for (final regla in maestroEfectivo(reglas)) {
    final resp = reemplazar(regla.fila.responsables);
    final aprob = reemplazar(regla.fila.aprobadores);
    if (resp == null && aprob == null) continue;
    final responsables = resp ?? regla.fila.responsables;
    final aprobadores = aprob ?? regla.fila.aprobadores;
    cambios[regla.clave] = {
      'tipoActa': familiaReglasActa(regla.tipoActa),
      'numeral': normalizarNumeralActa(regla.fila.numeral),
      'responsables': responsables,
      'aprobadores': aprobadores,
      'responsable': responsables.isEmpty ? '' : responsables.first,
      'aprobador': aprobadores.isEmpty ? '' : aprobadores.first,
      'actualizadoPor': actualizadoPor,
      'actualizadoEn': actualizadoEn,
    };
  }
  return cambios;
}

// ── 2. Por establecimiento ─────────────────────────────────────────────────

enum CoberturaRol { enSede, fueraDeSede, nadie }

class ResolucionRolSede {
  final List<String> cargos;
  final InterventoriaPersona? persona;

  const ResolucionRolSede(this.cargos, this.persona);

  CoberturaRol get cobertura {
    final p = persona;
    if (p == null) return CoberturaRol.nadie;
    return p.delCentro ? CoberturaRol.enSede : CoberturaRol.fueraDeSede;
  }
}

/// Numerales que comparten los mismos cargos, resueltos en una sede.
class GrupoReglaSede {
  final ResolucionRolSede responsable;
  final ResolucionRolSede aprobador;
  final List<String> numerales;

  const GrupoReglaSede({
    required this.responsable,
    required this.aprobador,
    required this.numerales,
  });

  /// El hallazgo se queda sin tarea: falta responsable o aprobador.
  bool get bloquea =>
      responsable.cobertura == CoberturaRol.nadie ||
      aprobador.cobertura == CoberturaRol.nadie;

  /// Se asigna, pero la tarea sale del establecimiento. Normal en cargos
  /// corporativos; sospechoso en el administrador de la sede.
  bool get responsableFuera =>
      responsable.cobertura == CoberturaRol.fueraDeSede;
}

class RevisionSede {
  final CentroCostoRef centro;
  final List<GrupoReglaSede> grupos;

  const RevisionSede(this.centro, this.grupos);

  int get bloqueados => grupos.where((g) => g.bloquea).length;

  int get fueraDeSede =>
      grupos.where((g) => !g.bloquea && g.responsableFuera).length;
}

/// Para cada establecimiento, quién queda como responsable y aprobador de
/// cada grupo de reglas. Primero las sedes con más grupos sin resolver.
List<RevisionSede> revisarSedes({
  required Map<String, dynamic> reglas,
  required List<CentroCostoRef> centros,
  required List<InterventoriaUsuario> usuariosActivos,
  required List<InterventoriaUsuario> usuariosAsignables,
}) {
  // Reglas con los mismos cargos se resuelven igual en una sede: se agrupan
  // para no pintar cien filas idénticas.
  final grupos =
      <String, ({List<String> resp, List<String> aprob, List<String> nums})>{};
  for (final regla in maestroEfectivo(reglas)) {
    // Una regla sin cargos es un pendiente del maestro, no de la sede: se
    // cuenta una sola vez (ver [reglasSinCargos]). Antes marcaba a TODAS las
    // sedes con "152 numerales sin persona".
    if (regla.fila.incompleta) continue;
    final resp = regla.fila.responsables;
    final aprob = regla.fila.aprobadores;
    final firma =
        '${resp.map(normalizarCargo).join('|')}>>'
        '${aprob.map(normalizarCargo).join('|')}';
    grupos
        .putIfAbsent(firma, () => (resp: resp, aprob: aprob, nums: <String>[]))
        .nums
        .add(regla.etiqueta);
  }

  // Candidatos por cargo, calculados una vez: la afinidad es lo costoso.
  final candidatosActivos = <String, List<InterventoriaUsuario>>{};
  final candidatosAsignables = <String, List<InterventoriaUsuario>>{};
  List<InterventoriaUsuario> candidatos(
    List<String> cargos,
    List<InterventoriaUsuario> usuarios,
    Map<String, List<InterventoriaUsuario>> cache,
  ) {
    final ids = <String>{};
    final out = <InterventoriaUsuario>[];
    for (final cargo in cargos) {
      final lista = cache.putIfAbsent(
        normalizarCargo(cargo),
        () => usuarios
            .where((u) => afinidadCargo(cargo, u.cargo) != null)
            .toList(),
      );
      for (final u in lista) {
        if (ids.add(u.id)) out.add(u);
      }
    }
    return out;
  }

  final out = <RevisionSede>[];
  for (final centro in centros) {
    final filas = <GrupoReglaSede>[];
    for (final g in grupos.values) {
      final responsable = resolverPrimerCargoQueResuelva(
        g.resp,
        centro.centroId,
        candidatos(g.resp, usuariosAsignables, candidatosAsignables),
      );
      final aprobador = resolverPrimerCargoQueResuelva(
        g.aprob,
        centro.centroId,
        candidatos(g.aprob, usuariosActivos, candidatosActivos),
      );
      filas.add(
        GrupoReglaSede(
          responsable: ResolucionRolSede(g.resp, responsable),
          aprobador: ResolucionRolSede(g.aprob, aprobador),
          numerales: g.nums,
        ),
      );
    }
    filas.sort((a, b) {
      int peso(GrupoReglaSede g) =>
          g.bloquea ? 0 : (g.responsableFuera ? 1 : 2);
      final porPeso = peso(a).compareTo(peso(b));
      if (porPeso != 0) return porPeso;
      return b.numerales.length.compareTo(a.numerales.length);
    });
    out.add(RevisionSede(centro, filas));
  }
  out.sort((a, b) {
    final porBloqueo = b.bloqueados.compareTo(a.bloqueados);
    if (porBloqueo != 0) return porBloqueo;
    final porFuera = b.fueraDeSede.compareTo(a.fueraDeSede);
    if (porFuera != 0) return porFuera;
    return a.centro.nombre.toLowerCase().compareTo(
      b.centro.nombre.toLowerCase(),
    );
  });
  return out;
}

/// Reglas del maestro a las que les falta responsable o aprobador, por acta.
/// Las actas con catálogo propio nacen así hasta que alguien las llena.
Map<String, int> reglasSinCargos(Map<String, dynamic> reglas) {
  final out = <String, int>{};
  for (final regla in maestroEfectivo(reglas)) {
    if (!regla.fila.incompleta) continue;
    final acta = etiquetaTipoActa(regla.tipoActa);
    out[acta] = (out[acta] ?? 0) + 1;
  }
  return out;
}

// ── 2b. Cambiar quién responde en una sede ─────────────────────────────────
//
// La matriz dice QUÉ CARGO responde; la persona sale de quién tiene ese cargo
// y cubre la sede (centros de operación, de trabajo o grupo, lo que guarda
// Talento Humano). Cambiar a la persona de una sede es, entonces, cambiar esa
// cobertura: al elegido se le agrega la sede —o todo su grupo, que es el
// caso de un coordinador de calidad por grupo— y a quien la cubría con el
// mismo cargo se le quita.

enum AlcanceCobertura { sede, grupo }

/// Cambio de cobertura de una persona, en los campos de Talento Humano.
class CambioCobertura {
  final String userId;
  final String nombre;

  /// Se agregan a `centrosOperacionIds`.
  final Set<String> agregarCentros;

  /// Se quitan de `centrosOperacionIds` y de `centrosTrabajoIds`.
  final Set<String> quitarCentros;

  /// Se agregan a `gruposInterventoria`.
  final Set<String> agregarGrupos;

  const CambioCobertura({
    required this.userId,
    required this.nombre,
    this.agregarCentros = const {},
    this.quitarCentros = const {},
    this.agregarGrupos = const {},
  });

  bool get vacio =>
      agregarCentros.isEmpty && quitarCentros.isEmpty && agregarGrupos.isEmpty;
}

/// Centros de costo de cada grupo (`G1` → {centros}).
Map<String, Set<String>> centrosPorGrupo(Iterable<CentroCostoRef> centros) {
  final out = <String, Set<String>>{};
  for (final c in centros) {
    final grupo = normalizarGrupoCentroCosto(c.grupo);
    if (grupo.isEmpty) continue;
    out.putIfAbsent(grupo, () => <String>{}).add(c.centroId);
  }
  return out;
}

/// Personas que pueden encarnar alguno de [cargos], con la misma afinidad que
/// usa la asignación real. Primero quienes ya cubren [centroId].
List<InterventoriaUsuario> candidatosDeCargos(
  List<String> cargos,
  List<InterventoriaUsuario> usuarios, {
  String centroId = '',
}) {
  final out = usuarios
      .where((u) => cargos.any((c) => afinidadCargo(c, u.cargo) != null))
      .toList();
  out.sort((a, b) {
    final enA = a.cubreCentro(centroId) ? 0 : 1;
    final enB = b.cubreCentro(centroId) ? 0 : 1;
    if (enA != enB) return enA.compareTo(enB);
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return out;
}

/// Cómo cubre una persona una sede, para explicarlo en pantalla.
enum ViaCobertura { ninguna, centroDeCosto, explicita, grupo }

ViaCobertura viaCobertura(
  InterventoriaUsuario u,
  String centroId,
  Map<String, Set<String>> porGrupo,
) {
  if (!u.cubreCentro(centroId)) return ViaCobertura.ninguna;
  if (u.centrosOperacionIds.contains(centroId) ||
      u.centrosTrabajoIds.contains(centroId)) {
    return ViaCobertura.explicita;
  }
  if (u.grupos.any((g) => porGrupo[g]?.contains(centroId) ?? false)) {
    return ViaCobertura.grupo;
  }
  if (u.centrosAsignadosIds.isEmpty) return ViaCobertura.centroDeCosto;
  return ViaCobertura.explicita;
}

/// La persona con el cambio aplicado.
InterventoriaUsuario aplicarCambioCobertura(
  InterventoriaUsuario u,
  CambioCobertura cambio,
  Map<String, Set<String>> porGrupo,
) {
  if (cambio.userId != u.id || cambio.vacio) return u;
  final grupos = {...u.grupos, ...cambio.agregarGrupos};
  final porSusGrupos = {
    for (final g in grupos) ...(porGrupo[g] ?? const <String>{}),
  };
  final asignados = <String>{
    ...u.centrosAsignadosIds.where(
      (c) => !cambio.quitarCentros.contains(c) || porSusGrupos.contains(c),
    ),
    ...cambio.agregarCentros,
    ...porSusGrupos,
  };
  return u.copyWith(
    centrosAsignadosIds: asignados,
    centrosOperacionIds: {
      ...u.centrosOperacionIds.where((c) => !cambio.quitarCentros.contains(c)),
      ...cambio.agregarCentros,
    },
    centrosTrabajoIds: u.centrosTrabajoIds
        .where((c) => !cambio.quitarCentros.contains(c))
        .toSet(),
    grupos: grupos,
  );
}

class PlanCambioSede {
  final List<CambioCobertura> cambios;

  /// Lo que el cambio no puede resolver solo (alguien cubre la sede por su
  /// grupo o por su centro de costo).
  final List<String> avisos;

  /// Quién respondería en la sede después del cambio.
  final InterventoriaPersona? quedaria;

  const PlanCambioSede({
    required this.cambios,
    required this.avisos,
    required this.quedaria,
  });

  bool get quedaElegido => quedaria != null && quedaria!.delCentro;
}

/// Qué hay que cambiar para que [elegido] responda por [cargos] en [sede], y
/// quién quedaría. [usuarios] es la lista contra la que se resuelve ese rol:
/// asignables para el responsable, activos para el aprobador.
PlanCambioSede planearCambioEnSede({
  required CentroCostoRef sede,
  required List<String> cargos,
  required InterventoriaUsuario elegido,
  required AlcanceCobertura alcance,
  required List<InterventoriaUsuario> usuarios,
  required Map<String, Set<String>> porGrupo,
  bool quitarALosDemas = true,
}) {
  final centroId = sede.centroId;
  final grupo = normalizarGrupoCentroCosto(sede.grupo);
  final cambios = <CambioCobertura>[];
  final avisos = <String>[];

  if (alcance == AlcanceCobertura.grupo && grupo.isNotEmpty) {
    if (!elegido.grupos.contains(grupo)) {
      cambios.add(
        CambioCobertura(
          userId: elegido.id,
          nombre: elegido.nombre,
          agregarGrupos: {grupo},
        ),
      );
    }
  } else if (!elegido.centrosOperacionIds.contains(centroId) &&
      !elegido.centrosTrabajoIds.contains(centroId)) {
    cambios.add(
      CambioCobertura(
        userId: elegido.id,
        nombre: elegido.nombre,
        agregarCentros: {centroId},
      ),
    );
  }

  if (quitarALosDemas) {
    for (final otro in candidatosDeCargos(cargos, usuarios)) {
      if (otro.id == elegido.id) continue;
      switch (viaCobertura(otro, centroId, porGrupo)) {
        case ViaCobertura.explicita:
          cambios.add(
            CambioCobertura(
              userId: otro.id,
              nombre: otro.nombre,
              quitarCentros: {centroId},
            ),
          );
          final porSuGrupo = otro.grupos.where(
            (g) => porGrupo[g]?.contains(centroId) ?? false,
          );
          if (porSuGrupo.isNotEmpty) {
            avisos.add(
              '${otro.nombre} también cubre esta sede por el grupo '
              '${porSuGrupo.first}. Si no debe responder aquí, quítele el '
              'grupo en Talento Humano.',
            );
          }
        case ViaCobertura.grupo:
          final suyo = otro.grupos.firstWhere(
            (g) => porGrupo[g]?.contains(centroId) ?? false,
          );
          avisos.add(
            '${otro.nombre} también cubre esta sede por el grupo $suyo. Si no '
            'debe responder aquí, quítele el grupo en Talento Humano.',
          );
        case ViaCobertura.centroDeCosto:
          avisos.add(
            '${otro.nombre} tiene esta sede como centro de costo. Deja de '
            'contar en cuanto Talento Humano le asigne sus centros de '
            'operación o trabajo.',
          );
        case ViaCobertura.ninguna:
          break;
      }
    }
  }

  final simulados = [
    for (final u in usuarios)
      cambios.fold(u, (acc, c) => aplicarCambioCobertura(acc, c, porGrupo)),
  ];
  final quedaria = resolverPrimerCargoQueResuelva(
    cargos,
    centroId,
    candidatosDeCargos(cargos, simulados),
  );
  return PlanCambioSede(cambios: cambios, avisos: avisos, quedaria: quedaria);
}

// ── 3. Hallazgos sin tarea ─────────────────────────────────────────────────

enum MotivoSinAsignar {
  sinNumeral,
  reglaIncompleta,
  sinResponsable,
  sinAprobador,
}

String etiquetaMotivoSinAsignar(MotivoSinAsignar motivo) => switch (motivo) {
  MotivoSinAsignar.sinNumeral => 'Numeral no reconocido',
  MotivoSinAsignar.reglaIncompleta => 'Regla sin cargos en el maestro',
  MotivoSinAsignar.sinResponsable => 'Nadie con el cargo responsable',
  MotivoSinAsignar.sinAprobador => 'Nadie con el cargo aprobador',
};

class PrevisionAsignacionPendiente {
  /// Hallazgos sin tarea que siguen abiertos.
  final int total;

  /// Los que el maestro puede asignar hoy (responsable y aprobador).
  final int asignables;

  final Map<MotivoSinAsignar, int> porMotivo;

  /// Cargo que falta → cuántos hallazgos detiene.
  final Map<String, int> cargosQueFaltan;

  /// Sede → hallazgos que se pueden asignar ahí.
  final Map<String, int> asignablesPorSede;

  const PrevisionAsignacionPendiente({
    required this.total,
    required this.asignables,
    required this.porMotivo,
    required this.cargosQueFaltan,
    required this.asignablesPorSede,
  });

  int get bloqueados => total - asignables;
}

/// Hallazgos que la asignación en lote va a considerar.
bool esHallazgoPendienteDeTarea(InterventoriaHallazgo h) =>
    h.tareaId.trim().isEmpty && debeAparecerEnTableroAsignacion(h);

/// Cuántos hallazgos sin tarea se asignarían al generar el rezago y por qué
/// se quedan los demás. Usa las mismas reglas que la asignación real.
///
/// Un hallazgo sin responsable por el maestro todavía puede ir al director de
/// su área si alguien la eligió a mano; aquí se cuenta como detenido, que es
/// lo prudente para una vista previa.
PrevisionAsignacionPendiente preverAsignacionPendiente({
  required Iterable<InterventoriaHallazgo> hallazgos,
  required Map<String, dynamic> reglas,
  required List<InterventoriaUsuario> usuariosActivos,
  required List<InterventoriaUsuario> usuariosAsignables,
}) {
  final indice = indiceMaestroEfectivo(reglas);
  var total = 0;
  var asignables = 0;
  final motivos = <MotivoSinAsignar, int>{};
  final faltan = <String, int>{};
  final porSede = <String, int>{};
  for (final h in hallazgos) {
    if (!esHallazgoPendienteDeTarea(h)) continue;
    total++;
    final numeral = h.numeralParaMatriz;
    final regla = numeral.isEmpty
        ? null
        : indice[claveRegla(h.tipoActa ?? kActaRegular, numeral)];
    if (regla == null) {
      motivos.update(
        MotivoSinAsignar.sinNumeral,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    // Las actas con catálogo propio nacen sin cargos: hasta que alguien llene
    // la regla en el maestro, sus hallazgos no tienen a quién ir.
    if (regla.fila.incompleta) {
      motivos.update(
        MotivoSinAsignar.reglaIncompleta,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      faltan.update(
        'Regla ${regla.etiqueta} sin cargos',
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    final responsable = resolverPrimerCargoQueResuelva(
      regla.fila.responsables,
      h.centroCostoId,
      usuariosAsignables,
    );
    final aprobador = resolverPrimerCargoQueResuelva(
      regla.fila.aprobadores,
      h.centroCostoId,
      usuariosActivos,
    );
    if (responsable == null) {
      motivos.update(
        MotivoSinAsignar.sinResponsable,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      faltan.update(
        regla.fila.responsables.join(' · '),
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    if (aprobador == null) {
      motivos.update(
        MotivoSinAsignar.sinAprobador,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      faltan.update(
        regla.fila.aprobadores.join(' · '),
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    asignables++;
    final sede = h.centroCostoNombre.trim().isEmpty
        ? 'Sin sede'
        : h.centroCostoNombre.trim();
    porSede.update(sede, (v) => v + 1, ifAbsent: () => 1);
  }
  return PrevisionAsignacionPendiente(
    total: total,
    asignables: asignables,
    porMotivo: motivos,
    cargosQueFaltan: faltan,
    asignablesPorSede: porSede,
  );
}
