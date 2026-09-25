// lib/gerencia/gerencia_areas.dart
//
// De dónde sale el área que Gerencia muestra, filtra y grafica.
//
// Pedido del 25 sep 2026: "el área no conecta con los filtros". Los hallazgos
// que se asignan a una PERSONA por la matriz de numerales nunca guardan
// `areaId` ni `dptoEncargado` (esos campos solo los llena la asignación por
// área, que ya casi no se usa), así que casi todos caían en "Sin área" y al
// elegir un área en el filtro no salía nada. En el tablero de tareas pasaba lo
// mismo: la tarea que nace de un hallazgo hereda ese `areaId` vacío.
//
// La regla acordada, en este orden:
//  1. El área es la del **responsable ya asignado**.
//  2. Si su área no se conoce, el área que se le haya asignado a mano al
//     registro (asignación por área de las versiones anteriores).
//  3. Si no está asignado, la del responsable que **la matriz asigna** (el
//     mismo cálculo con el que el tablero de Interventoría sugiere a quién
//     mandarlo).
//
// Nada de esto se escribe en Firestore: Gerencia es de solo lectura y el área
// se recalcula en cada lectura. Si alguien cambia de área o se reasigna el
// hallazgo, el informe lo refleja sin migraciones.

import '../core/area_directory.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart'
    show puedeUsarDatosRaizInterventoria;
import '../utils/user_company.dart';

/// Área de cada cargo de una empresa, leída de `TBL_CARGOS`.
///
/// La mayoría del personal no tiene `areaId` en su ficha: el área vive en el
/// cargo. Se indexa por nombre normalizado y por id porque unos usuarios
/// guardan el nombre del cargo y otros la referencia (`cargoId`).
class AreasPorCargo {
  final Map<String, String> _porClave;

  const AreasPorCargo([this._porClave = const {}]);

  factory AreasPorCargo.desde(
    Iterable<({String id, Map<String, dynamic> data})> cargos,
  ) {
    final mapa = <String, String>{};
    for (final cargo in cargos) {
      final data = cargo.data;
      // Los cargos de Gestión de Cargos solo guardan el nombre del área.
      final area = [data['areaId'], data['areaNombre'], data['area']]
          .map((v) => (v ?? '').toString().trim())
          .firstWhere((v) => v.isNotEmpty, orElse: () => '');
      if (area.isEmpty) continue;
      for (final ref in [cargo.id, data['cargoId'], data['nombre']]) {
        final clave = areaClave((ref ?? '').toString());
        if (clave.isNotEmpty) mapa.putIfAbsent(clave, () => area);
      }
    }
    return AreasPorCargo(mapa);
  }

  bool get isEmpty => _porClave.isEmpty;

  /// Área del cargo [cargoONombre] (id o nombre); vacío si no la declara.
  String areaDe(String cargoONombre) =>
      _porClave[areaClave(cargoONombre)] ?? '';
}

const _kClavesArea = [
  'areaId',
  'area_id',
  'departamentoId',
  'area',
  'areaNombre',
  'departamento',
];
const _kClavesCargo = ['cargoId', 'cargo', 'cargoNombre'];

