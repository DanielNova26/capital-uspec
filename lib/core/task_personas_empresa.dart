// lib/core/task_personas_empresa.dart
//
// Área y cargo de cada persona en la empresa activa, para los filtros de
// Tareas (3 oct 2026).
//
// "Mis tareas" agrupa y filtra por el área de QUIEN ASIGNÓ, y "Tareas que
// asigné" filtra por el cargo del responsable. Ninguno de los dos datos viene
// en la tarea: hay que leer a la persona. La mayoría del personal no guarda
// `areaId`; el área vive en su cargo (TBL_CARGOS.areaId), el mismo puente que
// ya usaban la reasignación y Visitas.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'area_directory.dart';

class PersonaEmpresa {
  final String id;
  final String nombre;

  /// Id de la opción del catálogo de áreas, o vacío si no se pudo resolver.
  final String areaId;
  final String cargoId;
  final String cargo;

  const PersonaEmpresa({
    required this.id,
    this.nombre = '',
    this.areaId = '',
    this.cargoId = '',
    this.cargo = '',
  });
}

/// Clave de un nombre de cargo: el mismo cargo viene con tildes, mayúsculas y
/// espacios distintos en TBL_USUARIOS y TBL_CARGOS.
String claveCargo(String cargo) => areaClave(cargo);

class PersonasEmpresa {
  final String empresaId;
  final AreaCatalogo areas;
  final Map<String, PersonaEmpresa> porId;

  /// Nombre de cada cargo por id (de TBL_CARGOS).
  final Map<String, String> cargos;

  const PersonasEmpresa({
    required this.empresaId,
    required this.areas,
    required this.porId,
    required this.cargos,
  });

  const PersonasEmpresa.vacio()
    : empresaId = '',
      areas = const AreaCatalogo.vacio(),
      porId = const {},
      cargos = const {};

  PersonaEmpresa? persona(String id) => porId[id.trim()];

  /// Área (id de opción del catálogo) de la persona; vacío si no se sabe.
  String areaDe(String id) => porId[id.trim()]?.areaId ?? '';

  /// Clave del cargo de la persona: el id si existe en el catálogo, si no el
  /// nombre normalizado. Sirve para agrupar y filtrar sin repetir cargos.
  String cargoClaveDe(String id) {
    final p = porId[id.trim()];
    if (p == null) return '';
    if (p.cargoId.isNotEmpty && cargos.containsKey(p.cargoId)) {
      return p.cargoId;
    }
    final clave = claveCargo(p.cargo);
    if (clave.isEmpty) return '';
    for (final e in cargos.entries) {
      if (claveCargo(e.value) == clave) return e.key;
    }
    return 'nombre:$clave';
  }

  String cargoNombreDe(String id) {
    final clave = cargoClaveDe(id);
    if (clave.isEmpty) return '';
    return cargos[clave] ?? porId[id.trim()]?.cargo ?? '';
  }

