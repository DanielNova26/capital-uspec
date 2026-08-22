import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class PersonnelTemplateExport {
  final Uint8List bytes;
  final int areas;
  final int cargos;
  final int centrosCostos;
  final int apps;

  const PersonnelTemplateExport({
    required this.bytes,
    required this.areas,
    required this.cargos,
    required this.centrosCostos,
    required this.apps,
  });
}

class PersonnelTemplateService {
  final FirebaseFirestore _db;

  PersonnelTemplateService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<PersonnelTemplateExport> buildForCompany({
    required String empresaId,
    required String empresaNombre,
  }) async {
    final id = empresaId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(empresaId, 'empresaId', 'No puede estar vacío');
    }

    final results = await Future.wait([
      _loadCompanyCollection('TBL_AREAS', id),
      _loadCompanyCollection('TBL_CARGOS', id),
      _loadCompanyCollection('TBL_CENTROS_COSTOS', id),
      _loadCompanyCollection('TBL_APPS', id),
      _loadCompanyPeople(id),
    ]);

    final people = results[4];
    final areas = _mergeAreas(results[0], people, id);
    final cargos = _mergeCargos(results[1], people, id);
    final centros = _mergeCentros(results[2], people, id);
    final apps = _mergeApps(results[3]);

    final excel = _buildWorkbook(
      empresaNombre: empresaNombre.trim().isEmpty ? id : empresaNombre.trim(),
      areas: areas,
      cargos: cargos,
      centros: centros,
      apps: apps,
    );
    final encoded = excel.save();
    if (encoded == null) {
      throw StateError('No fue posible generar la plantilla actualizada.');
    }
    return PersonnelTemplateExport(
      bytes: Uint8List.fromList(encoded),
      areas: areas.length,
      cargos: cargos.length,
      centrosCostos: centros.length,
      apps: apps.length,
    );
  }

  Future<List<Map<String, dynamic>>> _loadCompanyCollection(
    String collection,
    String empresaId,
  ) async {
    final snapshot = await _db
        .collection(collection)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snapshot.docs
        .map((doc) => <String, dynamic>{'_docId': doc.id, ...doc.data()})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadCompanyPeople(
    String empresaId,
  ) async {
    final results = await Future.wait([
      _db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get(),
      _db
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    final unique = <String, Map<String, dynamic>>{};
    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        unique[doc.id] = <String, dynamic>{'_docId': doc.id, ...doc.data()};
      }
    }
    return unique.values.toList();
  }

  List<Map<String, dynamic>> _mergeAreas(
    List<Map<String, dynamic>> catalog,
    List<Map<String, dynamic>> people,
    String empresaId,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in catalog) {
      final name = _first(row, const ['nombre', 'areaNombre', 'area']);
      if (name.isNotEmpty) merged[_key(name)] = row;
    }
    for (final person in people) {
      final name = _scopedFirst(person, empresaId, const [
        'areaNombre',
        'area',
      ]);
      if (name.isNotEmpty) {
        merged.putIfAbsent(
          _key(name),
          () => <String, dynamic>{
            'nombre': name,
            'descripcion': 'Detectada en el personal de la empresa',
            'activo': true,
          },
        );
      }
    }
    return _sorted(merged.values, const ['nombre', 'areaNombre', 'area']);
  }

  List<Map<String, dynamic>> _mergeCargos(
    List<Map<String, dynamic>> catalog,
    List<Map<String, dynamic>> people,
    String empresaId,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in catalog) {
      final name = _first(row, const ['nombre', 'cargoNombre', 'descripcion']);
      final area = _first(row, const ['areaNombre', 'area']);
      if (name.isNotEmpty) merged['${_key(name)}|${_key(area)}'] = row;
    }
    for (final person in people) {
      final name = _scopedFirst(person, empresaId, const [
        'cargoNombre',
        'cargo',
        'cargoDesc',
      ]);
      final area = _scopedFirst(person, empresaId, const [
        'areaNombre',
        'area',
      ]);
      if (name.isNotEmpty) {
        merged.putIfAbsent(
          '${_key(name)}|${_key(area)}',
          () => <String, dynamic>{
            'nombre': name,
            'areaNombre': area,
            'descripcion': 'Detectado en el personal de la empresa',
            'activo': true,
          },
        );
      }
    }
    return _sorted(merged.values, const [
      'nombre',
      'cargoNombre',
      'descripcion',
    ]);
  }

  List<Map<String, dynamic>> _mergeCentros(
    List<Map<String, dynamic>> catalog,
    List<Map<String, dynamic>> people,
    String empresaId,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in catalog) {
      final code = _first(row, const ['codigo', 'centroCodigo', 'codigoZeus']);
      final name = _first(row, const ['nombre', 'centroCostos', 'descripcion']);
      final key = _key(code.isNotEmpty ? code : name);
      if (key.isNotEmpty) merged[key] = row;
    }
    for (final person in people) {
      final code = _scopedFirst(person, empresaId, const [
        'centroCodigo',
        'centroId',
      ]);
      final name = _scopedFirst(person, empresaId, const [
        'centroCostos',
        'centro_nombre',
      ]);
      final key = _key(code.isNotEmpty ? code : name);
      if (key.isNotEmpty) {
        merged.putIfAbsent(
          key,
          () => <String, dynamic>{'codigo': code, 'nombre': name},
        );
      }
    }
    return _sorted(merged.values, const [
      'codigo',
      'centroCodigo',
      'nombre',
      'centroCostos',
    ]);
  }

  List<Map<String, dynamic>> _mergeApps(List<Map<String, dynamic>> catalog) {
    final merged = <String, Map<String, dynamic>>{
      for (final app in _defaultApps) _key(app['appId']): app,
    };
    for (final row in catalog) {
      final appId = _first(row, const ['appId', 'id']);
      if (appId.isNotEmpty) merged[_key(appId)] = row;
    }
    return _sorted(merged.values, const ['nombre', 'appId']);
  }

  Excel _buildWorkbook({
    required String empresaNombre,
    required List<Map<String, dynamic>> areas,
    required List<Map<String, dynamic>> cargos,
    required List<Map<String, dynamic>> centros,
    required List<Map<String, dynamic>> apps,
  }) {
    final excel = Excel.createExcel();
    final initialSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(initialSheet, 'INSTRUCCIONES');
    excel.setDefaultSheet('INSTRUCCIONES');

    _buildInstructions(excel['INSTRUCCIONES'], empresaNombre);
    _buildDataSheet(
      excel['PERSONAL'],
      const [
        'cedula',
        'tipo_documento',
        'nombres',
        'apellidos',
        'nombreCompleto',
        'correo',
        'area',
        'cargo',
        'centroCostos',
        'jefeId',
        'jefeNombre',
        'cargoJefe',
        'estado',
        'apps',
      ],
      const [16, 18, 22, 22, 30, 32, 26, 30, 24, 16, 30, 28, 15, 28],
      const [],
    );
    _buildDataSheet(
      excel['AREAS'],
      const ['nombre', 'descripcion', 'activo'],
      const [30, 48, 14],
      areas
          .map(
            (data) => [
              _first(data, const ['nombre', 'areaNombre', 'area']),
              _first(data, const ['descripcion', 'detalle']),
              _boolLabel(data['activo'] ?? data['enabled'], fallback: true),
            ],
          )
          .toList(),
    );
    _buildDataSheet(
      excel['CARGOS'],
      const ['nombre', 'area', 'descripcion', 'parent_cargo', 'activo'],
      const [32, 28, 46, 32, 14],
      cargos
          .map(
            (data) => [
              _first(data, const ['nombre', 'cargoNombre', 'descripcion']),
              _first(data, const ['areaNombre', 'area']),
              _first(data, const ['descripcion', 'detalle']),
              _first(data, const ['parent_cargo', 'parent_desc', 'cargoPadre']),
              _boolLabel(data['activo'] ?? data['enabled'], fallback: true),
            ],
          )
          .toList(),
    );
    _buildDataSheet(
      excel['CENTROS_COSTOS'],
      const ['codigo', 'nombre'],
      const [24, 46],
      centros
          .map(
            (data) => [
              _first(data, const ['codigo', 'centroCodigo', 'codigoZeus']),
              _first(data, const ['nombre', 'centroCostos', 'descripcion']),
            ],
          )
          .toList(),
    );
    _buildDataSheet(
      excel['APPS'],
      const ['appId', 'nombre', 'descripcion', 'enabled'],
      const [28, 30, 48, 14],
      apps
          .map(
            (data) => [
              _first(data, const ['appId', 'id']),
              _first(data, const ['nombre', 'name']),
              _first(data, const ['descripcion', 'detalle']),
              _boolLabel(data['enabled'] ?? data['activo'], fallback: true),
            ],
          )
          .toList(),
    );
    _buildDataSheet(
      excel['EJEMPLO'],
      const [
        'cedula',
        'tipo_documento',
        'nombres',
        'apellidos',
        'nombreCompleto',
        'correo',
        'area',
        'cargo',
        'centroCostos',
        'jefeId',
        'jefeNombre',
        'cargoJefe',
        'estado',
        'apps',
      ],
      const [16, 18, 22, 22, 30, 32, 26, 30, 24, 16, 30, 28, 15, 28],
      const [
        [
          '1012345678',
          'CC',
          'Andrea',
          'Pérez',
          'Andrea Pérez',
          'andrea.perez@empresa.com',
          'Talento Humano',
          'Analista',
          'CC-01',
          '',
          '',
          '',
          'ACTIVO',
          'tareasdashboard',
        ],
      ],
    );
    return excel;
  }

  void _buildInstructions(Sheet sheet, String empresaNombre) {
    const steps = [
      ['1', 'PERSONAL', 'Obligatoria', 'Una fila por colaborador'],
      ['2', 'AREAS', 'Actualizada', 'Áreas existentes y nuevas'],
      ['3', 'CARGOS', 'Actualizada', 'Cargos existentes y jerarquía'],
      ['4', 'CENTROS_COSTOS', 'Actualizada', 'Códigos y nombres existentes'],
      ['5', 'APPS', 'Actualizada', 'Módulos asignables'],
    ];
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
    );
    _cell(sheet, 0, 0, 'Plantilla de personal · Talento Humano', _titleStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1),
    );
    _cell(
      sheet,
      1,
      0,
      'Empresa activa: $empresaNombre. Los catálogos fueron consultados al '
      'momento de descargar este archivo.',
      _subtitleStyle,
    );
    const headers = ['Paso', 'Hoja', 'Estado', 'Uso'];
    for (var column = 0; column < headers.length; column++) {
      _cell(sheet, 3, column, headers[column], _headerStyle);
    }
    for (var row = 0; row < steps.length; row++) {
      for (var column = 0; column < steps[row].length; column++) {
        _cell(sheet, row + 4, column, steps[row][column], _bodyStyle);
      }
    }
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 10),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 10),
    );
    _cell(
      sheet,
      10,
      0,
      'Diligencia PERSONAL sin cambiar los encabezados. Puedes agregar nuevos '
      'valores en los catálogos; la importación usa la cédula para actualizar '
      'sin borrar el historial.',
      _noticeStyle,
    );
    for (var column = 0; column < 4; column++) {
      sheet.setColumnWidth(column, [10.0, 26.0, 20.0, 48.0][column]);
    }
    sheet.setRowHeight(0, 32);
    sheet.setRowHeight(1, 38);
    sheet.setRowHeight(10, 48);
  }

  void _buildDataSheet(
    Sheet sheet,
    List<String> headers,
    List<int> widths,
    List<List<String>> rows,
  ) {
    for (var column = 0; column < headers.length; column++) {
      _cell(sheet, 0, column, headers[column], _headerStyle);
      sheet.setColumnWidth(column, widths[column].toDouble());
    }
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        _cell(sheet, row + 1, column, rows[row][column], _bodyStyle);
      }
    }
    sheet.setRowHeight(0, 28);
  }

  void _cell(Sheet sheet, int row, int column, String value, CellStyle style) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }

  List<Map<String, dynamic>> _sorted(
    Iterable<Map<String, dynamic>> values,
    List<String> keys,
  ) {
    final rows = values.toList();
    rows.sort(
      (a, b) => _first(
        a,
        keys,
      ).toLowerCase().compareTo(_first(b, keys).toLowerCase()),
    );
    return rows;
  }

  String _scopedFirst(
    Map<String, dynamic> data,
    String empresaId,
    List<String> keys,
  ) {
    final rawDetails = data['empresasDetalle'];
    final details = rawDetails is Map
        ? rawDetails[empresaId]
        : const <String, dynamic>{};
    if (details is Map) {
      final scoped = <String, dynamic>{
        for (final entry in details.entries) entry.key.toString(): entry.value,
      };
      final value = _first(scoped, keys);
      if (value.isNotEmpty) return value;
    }
    return _first(data, keys);
  }

  String _first(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = key == 'id' ? data['_docId'] : data[key];
      final value = raw?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  String _key(String value) => value.trim().toLowerCase();

  String _boolLabel(dynamic value, {required bool fallback}) {
    if (value == null) return fallback ? 'SI' : 'NO';
    if (value is bool) return value ? 'SI' : 'NO';
    if (value is num) return value == 0 ? 'NO' : 'SI';
    final normalized = value.toString().trim().toLowerCase();
    if (const {
      'false',
      'no',
      'n',
      '0',
      'inactivo',
      'deshabilitado',
    }.contains(normalized)) {
      return 'NO';
    }
    if (const {
      'true',
      'si',
      'sí',
      's',
      '1',
      'activo',
      'habilitado',
    }.contains(normalized)) {
      return 'SI';
    }
    return fallback ? 'SI' : 'NO';
  }
}

