import '../utils/user_company.dart';
import 'area_directory.dart';

/// Directorio de destino: los mismos identificadores para los filtros y las
/// personas, incluso cuando la ficha histórica solo guarda nombres.
class TaskReassignmentDirectory {
  final AreaCatalogo areas;
  final List<Map<String, String>> cargos;
  final List<Map<String, String>> usuarios;

  TaskReassignmentDirectory._(this.areas, this.cargos, this.usuarios);

  factory TaskReassignmentDirectory.desdeDatos({
    required String empresaId,
    required Map<String, Map<String, dynamic>> usuarios,
    required Map<String, Map<String, dynamic>> cargos,
    required Map<String, Map<String, dynamic>> areas,
    Map<String, Map<String, dynamic>> estructuras = const {},
    Map<String, String> centroAliases = const {},
  }) {
    final catalogo = AreaCatalogo.desde([
      for (final e in areas.entries)
        if ((e.value['empresaId'] ?? empresaId) == empresaId)
          for (final id in {e.key, (e.value['areaId'] ?? e.key).toString()})
            (
              id: id,
              nombre: (e.value['nombre'] ?? e.value['area'])?.toString(),
            ),
    ], empresaId: empresaId);
    String areaDe(String id, [String nombre = '']) {
      for (final a in catalogo.opciones) {
        if (a.contiene(id) || a.contiene(nombre)) return a.id;
      }
      return id.trim();
    }

    final puestos = <String, Map<String, String>>{};
    final porAlias = <String, String>{};
    final datosCargo = <String, Map<String, dynamic>>{};
    for (final e in cargos.entries) {
      final m = e.value;
      if ((m['empresaId'] ?? empresaId) != empresaId) continue;
      final id = (m['cargoId'] ?? e.key).toString().trim();
      if (id.isEmpty) continue;
      puestos[id] = {
        'id': id,
        'nombre': (m['nombre'] ?? m['descripcion'] ?? id).toString().trim(),
        'areaId': areaDe(
          (m['areaId'] ?? '').toString(),
          (m['areaNombre'] ?? m['area'] ?? '').toString(),
        ),
      };
      porAlias[e.key] = id;
      porAlias[id] = id;
      datosCargo[id] = m;
    }
    final personas = <Map<String, String>>[];
    for (final e in usuarios.entries) {
      final m = e.value;
      if (!matchesEmpresaScope(
            m,
            empresaId,
            allowLegacyWithoutEmpresa: false,
          ) ||
          !personaHabilitadaEn(
            m,
            empresaId,
            estructura:
                estructuras[(m['cedula'] ?? e.key).toString()] ??
                estructuras[e.key],
          )) {
        continue;
      }
      String dato(List<String> keys) =>
          resolveScopedStringWithFallbacks(m, empresaId, keys, keys).trim();
      var area = areaDe(
        dato(const ['areaId', 'area_id', 'departamentoId', 'departamento_id']),
        dato(const ['area', 'areaNombre', 'area_nombre', 'departamento']),
      );
      final rawCargo = dato(const ['cargoId', 'cargo_id']);
      final nombreCargo = dato(const [
        'cargo',
        'cargoNombre',
        'cargo_nombre',
        'puesto',
      ]);
      var cargoId = porAlias[rawCargo];
      if (cargoId == null && (nombreCargo.isNotEmpty || rawCargo.isNotEmpty)) {
        final clave = areaClave(nombreCargo.isEmpty ? rawCargo : nombreCargo);
        final areaConocida = catalogo.opciones.any((a) => a.contiene(area));
        final coincidencias = puestos.values
            .where(
              (c) =>
                  datosCargo.containsKey(c['id']) &&
                  areaClave(c['nombre']!) == clave &&
                  (!areaConocida || c['areaId'] == area),
            )
            .toList();
        // Un nombre ambiguo nunca toma arbitrariamente el área de otro puesto.
        if (coincidencias.length == 1) cargoId = coincidencias.single['id'];
      }
      if (!recibeAsignacionesEnEmpresa(
        m,
        empresaId,
        marcaDelCargo: datosCargo[cargoId] == null
            ? null
            : cargoRecibeAsignaciones(datosCargo[cargoId]!),
      )) {
        continue;
      }
      final cargo = puestos[cargoId];
      if (area.isEmpty || !catalogo.opciones.any((a) => a.contiene(area))) {
        area = cargo?['areaId'] ?? area;
      }
      final cargoNombre = cargo?['nombre'] ?? nombreCargo;
      cargoId ??= rawCargo.isNotEmpty
          ? rawCargo
          : (nombreCargo.isEmpty
                ? ''
                : 'nombre:${areaClave(nombreCargo)}:$area');
      // Las fichas con un cargo todavía ausente del maestro siguen filtrables.
      if (cargoId.isNotEmpty) {
        final key = cargoId;
        puestos.putIfAbsent(
          key,
          () => {
            'id': key,
            'nombre': cargoNombre.isEmpty ? key : cargoNombre,
            'areaId': area,
          },
        );
      }
      final detalle = getUserCompanyDetail(m, empresaId);
      Object? centro(String key) => detalle?.containsKey(key) == true
          ? detalle![key]
          : (raizEsDeEmpresa(m, empresaId) ? m[key] : null);
      final cobertura = <String>{};
      for (final key in const ['centrosTrabajoIds', 'centrosOperacionIds']) {
        final raw = centro(key);
        if (raw is Iterable && raw is! String) {
          cobertura.addAll(
            raw.map((v) => v.toString().trim()).where((v) => v.isNotEmpty),
          );
        }
      }
      for (final key in const ['centroTrabajoId', 'centroOperacionId']) {
        final id = (centro(key) ?? '').toString().trim();
        if (id.isNotEmpty) cobertura.add(id);
      }
      if (cobertura.isEmpty) {
        final id = dato(const ['centroId']);
        if (id.isNotEmpty && id != 'global') cobertura.add(id);
      }
      final nombre = [
        (m['nombres'] ?? m['primerNombre'] ?? '').toString(),
        (m['apellidos'] ?? m['primerApellido'] ?? '').toString(),
      ].where((v) => v.trim().isNotEmpty).join(' ').trim();
      personas.add({
        'id': e.key,
        'nombre': nombre.isEmpty ? e.key : nombre,
        'areaId': area,
        'areaNombre': area.isEmpty
            ? ''
            : catalogo.nombreDe(area, empresaId: empresaId),
        'cargoId': cargoId,
        'cargo': cargoNombre,
        'centrosCobertura': cobertura
            .map((id) => centroAliases[id] ?? id)
            .join('|'),
      });
    }
    return TaskReassignmentDirectory._(
      catalogo,
      puestos.values.toList(),
      personas,
    );
  }

  List<Map<String, String>> filtrar({
    String areaId = '',
    String cargoId = '',
    String centroId = '',
    String busqueda = '',
    Set<String> excluir = const {},
  }) {
    final query = areaClave(busqueda);
    return usuarios
        .where(
          (u) =>
              !excluir.contains(u['id']) &&
              areas.coincide(filtro: areaId, valor: u['areaId'], todas: '') &&
              (cargoId.isEmpty || u['cargoId'] == cargoId) &&
              (centroId.isEmpty ||
                  u['centrosCobertura']!.split('|').contains(centroId)) &&
              (query.isEmpty ||
                  areaClave(
                    [
                      u['nombre'],
                      u['id'],
                      u['cargo'],
                      u['areaNombre'],
                    ].join(' '),
                  ).contains(query)),
        )
        .toList()
      ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));
  }
}
