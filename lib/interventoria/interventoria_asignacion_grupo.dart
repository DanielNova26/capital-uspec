import 'interventoria_models.dart';
import 'interventoria_service.dart';

/// Asignar por grupo los hallazgos sin asignar (21 oct 2026).
///
/// Pedido: en «Sin asignar», cuando el maestro pide un cargo que no se
/// encuentra, que se vea cuál es y que se pueda poner a mano a quien sí
/// corresponde, eligiendo un grupo de Interventoría (G1, G9…) y a una persona
/// de ese grupo. Solo se llenan los huecos: donde el maestro sí resuelve
/// (responsable dentro de la sede, aprobador único) se respeta.
///
/// Aquí vive la lógica, sin Firestore ni widgets, para que Web y Móvil
/// propongan lo mismo y se pueda probar.

/// Qué resuelve el maestro para un hallazgo sin asignar.
class HuecoAsignacion {
  final InterventoriaHallazgo hallazgo;

  /// Responsable del maestro DENTRO del establecimiento; null = hueco.
  final InterventoriaPersona? responsable;
  final List<String> cargosResponsable;
  final ResolucionAprobadorMaestro aprobador;

  const HuecoAsignacion({
    required this.hallazgo,
    required this.responsable,
    required this.cargosResponsable,
    required this.aprobador,
  });

  bool get faltaResponsable => responsable == null;
  bool get faltaAprobador => aprobador.persona == null;
  bool get tieneHueco => faltaResponsable || faltaAprobador;
}

/// Hallazgos de un grupo a los que les falta lo mismo (los mismos cargos del
/// maestro para el mismo rol). Solo a ellos se les puede poner la misma
/// persona: un lote mezclado mandaría a un administrador hallazgos de
/// Calidad.
class LoteGrupo {
  final String grupo;
  final bool faltaResponsable;
  final bool faltaAprobador;
  final List<String> cargosResponsable;
  final List<String> cargosAprobador;
  final List<HuecoAsignacion> huecos;

  const LoteGrupo({
    required this.grupo,
    required this.faltaResponsable,
    required this.faltaAprobador,
    required this.cargosResponsable,
    required this.cargosAprobador,
    required this.huecos,
  });

  int get sedes => {for (final h in huecos) h.hallazgo.centroCostoId}.length;

  static String _cargos(List<String> cargos) =>
      cargos.isEmpty ? 'sin cargo en el maestro' : cargos.join(' o ');

  /// "Falta aprobador: Director de operaciones".
  String get titulo => [
    if (faltaResponsable) 'Falta responsable: ${_cargos(cargosResponsable)}',
    if (faltaAprobador) 'Falta aprobador: ${_cargos(cargosAprobador)}',
  ].join(' · ');
}

/// Grupo normalizado de un hallazgo: el suyo o el de su establecimiento.
Set<String> gruposDeHallazgo(
  InterventoriaHallazgo h,
  Map<String, Set<String>> centrosPorGrupo,
) => {
  if (normalizarGrupoCentroCosto(h.grupoId).isNotEmpty)
    normalizarGrupoCentroCosto(h.grupoId),
  for (final e in centrosPorGrupo.entries)
    if (e.value.contains(h.centroCostoId.trim())) e.key,
};

/// Lo que resuelve el maestro para cada hallazgo, con la misma lógica que la
/// tarjeta, «Asignar por el maestro» y la sincronización de Admin.
HuecoAsignacion huecoDe(
  InterventoriaHallazgo h, {
  required InterventoriaService service,
  required List<InterventoriaUsuario> asignables,
  required List<InterventoriaUsuario> activos,
  required Map<String, dynamic> reglas,
}) {
  final sinNumeral = h.numeralParaMatriz.isEmpty;
  final responsable = sinNumeral
      ? null
      : service.sugerirResponsable(h, asignables, reglas: reglas);
  return HuecoAsignacion(
    hallazgo: h,
    responsable: responsable != null && responsable.delCentro
        ? responsable
        : null,
    cargosResponsable: sinNumeral
        ? const []
        : service.cargosResponsablesDe(h, reglas),
    aprobador: service.resolucionAprobador(h, activos, reglas: reglas),
  );
}

/// Lotes de un grupo: los hallazgos sin asignar del grupo con algún hueco,
/// juntos cuando les falta lo mismo. Los más grandes primero.
List<LoteGrupo> lotesDelGrupo(
  String grupo,
  Iterable<HuecoAsignacion> huecos,
  Map<String, Set<String>> centrosPorGrupo,
) {
  final g = normalizarGrupoCentroCosto(grupo);
  final porClave = <String, List<HuecoAsignacion>>{};
  for (final h in huecos) {
    if (!h.tieneHueco) continue;
    if (!gruposDeHallazgo(h.hallazgo, centrosPorGrupo).contains(g)) continue;
    final clave =
        '${h.faltaResponsable ? h.cargosResponsable.join('|') : '-'}'
        '#${h.faltaAprobador ? h.aprobador.cargos.join('|') : '-'}';
    porClave.putIfAbsent(clave, () => []).add(h);
  }
  final lotes = [
    for (final lista in porClave.values)
      LoteGrupo(
        grupo: g,
        faltaResponsable: lista.first.faltaResponsable,
        faltaAprobador: lista.first.faltaAprobador,
        cargosResponsable: lista.first.cargosResponsable,
        cargosAprobador: lista.first.aprobador.cargos,
        huecos: lista,
      ),
  ];
  lotes.sort((a, b) => b.huecos.length.compareTo(a.huecos.length));
  return lotes;
}

