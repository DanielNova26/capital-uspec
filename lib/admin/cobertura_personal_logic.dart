import '../interventoria/interventoria_revision_maestro.dart';
import '../interventoria/interventoria_service.dart';

/// Situación de la cobertura de una persona frente a Interventoría.
enum EstadoCobertura {
  /// Tiene grupos marcados pero su cargo no los usa (administradores por
  /// sede): no le suman sedes. Conviene quitarlos para que no confundan.
  gruposSinEfecto,

  /// No tiene centros de operación ni de trabajo: hoy solo cubre su centro de
  /// costos administrativo (o nada). Conviene fijarlo de forma explícita.
  soloCentroDeCostos,

  /// Ni centros propios, ni grupos, ni centro de costos: no cubre ninguna
  /// sede y nunca recibirá hallazgos.
  sinCobertura,

  /// Marcada como "atiende todas las sedes" (tesorero, director de
  /// operaciones…): responde cuando la sede no tiene titular propio.
  todasLasSedes,

  /// Cobertura propia clara (con o sin grupos que su cargo sí usa).
  correcta;

  String get etiqueta => switch (this) {
    gruposSinEfecto => 'Grupos que su cargo no usa',
    soloCentroDeCostos => 'Solo centro de costos',
    sinCobertura => 'Sin ninguna sede',
    todasLasSedes => 'Todas las sedes',
    correcta => 'Correcta',
  };

  bool get requiereAtencion => this != correcta && this != todasLasSedes;
}

/// Diagnóstico de una persona, con lo necesario para decidir y para actuar.
class PersonaCobertura {
  const PersonaCobertura({
    required this.usuario,
    required this.estado,
    required this.propios,
    required this.porGrupo,
  });

  final InterventoriaUsuario usuario;
  final EstadoCobertura estado;

  /// Centros de operación y de trabajo cargados a la persona.
  final Set<String> propios;

  /// Sedes que suma por sus grupos (cuando su cargo los usa).
  final Set<String> porGrupo;

  bool get puedeQuitarGrupos =>
      usuario.grupos.isNotEmpty && estado == EstadoCobertura.gruposSinEfecto;

  bool get puedeFijarCentroDeCostos =>
      usuario.centroId.trim().isNotEmpty &&
      propios.isEmpty &&
      (estado == EstadoCobertura.gruposSinEfecto ||
          estado == EstadoCobertura.soloCentroDeCostos);
}

PersonaCobertura diagnosticarCobertura(InterventoriaUsuario u) {
  final propios = {...u.centrosOperacionIds, ...u.centrosTrabajoIds};
  final porGrupo = u.centrosAsignadosIds.difference(propios);
  final EstadoCobertura estado;
  if (u.cubreTodas) {
    estado = EstadoCobertura.todasLasSedes;
  } else if (u.gruposIgnorados) {
    estado = EstadoCobertura.gruposSinEfecto;
  } else if (u.centrosAsignadosIds.isEmpty && u.centroId.trim().isEmpty) {
    estado = EstadoCobertura.sinCobertura;
  } else if (propios.isEmpty && porGrupo.isEmpty) {
    estado = EstadoCobertura.soloCentroDeCostos;
  } else {
    estado = EstadoCobertura.correcta;
  }
  return PersonaCobertura(
    usuario: u,
    estado: estado,
    propios: propios,
    porGrupo: porGrupo,
  );
}

/// Quita los grupos de las personas cuyo cargo no los usa.
List<CambioCobertura> cambiosQuitarGrupos(
  Iterable<PersonaCobertura> personas,
) => [
  for (final p in personas)
    if (p.puedeQuitarGrupos)
      CambioCobertura(
        userId: p.usuario.id,
        nombre: p.usuario.nombre,
        quitarGrupos: p.usuario.grupos,
      ),
];

/// Fija el centro de costos como centro de operación de quien no tiene
/// cobertura propia, para que la sede quede explícita en Talento Humano.
List<CambioCobertura> cambiosFijarCentroDeCostos(
  Iterable<PersonaCobertura> personas,
) => [
  for (final p in personas)
    if (p.puedeFijarCentroDeCostos)
      CambioCobertura(
        userId: p.usuario.id,
        nombre: p.usuario.nombre,
        agregarCentros: {p.usuario.centroId.trim()},
      ),
];