/// Área de una persona dentro de una empresa (id del catálogo o nombre).
///
/// Manda la ficha de esa empresa (`empresasDetalle[empresaId]`); los campos
/// de la raíz solo cuentan si describen a esa empresa, con el mismo criterio
/// que Interventoría usa para el cargo. Si la ficha no trae área, la del
/// cargo. Vacío si no hay forma de saberla.
String areaDeUsuario(
  Map<String, dynamic>? usuario,
  String empresaId, {
  AreasPorCargo cargos = const AreasPorCargo(),
}) {
  if (usuario == null) return '';
  final empresa = empresaId.trim();
  final scoped = getUserCompanyDetail(usuario, empresa) ?? const {};
  final raiz =
      empresa.isEmpty || puedeUsarDatosRaizInterventoria(usuario, empresa)
      ? usuario
      : const <String, dynamic>{};

  String primero(Map<String, dynamic> fuente, List<String> claves) {
    for (final clave in claves) {
      final v = (fuente[clave] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  for (final fuente in [scoped, raiz]) {
    final propia = primero(fuente, _kClavesArea);
    if (propia.isNotEmpty) return propia;
  }
  for (final fuente in [scoped, raiz]) {
    for (final clave in _kClavesCargo) {
      final cargo = (fuente[clave] ?? '').toString().trim();
      if (cargo.isEmpty) continue;
      final area = cargos.areaDe(cargo);
      if (area.isNotEmpty) return area;
    }
  }
  return '';
}

/// De dónde salió el área de un registro. Sirve para explicarlo en pantalla
/// y para las pruebas; el filtro no distingue.
enum OrigenArea { responsable, asignada, sugerido, ninguna }

class AreaResuelta {
  /// Id de catálogo o nombre del área; vacío = sin área.
  final String ref;
  final OrigenArea origen;

  const AreaResuelta(this.ref, this.origen);

  static const ninguna = AreaResuelta('', OrigenArea.ninguna);
}

/// Área de un hallazgo para Gerencia (ver la regla al inicio del archivo).
///
/// [responsableSugerido] se evalúa solo si hace falta: resolver la matriz
/// recorre todo el personal y la mayoría de hallazgos no lo necesita.
AreaResuelta areaDeHallazgo(
  InterventoriaHallazgo h, {
  required String Function(String personaId) areaDePersona,
  String Function()? responsableSugerido,
}) {
  final responsable = h.responsableId.trim();
  if (responsable.isNotEmpty) {
    final area = areaDePersona(responsable).trim();
    if (area.isNotEmpty) return AreaResuelta(area, OrigenArea.responsable);
  }
  final guardada = h.areaId.trim().isNotEmpty
      ? h.areaId.trim()
      : h.dptoEncargado.trim();
  if (guardada.isNotEmpty) return AreaResuelta(guardada, OrigenArea.asignada);
  final sugerido = (responsableSugerido?.call() ?? '').trim();
  if (sugerido.isNotEmpty) {
    final area = areaDePersona(sugerido).trim();
    if (area.isNotEmpty) return AreaResuelta(area, OrigenArea.sugerido);
  }
  return AreaResuelta.ninguna;
}

/// Área de una tarea: la de la persona a la que está asignada y, si no se
/// conoce, la que quedó guardada en la tarea.
String areaDeTarea(
  Map<String, dynamic> tarea, {
  required String Function(String uid) areaDePersona,
}) {
  final uid = (tarea['asignado_uid'] ?? tarea['asignadoUid'] ?? '')
      .toString()
      .trim();
  if (uid.isNotEmpty) {
    final area = areaDePersona(uid).trim();
    if (area.isNotEmpty) return area;
  }
  for (final clave in const ['areaId', 'areaNombre']) {
    final v = (tarea[clave] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// Opciones del filtro de área, como (clave, nombre).
///
/// Son el catálogo de la empresa más las áreas que aparecen en los datos y no
/// están en él (un área reconstruida desde el id del cargo, "Sin área"): si
/// una barra muestra un área, el filtro tiene que poder elegirla. La clave es
/// el nombre normalizado ([areaClave]) y se compara contra el nombre legible
/// del registro, así no importa con qué variante del id quedó guardada.
List<({String clave, String nombre})> opcionesFiltroArea(
  AreaCatalogo catalogo,
  Iterable<String> nombresEnDatos,
) {
  final porClave = <String, String>{};
  for (final opcion in catalogo.opciones) {
    final clave = areaClave(opcion.nombre);
    if (clave.isNotEmpty) porClave.putIfAbsent(clave, () => opcion.nombre);
  }
  for (final nombre in nombresEnDatos) {
    final clave = areaClave(nombre);
    if (clave.isNotEmpty) porClave.putIfAbsent(clave, () => nombre.trim());
  }
  final sinArea = areaClave('Sin área');
  final lista = [
    for (final e in porClave.entries) (clave: e.key, nombre: e.value),
  ];
  lista.sort((a, b) {
    // "Sin área" al final: es lo que queda por resolver, no un área más.
    if (a.clave == sinArea) return 1;
    if (b.clave == sinArea) return -1;
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return lista;
}