/// Grupos con hallazgos sin asignar que tienen algún hueco, con su cantidad.
Map<String, int> gruposConHuecos(
  Iterable<HuecoAsignacion> huecos,
  Map<String, Set<String>> centrosPorGrupo,
) {
  final out = <String, int>{};
  for (final h in huecos) {
    if (!h.tieneHueco) continue;
    for (final g in gruposDeHallazgo(h.hallazgo, centrosPorGrupo)) {
      out[g] = (out[g] ?? 0) + 1;
    }
  }
  return Map.fromEntries(
    out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Persona del grupo propuesta para un rol, y si cumple el cargo pedido.
typedef CandidatoGrupo = ({InterventoriaUsuario usuario, bool cumpleCargo});

/// Personas que cubren el grupo: lo tienen asignado o atienden alguno de sus
/// establecimientos (incluye a quien atiende todas las sedes). Primero quienes
/// tienen el cargo que pide el maestro, después el resto del grupo por nombre.
/// Con [todaLaEmpresa] se listan todos, por si quien responde no está en el
/// grupo.
List<CandidatoGrupo> candidatosDelGrupo(
  String grupo,
  List<String> cargos,
  List<InterventoriaUsuario> usuarios,
  Map<String, Set<String>> centrosPorGrupo, {
  bool todaLaEmpresa = false,
}) {
  final g = normalizarGrupoCentroCosto(grupo);
  final centros = centrosPorGrupo[g] ?? const <String>{};
  final out = <CandidatoGrupo>[
    for (final u in usuarios)
      if (todaLaEmpresa || u.grupos.contains(g) || centros.any(u.cubreCentro))
        (
          usuario: u,
          cumpleCargo: cargos.any((c) => afinidadCargo(c, u.cargo) != null),
        ),
  ];
  out.sort((a, b) {
    if (a.cumpleCargo != b.cumpleCargo) return a.cumpleCargo ? -1 : 1;
    return a.usuario.nombre.toLowerCase().compareTo(
      b.usuario.nombre.toLowerCase(),
    );
  });
  return out;
}

/// Quién queda en cada hallazgo de un lote: el maestro donde resuelve, la
/// persona elegida en los huecos. Un hallazgo cuyo responsable y aprobador
/// serían la misma persona se deja fuera, con el motivo.
typedef AsignacionGrupo = ({
  HuecoAsignacion hueco,
  InterventoriaPersona responsable,

  /// null = el del maestro (se resuelve al crear la tarea, origen maestro).
  InterventoriaPersona? aprobadorElegido,
  String aprobadorNombre,
});

({List<AsignacionGrupo> asignar, List<String> omitidos}) planAsignacionGrupo(
  LoteGrupo lote, {
  InterventoriaUsuario? responsable,
  InterventoriaUsuario? aprobador,
}) {
  InterventoriaPersona persona(InterventoriaUsuario u, String centro) =>
      InterventoriaPersona(
        id: u.id,
        nombre: u.nombre,
        cargo: u.cargo,
        cargoMatriz: '',
        delCentro: u.cubreCentro(centro),
      );
  final asignar = <AsignacionGrupo>[];
  final omitidos = <String>[];
  for (final h in lote.huecos) {
    final centro = h.hallazgo.centroCostoId;
    final resp =
        h.responsable ??
        (responsable == null ? null : persona(responsable, centro));
    final aprobElegido = h.faltaAprobador && aprobador != null
        ? persona(aprobador, centro)
        : null;
    final aprob = aprobElegido ?? h.aprobador.persona;
    final etiqueta =
        '${h.hallazgo.establecimiento} '
                '${h.hallazgo.numeralParaMatriz}'
            .trim();
    if (resp == null || aprob == null) {
      omitidos.add('$etiqueta: falta elegir quién responde o aprueba.');
      continue;
    }
    if (resp.id == aprob.id) {
      omitidos.add(
        '$etiqueta: ${resp.nombre} quedaría respondiendo y aprobando.',
      );
      continue;
    }
    asignar.add((
      hueco: h,
      responsable: resp,
      aprobadorElegido: aprobElegido,
      aprobadorNombre: aprob.nombre,
    ));
  }
  return (asignar: asignar, omitidos: omitidos);
}