final _thinBorder = Border(
  borderStyle: BorderStyle.Thin,
  borderColorHex: ExcelColor.fromHexString('FFD8E2EA'),
);

final _titleStyle = CellStyle(
  backgroundColorHex: ExcelColor.fromHexString('FF173B5E'),
  fontColorHex: ExcelColor.white,
  fontFamily: 'Arial',
  fontSize: 18,
  bold: true,
  verticalAlign: VerticalAlign.Center,
);

final _subtitleStyle = CellStyle(
  backgroundColorHex: ExcelColor.fromHexString('FFEAF4FB'),
  fontColorHex: ExcelColor.fromHexString('FF5F6B76'),
  fontFamily: 'Arial',
  fontSize: 10,
  italic: true,
  textWrapping: TextWrapping.WrapText,
  verticalAlign: VerticalAlign.Center,
);

final _headerStyle = CellStyle(
  backgroundColorHex: ExcelColor.fromHexString('FF246B9E'),
  fontColorHex: ExcelColor.white,
  fontFamily: 'Arial',
  fontSize: 10,
  bold: true,
  textWrapping: TextWrapping.WrapText,
  verticalAlign: VerticalAlign.Center,
  leftBorder: _thinBorder,
  rightBorder: _thinBorder,
  topBorder: _thinBorder,
  bottomBorder: _thinBorder,
);

