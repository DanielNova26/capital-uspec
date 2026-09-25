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
