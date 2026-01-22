// lib/services/seed_excel_parser.dart
//
// Parser robusto para excel: ^4.0.6
// - Acepta alias de columnas (case-insensitive, sin tildes)
// - Normaliza encabezados y convierte a los nombres esperados por el seeder
//
// Hojas toleradas (nombres flexibles):
//   - PERSONAL
//   - AREAS / ÁREAS
//   - CARGOS
//   - CENTROS_COSTOS / CENTROS / CC
//   - APPS / APLICACIONES
//   - TIPOS_DOCUMENTO / TIPO_DOCUMENTO / DOCUMENTOS
//   - CIUDADES
//   - DEPARTAMENTOS
//
// Salida: SeedWorkbook con llaves estándar:
//
// PERSONAL: cedula,tipo_documento,nombres,apellidos,nombreCompleto,correo,
//           area,cargo,centroCostos,jefeId,jefeNombre,cargoJefe,estado,apps
// AREAS:   nombre, descripcion, activo
// CARGOS:  nombre, area, descripcion, activo
// CENTROS_COSTOS: codigo, nombre
// APPS:    appId, nombre, descripcion, enabled
// TIPOS_DOCUMENTO: codigo, descripcion, tipo_persona
// CIUDADES: codigo_dane, cod_departamento, nombre
// DEPARTAMENTOS: codigo_dane, nombre

import 'dart:typed_data';
import 'package:excel/excel.dart';

class SeedWorkbook {
  final List<Map<String, dynamic>> personal;
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> cargos;
  final List<Map<String, dynamic>> centrosCostos;
  final List<Map<String, dynamic>> apps;

  // Catálogos globales
  final List<Map<String, dynamic>> tiposDocumento;
  final List<Map<String, dynamic>> ciudades;
  final List<Map<String, dynamic>> departamentos;

  const SeedWorkbook({
    required this.personal,
    required this.areas,
    required this.cargos,
    required this.centrosCostos,
    required this.apps,
    required this.tiposDocumento,
    required this.ciudades,
    required this.departamentos,
  });
}

class SeedExcelParser {
  /// Método principal
  Future<SeedWorkbook> parse(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    List<Map<String, dynamic>> readSheetFlexible(List<String> candidates) {
      Sheet? sheet;
      for (final name in candidates) {
        sheet = excel.tables[name] ??
            excel.tables[name.toUpperCase()] ??
            excel.tables[name.toLowerCase()];
        if (sheet != null) break;
      }
      if (sheet == null) return [];

      final rows = sheet.rows; // excel ^4.0.6
      if (rows.isEmpty) return [];

      // Encabezados
      final rawHeaders = rows.first.map((cell) => _cellToString(cell?.value)).toList();
      final headers = rawHeaders.map(_canonHeader).toList();

      final out = <Map<String, dynamic>>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final isBlank = row.every((c) => _cellToString(c?.value).trim().isEmpty);
        if (isBlank) continue;

        final m = <String, dynamic>{};
        for (var j = 0; j < headers.length; j++) {
          final key = headers[j];
          final cell = j < row.length ? row[j] : null;
          final val = _cellToString(cell?.value).trim();
          if (key.isNotEmpty) m[key] = val;
        }
        out.add(m);
      }
      return out;
    }

    // Lee hojas crudas
    final rawPersonal      = readSheetFlexible(['PERSONAL']);
    final rawAreas         = readSheetFlexible(['AREAS', 'ÁREAS']);
    final rawCargos        = readSheetFlexible(['CARGOS']);
    final rawCentrosCostos = readSheetFlexible(['CENTROS_COSTOS', 'CENTROS', 'CC']);
    final rawApps          = readSheetFlexible(['APPS', 'APLICACIONES']);

    // Catálogos globales
    final rawTiposDoc      = readSheetFlexible(['TIPOS_DOCUMENTO', 'TIPO_DOCUMENTO', 'DOCUMENTOS']);
    final rawCiudades      = readSheetFlexible(['CIUDADES']);
    final rawDeptos        = readSheetFlexible(['DEPARTAMENTOS']);

    // Normaliza a las llaves esperadas por el seeder
    final personal = rawPersonal.map(_normalizePersonalRow).where(_notAllEmpty).toList();
    final areas    = rawAreas.map(_normalizeAreaRow).where(_notAllEmpty).toList();
    final cargos   = rawCargos.map(_normalizeCargoRow).where(_notAllEmpty).toList();
    final centros  = rawCentrosCostos.map(_normalizeCentroRow).where(_notAllEmpty).toList();
    final apps     = rawApps.map(_normalizeAppRow).where(_notAllEmpty).toList();

    final tiposDoc = rawTiposDoc.map(_normalizeTipoDocRow).where(_notAllEmpty).toList();
    final ciudades = rawCiudades.map(_normalizeCiudadRow).where(_notAllEmpty).toList();
    final deptos   = rawDeptos.map(_normalizeDepartamentoRow).where(_notAllEmpty).toList();