final _bodyStyle = CellStyle(
  fontColorHex: ExcelColor.fromHexString('FF17212B'),
  fontFamily: 'Arial',
  fontSize: 10,
  verticalAlign: VerticalAlign.Center,
  leftBorder: _thinBorder,
  rightBorder: _thinBorder,
  topBorder: _thinBorder,
  bottomBorder: _thinBorder,
);

final _noticeStyle = CellStyle(
  backgroundColorHex: ExcelColor.fromHexString('FFE9F8F0'),
  fontColorHex: ExcelColor.fromHexString('FF176B45'),
  fontFamily: 'Arial',
  fontSize: 10,
  bold: true,
  textWrapping: TextWrapping.WrapText,
  verticalAlign: VerticalAlign.Center,
  leftBorder: _thinBorder,
  rightBorder: _thinBorder,
  topBorder: _thinBorder,
  bottomBorder: _thinBorder,
);

const _defaultApps = <Map<String, dynamic>>[
  {
    'appId': 'admindashboard',
    'nombre': 'Administración',
    'descripcion': 'Configuración global y seguridad',
    'enabled': true,
  },
  {
    'appId': 'talentohumanodashboard',
    'nombre': 'Talento Humano',
    'descripcion': 'Gestión del personal',
    'enabled': true,
  },
  {
    'appId': 'gerenciadashboard',
    'nombre': 'Gerencia',
    'descripcion': 'Seguimiento gerencial',
    'enabled': true,
  },
  {
    'appId': 'gestiondocumentaldashboard',
    'nombre': 'Gestión de Correspondencia',
    'descripcion': 'Correspondencia y documentos',
    'enabled': true,
  },
  {
    'appId': 'nutriciondashboard',
    'nombre': 'Nutrición',
    'descripcion': 'Gestión nutricional',
    'enabled': true,
  },
  {
    'appId': 'comprasdashboard',
    'nombre': 'Compras',
    'descripcion': 'Proveedores, productos y recepción',
    'enabled': true,
  },
  {
    'appId': 'correodashboard',
    'nombre': 'Correo',
    'descripcion': 'Monitoreo y alertas de correo',
    'enabled': true,
  },
  {
    'appId': 'interventoriadashboard',
    'nombre': 'Interventoría',
    'descripcion': 'Seguimiento de interventoría',
    'enabled': true,
  },
  {
    'appId': 'facturaciondashboard',
    'nombre': 'Facturación',
    'descripcion': 'Gestión de facturación',
    'enabled': true,
  },
  {
    'appId': 'rutasdashboard',
    'nombre': 'Rutas',
    'descripcion': 'Gestión logística de rutas',
    'enabled': true,
  },
];