  /// Arma el directorio con los documentos ya leídos (sin Firebase).
  factory PersonasEmpresa.desdeDatos({
    required String empresaId,
    required Map<String, Map<String, dynamic>> usuarios,
    required List<({String id, Map<String, dynamic> data})> cargos,
    required List<({String id, String? nombre})> areas,
  }) {
    final catalogo = AreaCatalogo.desde(areas, empresaId: empresaId);

    String opcionDeArea(String valor) {
      final v = valor.trim();
      if (v.isEmpty) return '';
      for (final o in catalogo.opciones) {
        if (o.contiene(v)) return o.id;
      }
      return '';
    }

    final nombresCargo = <String, String>{};
    final areaPorCargo = <String, String>{};
    for (final c in cargos) {
      final id = (c.data['cargoId'] ?? c.id).toString().trim();
      final nombre = (c.data['nombre'] ?? c.data['descripcion'] ?? '')
          .toString()
          .trim();
      if (id.isNotEmpty && nombre.isNotEmpty) nombresCargo[id] = nombre;
      final area = opcionDeArea(
        (c.data['areaId'] ?? '').toString().trim().isNotEmpty
            ? c.data['areaId'].toString()
            : (c.data['areaNombre'] ?? c.data['area'] ?? '').toString(),
      );
      if (area.isEmpty) continue;
      if (id.isNotEmpty) areaPorCargo.putIfAbsent('id:$id', () => area);
      if (c.id.isNotEmpty) areaPorCargo.putIfAbsent('id:${c.id}', () => area);
      final clave = claveCargo(nombre);
      if (clave.isNotEmpty) {
        areaPorCargo.putIfAbsent('nombre:$clave', () => area);
      }
    }

    final personas = <String, PersonaEmpresa>{};
    for (final entry in usuarios.entries) {
      final m = entry.value;
      if (!matchesEmpresaScope(
        m,
        empresaId,
        allowLegacyWithoutEmpresa: false,
      )) {
        continue;
      }
      final nombre = [
        (m['nombres'] ?? m['primerNombre'] ?? '').toString(),
        (m['apellidos'] ?? m['primerApellido'] ?? '').toString(),
      ].where((e) => e.trim().isNotEmpty).join(' ').trim();
      final areaId = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
        const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
      ).trim();
      final areaNombre = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['area', 'areaNombre', 'area_nombre', 'departamento'],
        const ['area', 'areaNombre', 'area_nombre', 'departamento'],
      ).trim();
      final cargoId = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['cargoId', 'cargo_id'],
        const ['cargoId', 'cargo_id'],
      ).trim();
      final cargo = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
        const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
      ).trim();
      var area = opcionDeArea(areaId);
      if (area.isEmpty) area = opcionDeArea(areaNombre);
      if (area.isEmpty) {
        area =
            areaPorCargo['id:$cargoId'] ??
            areaPorCargo['nombre:${claveCargo(cargo)}'] ??
            '';
      }
      personas[entry.key] = PersonaEmpresa(
        id: entry.key,
        nombre: nombre,
        areaId: area,
        cargoId: cargoId,
        cargo: cargo.isNotEmpty ? cargo : (nombresCargo[cargoId] ?? ''),
      );
    }

    return PersonasEmpresa(
      empresaId: empresaId,
      areas: catalogo,
      porId: personas,
      cargos: nombresCargo,
    );
  }

  /// Lee personas, cargos y áreas de la empresa. Ante un error de lectura
  /// devuelve lo que alcanzó a leer: los filtros son auxiliares.
  static Future<PersonasEmpresa> cargar(String empresaId) async {
    final empresa = empresaId.trim();
    if (empresa.isEmpty) return const PersonasEmpresa.vacio();
    final db = FirebaseFirestore.instance;

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> leer(
      Query<Map<String, dynamic>> q,
    ) async {
      try {
        return (await q.get()).docs;
      } catch (_) {
        return const [];
      }
    }

    final resultados = await Future.wait([
      leer(
        db.collection('TBL_USUARIOS').where('empresaId', isEqualTo: empresa),
      ),
      // Quien tiene esta empresa como secundaria no la lleva en `empresaId`.
      leer(
        db.collection('TBL_USUARIOS').where('empresas', arrayContains: empresa),
      ),
      leer(db.collection('TBL_CARGOS').where('empresaId', isEqualTo: empresa)),
      leer(db.collection('TBL_AREAS').where('empresaId', isEqualTo: empresa)),
    ]);

    final usuarios = <String, Map<String, dynamic>>{
      for (final d in resultados[0]) d.id: d.data(),
      for (final d in resultados[1]) d.id: d.data(),
    };
    return PersonasEmpresa.desdeDatos(
      empresaId: empresa,
      usuarios: usuarios,
      cargos: [for (final d in resultados[2]) (id: d.id, data: d.data())],
      // El id del documento y `areaId` pueden diferir; las dos variantes
      // quedan en la misma opción para que cualquiera de las dos coincida.
      areas: [
        for (final d in resultados[3]) ...[
          (
            id: d.id,
            nombre: (d.data()['nombre'] ?? d.data()['area'])?.toString(),
          ),
          if ((d.data()['areaId'] ?? '').toString().trim().isNotEmpty &&
              d.data()['areaId'].toString().trim() != d.id)
            (
              id: d.data()['areaId'].toString().trim(),
              nombre: (d.data()['nombre'] ?? d.data()['area'])?.toString(),
            ),
        ],
      ],
    );
  }
}