    return SeedWorkbook(
      personal: personal,
      areas: areas,
      cargos: cargos,
      centrosCostos: centros,
      apps: apps,
      tiposDocumento: tiposDoc,
      ciudades: ciudades,
      departamentos: deptos,
    );
  }

  /// Alias de compatibilidad: si tu UI llama `parseBytes(...)`, seguirá funcionando.
  Future<SeedWorkbook> parseBytes(Uint8List bytes) => parse(bytes);

  // ---------- Normalizadores (aceptan alias) ----------

  Map<String, dynamic> _normalizePersonalRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    return {
      'cedula'        : pick(['cedula', 'num_documento', 'documento', 'id']),
      'tipo_documento': pick(['tipo_documento', 'tipodocumento', 'tipo']),
      'nombres'       : pick(['nombres', 'primer_nombre', 'nombre']),
      'apellidos'     : pick(['apellidos', 'primer_apellido', 'apellido']),
      'nombreCompleto': pick(['nombrecompleto', 'nombre_completo']),
      'correo'        : pick(['correo', 'email']),
      'area'          : pick(['area', 'área', 'areadepartamento', 'area_departamento', 'departamento', 'depto']),
      'cargo'         : pick(['cargo', 'puesto']),
      'centroCostos'  : pick(['centrocostos', 'centro_costos', 'centro', 'cc']),
      'jefeId'        : pick(['jefeid', 'jefe_id', 'id_jefe']),
      'jefeNombre'    : pick(['jefenombre', 'jefe_nombre', 'nombre_jefe']),
      'cargoJefe'     : pick(['cargojefe', 'cargo_jefe']),
      'estado'        : pick(['estado', 'estatus']),
      'apps'          : pick(['apps', 'aplicaciones', 'permisos']),
    };
  }

  Map<String, dynamic> _normalizeAreaRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final nombre = pick(['nombre', 'area', 'área', 'areadepartamento', 'area_departamento', 'descripcion', 'descripción']);
    return {
      'nombre'     : nombre,
      'descripcion': pick(['descripcion', 'descripción', 'detalle']),
      'activo'     : pick(['activo', 'habilitado', 'enabled']),
    };
  }

  Map<String, dynamic> _normalizeCargoRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final nombre = pick(['nombre', 'cargo', 'descripcion', 'descripción']);
    return {
      'nombre'     : nombre,
      'area'       : pick(['area', 'área', 'areadepartamento', 'area_departamento', 'departamento', 'depto']),
      'descripcion': pick(['descripcion', 'descripción', 'detalle']),
      'activo'     : pick(['activo', 'habilitado', 'enabled']),
    };
  }

  Map<String, dynamic> _normalizeCentroRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    return {
      'codigo': pick(['codigo', 'código', 'id']),
      'nombre': pick(['nombre', 'descripcion', 'descripción']),
    };
  }

  Map<String, dynamic> _normalizeAppRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final appId = pick(['appid', 'app_id', 'id']);
    final nombre = pick(['nombre', 'name']);
    return {
      'appId'      : appId,
      'nombre'     : nombre,
      'descripcion': pick(['descripcion', 'descripción']),
      'enabled'    : pick(['enabled', 'habilitada', 'activo']),
    };
  }

  Map<String, dynamic> _normalizeTipoDocRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    return {
      'codigo'      : pick(['codigo', 'código', 'id', 'abreviatura']),
      'descripcion' : pick(['descripcion', 'descripción', 'nombre']),
      'tipo_persona': pick(['tipo_persona', 'personeria', 'persona']),
    };
  }

  Map<String, dynamic> _normalizeCiudadRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    return {
      'codigo_dane'     : pick(['codigo_dane', 'codigodane', 'codigo', 'código', 'id']),
      'cod_departamento': pick(['cod_departamento', 'codigo_departamento', 'deptoid', 'coddepto']),
      'nombre'          : pick(['nombre', 'descripcion', 'descripción']),
    };
  }

  Map<String, dynamic> _normalizeDepartamentoRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    return {
      'codigo_dane': pick(['codigo_dane', 'codigodane', 'codigo', 'código', 'id', 'cod_dane']),
      'nombre'     : pick(['nombre', 'descripcion', 'descripción']),
    };
  }

  // ---------- Utilidades ----------

  String _cellToString(dynamic cv) {
    if (cv == null) return '';
    try {
      if (cv is String) return cv;
      if (cv is bool)   return cv ? 'true' : 'false';
      if (cv is num)    return cv.toString();
      if (cv is DateTime) return cv.toIso8601String();
      // excel CellValue wrappers suelen tener .value
      final v = (cv as dynamic).value;
      if (v is DateTime) return v.toIso8601String();
      if (v != null) return v.toString();
      return cv.toString();
    } catch (_) {
      return cv.toString();
    }
  }

  String _canonHeader(String h) {
    final s = _stripDiacritics(h).toLowerCase().trim();
    return s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '')
        .trim();
  }

  String _stripDiacritics(String s) {
    const src = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑçÇ';
    const dst = 'aeiouAEIOUaeiouAEIOUnNcC';
    var out = s;
    for (int i = 0; i < src.length; i++) {
      out = out.replaceAll(src[i], dst[i]);
    }
    return out;
  }

  bool _notAllEmpty(Map<String, dynamic> m) {
    for (final v in m.values) {
      if (v != null && v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }
}
