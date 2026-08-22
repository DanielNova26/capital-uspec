import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class ZeusExportFilter {
  final String estado;
  final String area;
  final String cargo;

  const ZeusExportFilter({this.estado = '', this.area = '', this.cargo = ''});
}

class ZeusExportPending {
  final String cedula;
  final String nombre;
  final String campo;
  final String detalle;

  const ZeusExportPending({
    required this.cedula,
    required this.nombre,
    required this.campo,
    required this.detalle,
  });
}

class ZeusExportSummary {
  final int total;
  final int exportables;
  final int conPendientes;
  final List<String> areas;
  final List<String> cargos;
  final List<ZeusExportPending> pendientes;
  final Map<String, String> config;
  final List<ZeusEmployeeBundle> empleados;
  final ZeusIndexes indexes;

  const ZeusExportSummary({
    required this.total,
    required this.exportables,
    required this.conPendientes,
    required this.areas,
    required this.cargos,
    required this.pendientes,
    required this.config,
    required this.empleados,
    required this.indexes,
  });
}

class ZeusExportService {
  final FirebaseFirestore _db;

  ZeusExportService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<ZeusExportSummary> loadSummary(
    String empresaId, {
    ZeusExportFilter filter = const ZeusExportFilter(),
  }) async {
    final results = await Future.wait([
      _loadUsers(empresaId),
      _loadOrgDocs(empresaId),
      _loadCollection('TBL_CARGOS', empresaId: empresaId),
      _loadCollection('TBL_AREAS', empresaId: empresaId),
      _loadCollection('TBL_CENTROS_COSTOS', empresaId: empresaId),
      _loadCollection('TBL_CIUDADES'),
      loadConfig(empresaId),
      _loadZeusCatalogs(empresaId),
      _loadEmployeeZeusData(empresaId),
    ]);

    final users =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final orgDocs = results[1] as Map<String, Map<String, dynamic>>;
    final cargos =
        results[2] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final areas =
        results[3] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final centros =
        results[4] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final ciudades =
        results[5] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final config = results[6] as Map<String, String>;
    final catalogs = results[7] as ZeusCatalogs;
    final zeusDataByCedula = results[8] as Map<String, Map<String, String>>;

    final indexes = ZeusIndexes(
      cargos: _indexDocs(cargos, nameKeys: const ['nombre', 'descripcion']),
      areas: _indexDocs(areas, nameKeys: const ['nombre']),
      centros: _indexDocs(
        centros,
        nameKeys: const ['nombre', 'centroCostos'],
        codeKeys: const ['codigo', 'centroCodigo', 'codigoZeus'],
      ),
      ciudades: _indexDocs(
        ciudades,
        nameKeys: const ['nombre'],
        codeKeys: const ['codigoZeus', 'codigo_zeus', 'cod_zeus', 'cod_dane'],
      ),
      catalogs: catalogs,
    );

    final bundles = <ZeusEmployeeBundle>[];
    final hvResults = await Future.wait([
      for (final user in users)
        _loadHv(user.reference).timeout(
          const Duration(seconds: 8),
          onTimeout: () => <String, dynamic>{},
        ),
    ]);

    for (var i = 0; i < users.length; i++) {
      final user = users[i];
      final hv = hvResults[i];
      final data = user.data();
      final cedula = _first([data['cedula'], user.id]);
      final org = orgDocs[cedula] ?? orgDocs['${empresaId}_$cedula'];
      final detail = _empresaDetail(data, empresaId);
      final bundle = ZeusEmployeeBundle(
        userId: user.id,
        cedula: cedula,
        user: data,
        hv: hv,
        org: org ?? const {},
        empresaDetail: detail,
        zeusData: zeusDataByCedula[cedula] ?? const {},
      );
      if (!_matchesFilter(bundle, filter)) continue;
      bundles.add(bundle);
    }

    final areasList =
        bundles.map((e) => e.area).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    final cargosList =
        bundles.map((e) => e.cargo).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();

    final pendings = <ZeusExportPending>[];
    final pendingIds = <String>{};
    for (final e in bundles) {
      final before = pendings.length;
      _validateEmployee(e, indexes, config, pendings);
      if (pendings.length > before) pendingIds.add(e.cedula);
    }

    return ZeusExportSummary(
      total: bundles.length,
      exportables: bundles.length - pendingIds.length,
      conPendientes: pendingIds.length,
      areas: areasList,
      cargos: cargosList,
      pendientes: pendings,
      config: config,
      empleados: bundles,
      indexes: indexes,
    );
  }

  Future<Map<String, String>> loadConfig(String empresaId) async {
    final out = <String, String>{};
    try {
      final empresa = await _db
          .collection('TBL_EMPRESAS')
          .doc(empresaId)
          .get()
          .timeout(const Duration(seconds: 8));
      final empresaConfig = empresa.data()?['zeusConfig'];
      if (empresaConfig is Map) {
        for (final entry in empresaConfig.entries) {
          out[entry.key.toString()] = entry.value?.toString() ?? '';
        }
      }
    } catch (_) {}
    try {
      final snap = await _db
          .collection('TBL_ZEUS_CONFIG')
          .doc(empresaId)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = snap.data() ?? {};
      for (final entry in data.entries) {
        if (entry.value is Timestamp) continue;
        out[entry.key] = entry.value?.toString() ?? '';
      }
    } catch (_) {}
    return out;
  }

  Future<void> saveConfig(String empresaId, Map<String, String> values) async {
    final clean = <String, dynamic>{
      for (final entry in values.entries) entry.key: entry.value.trim(),
      'empresaId': empresaId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _db
        .collection('TBL_ZEUS_CONFIG')
        .doc(empresaId)
        .set(clean, SetOptions(merge: true));
  }

  Future<void> saveEmployeeZeusData(
    String empresaId,
    String cedula,
    Map<String, String> values,
  ) async {
    final clean = <String, dynamic>{
      'empresaId': empresaId,
      'cedula': cedula,
      for (final entry in values.entries) entry.key: entry.value.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _db
        .collection('TBL_ZEUS_EMPLEADOS')
        .doc('${empresaId}_$cedula')
        .set(clean, SetOptions(merge: true));
  }

  Future<void> createBasicUser({
    required String empresaId,
    required String cedula,
    required String primerNombre,
    required String segundoNombre,
    required String primerApellido,
    required String segundoApellido,
    required String correo,
    required String area,
    required String cargo,
    required String centroCostos,
  }) async {
    final nombres = '$primerNombre $segundoNombre'.trim();
    final apellidos = '$primerApellido $segundoApellido'.trim();
    final nombreCompleto = '$nombres $apellidos'.trim();
    final ref = _db.collection('TBL_USUARIOS').doc(cedula);
    final existing = await ref.get();
    final payload = <String, dynamic>{
      'usuario': cedula,
      'cedula': cedula,
      'tipo_documento': 'CC',
      'primerNombre': primerNombre.trim(),
      'segundoNombre': segundoNombre.trim(),
      'primerApellido': primerApellido.trim(),
      'segundoApellido': segundoApellido.trim(),
      'nombres': nombres,
      'apellidos': apellidos,
      'nombreCompleto': nombreCompleto,
      'correo': correo.trim(),
      'empresaId': empresaId,
      'empresas': FieldValue.arrayUnion([empresaId]),
      'area': area.trim().isEmpty ? null : area.trim(),
      'areaNombre': area.trim().isEmpty ? null : area.trim(),
      'cargo': cargo.trim().isEmpty ? null : cargo.trim(),
      'centroCostos': centroCostos.trim().isEmpty ? null : centroCostos.trim(),
      'estado': 'activo',
      'role': 'usuario',
      'updatedAt': FieldValue.serverTimestamp(),
      'empresasDetalle': {
        empresaId: {
          'empresaId': empresaId,
          'area': area.trim().isEmpty ? null : area.trim(),
          'areaNombre': area.trim().isEmpty ? null : area.trim(),
          'cargo': cargo.trim().isEmpty ? null : cargo.trim(),
          'centroCostos': centroCostos.trim().isEmpty
              ? null
              : centroCostos.trim(),
        },
      },
    };
    if (!existing.exists ||
        (existing.data()?['password'] ?? '').toString().trim().isEmpty) {
      payload.addAll({
        'password': '123456',
        'needsPasswordChange': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await ref.set(payload, SetOptions(merge: true));
  }

  Future<Uint8List> exportToExcelBytes(ZeusExportSummary summary) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    _writeSheet(excel, 'ZEmpleados1', _empleadosHeaders, [
      for (final e in summary.empleados)
        _buildEmpleadoRow(e, summary.indexes, summary.config),
    ]);
    _writeSheet(excel, 'ZContrato1', _contratoHeaders, [
      for (final e in summary.empleados)
        _buildContratoRow(e, summary.indexes, summary.config),
    ]);
    _writeSheet(excel, 'ZDatos Familiares1', _familiaresHeaders, const []);
    _writeSheet(excel, 'ZDistribución1', _distribucionHeaders, [
      for (final e in summary.empleados)
        _buildDistribucionRow(e, summary.indexes, summary.config),
    ]);
    _writeSheet(
      excel,
      'ZEPS1',
      _epsHeaders,
      _catalogRows(
        summary.empleados.map((e) => e.eps),
        summary.indexes.catalogs.eps,
        50,
      ),
    );
    _writeSheet(
      excel,
      'ZPension1',
      _epsHeaders,
      _catalogRows(
        summary.empleados.map((e) => e.fondoPensiones),
        summary.indexes.catalogs.pension,
        50,
      ),
    );
    _writeSheet(
      excel,
      'ZCesantias1',
      _cesantiasHeaders,
      _catalogRows(
        summary.empleados.map((e) => e.fondoCesantias),
        summary.indexes.catalogs.cesantias,
        5,
      ),
    );
    _writeSheet(
      excel,
      'ZCajas Compension1',
      _cajaHeaders,
      [
        _fixedCatalogRow(
          summary.config,
          codeKey: 'cajaCompensacionCodigo',
          nameKey: 'cajaCompensacionNombre',
          nationalKey: 'cajaCompensacionCodigoNacional',
          nitKey: 'cajaCompensacionNit',
          width: 5,
        ),
      ].where((row) => row.any((v) => v.toString().trim().isNotEmpty)).toList(),
    );
    _writeSheet(excel, 'ZCargos1', _cargosHeaders, _cargoRows(summary));
    _writeSheet(
      excel,
      'ZProfesiones1',
      _profesionesHeaders,
      _profesionRows(summary),
    );
    _writeSheet(
      excel,
      'ZCentrosTrabajos1',
      _centrosHeaders,
      _centroRows(summary),
    );
    excel.setDefaultSheet('ZEmpleados1');

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo Zeus.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadUsers(
    String empresaId,
  ) async {
    final docs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    try {
      final snap = await _db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get()
          .timeout(const Duration(seconds: 10));
      for (final d in snap.docs) {
        docs[d.id] = d;
      }
    } catch (_) {}
    try {
      final snap = await _db
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get()
          .timeout(const Duration(seconds: 10));
      for (final d in snap.docs) {
        docs[d.id] = d;
      }
    } catch (_) {}
    return docs.values.toList();
  }

  Future<Map<String, Map<String, dynamic>>> _loadOrgDocs(
    String empresaId,
  ) async {
    try {
      final snap = await _db
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .where('empresaId', isEqualTo: empresaId)
          .get()
          .timeout(const Duration(seconds: 10));
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return {};
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadCollection(
    String collection, {
    String? empresaId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db.collection(collection);
      if (empresaId != null && empresaId.trim().isNotEmpty) {
        q = q.where('empresaId', isEqualTo: empresaId.trim());
      }
      final snap = await q.get().timeout(const Duration(seconds: 10));
      return snap.docs;
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> _loadHv(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref
          .collection('hoja_de_vida')
          .doc('datos')
          .get()
          .timeout(const Duration(seconds: 8));
      return snap.data() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, String>>> _loadEmployeeZeusData(
    String empresaId,
  ) async {
    try {
      final snap = await _db
          .collection('TBL_ZEUS_EMPLEADOS')
          .where('empresaId', isEqualTo: empresaId)
          .get()
          .timeout(const Duration(seconds: 10));
      return {
        for (final d in snap.docs)
          _first([
            d.data()['cedula'],
            d.id.replaceFirst('${empresaId}_', ''),
          ]): {
            for (final entry in d.data().entries)
              if (entry.value is! Timestamp)
                entry.key: entry.value?.toString() ?? '',
          },
      };
    } catch (_) {
      return {};
    }
  }

  Future<ZeusCatalogs> _loadZeusCatalogs(String empresaId) async {
    final results = await Future.wait([
      _loadZeusCatalog(empresaId, const [
        'TBL_ZEUS_EPS',
        'TBL_EPS',
        'TBL_CATALOGOS_EPS',
      ]),
      _loadZeusCatalog(empresaId, const [
        'TBL_ZEUS_PENSION',
        'TBL_PENSIONES',
        'TBL_FONDOS_PENSION',
      ]),
      _loadZeusCatalog(empresaId, const [
        'TBL_ZEUS_CESANTIAS',
        'TBL_CESANTIAS',
        'TBL_FONDOS_CESANTIAS',
      ]),
      _loadZeusCatalog(empresaId, const ['TBL_ZEUS_BANCOS', 'TBL_BANCOS']),
      _loadZeusCatalog(empresaId, const [
        'TBL_ZEUS_PROFESIONES',
        'TBL_PROFESIONES',
      ]),
    ]);
    return ZeusCatalogs(
      eps: results[0],
      pension: results[1],
      cesantias: results[2],
      bancos: results[3],
      profesiones: results[4],
    );
  }

  Future<Map<String, ZeusCatalogItem>> _loadZeusCatalog(
    String empresaId,
    List<String> collections,
  ) async {
    final out = <String, ZeusCatalogItem>{};
    for (final collection in collections) {
      try {
        final snap = await _db
            .collection(collection)
            .get()
            .timeout(const Duration(seconds: 8));
        for (final d in snap.docs) {
          final data = d.data();
          final rowEmpresa = _first([data['empresaId'], data['empresa_id']]);
          if (rowEmpresa.isNotEmpty && rowEmpresa != empresaId) continue;
          final name = _first([
            data['nombre'],
            data['descripcion'],
            data['name'],
            data['label'],
            d.id,
          ]);
          if (name.isEmpty) continue;
          final code = _first([
            data['codigoZeus'],
            data['codigo_zeus'],
            data['codZeus'],
            data['cod_zeus'],
            data['codigo'],
            data['cod'],
          ]);
          out[_norm(name)] = ZeusCatalogItem(
            code: code,
            name: name,
            nationalCode: _first([
              data['codigoNacional'],
              data['codigo_nacional'],
              data['codNacional'],
            ]),
            nit: _first([data['nit'], data['NIT'], data['n.i.t']]),
          );
        }
      } catch (_) {}
    }
    return out;
  }

  bool _matchesFilter(ZeusEmployeeBundle e, ZeusExportFilter filter) {
    if (filter.estado.isNotEmpty && e.estado != filter.estado) return false;
    if (filter.area.isNotEmpty && e.area != filter.area) return false;
    if (filter.cargo.isNotEmpty && e.cargo != filter.cargo) return false;
    return true;
  }

  void _validateEmployee(
    ZeusEmployeeBundle e,
    ZeusIndexes indexes,
    Map<String, String> config,
    List<ZeusExportPending> out,
  ) {
    void add(String campo, String detalle) {
      out.add(
        ZeusExportPending(
          cedula: e.cedula,
          nombre: e.nombreCompleto,
          campo: campo,
          detalle: detalle,
        ),
      );
    }

    if (e.cedula.isEmpty) add('Identificación', 'No hay cédula.');
    if (e.primerNombre.isEmpty || e.primerApellido.isEmpty) {
      add('Nombre', 'Faltan nombres o apellidos.');
    }
    if (e.fechaNacimiento.isEmpty) {
      add('Fecha nacimiento', 'No está en la hoja de vida.');
    }
    if (e.cargo.isEmpty) add('Cargo', 'No tiene cargo asignado.');
    if (e.cargo.isNotEmpty && _cargoCode(e, indexes).isEmpty) {
      add('Código cargo Zeus', 'Configura código para "${e.cargo}".');
    }
    if (e.centroNombre.isEmpty && _cfg(config, 'centroTrabajoCodigo').isEmpty) {
      add('Centro de trabajo', 'No hay centro asignado ni default Zeus.');
    }
    if (e.eps.isNotEmpty && _catalogCode(e.eps, indexes.catalogs.eps).isEmpty) {
      add('Código EPS Zeus', 'Configura código para "${e.eps}".');
    }
    if (e.fondoPensiones.isNotEmpty &&
        _catalogCode(e.fondoPensiones, indexes.catalogs.pension).isEmpty) {
      add(
        'Código pensión Zeus',
        'Configura código para "${e.fondoPensiones}".',
      );
    }
    if (e.fondoCesantias.isNotEmpty &&
        _catalogCode(e.fondoCesantias, indexes.catalogs.cesantias).isEmpty) {
      add(
        'Código cesantías Zeus',
        'Configura código para "${e.fondoCesantias}".',
      );
    }
    if (e.banco.isNotEmpty &&
        _catalogCode(e.banco, indexes.catalogs.bancos).isEmpty) {
      add('Código banco Zeus', 'Configura código para "${e.banco}".');
    }
    if (e.banco.isEmpty) {
      add('Banco', 'Falta banco del empleado.');
    }
    if (e.tipoCuenta.isEmpty) {
      add('Tipo de cuenta', 'Falta tipo de cuenta del empleado.');
    }
    if (e.cuentaBancaria.isEmpty) {
      add('Cuenta bancaria', 'Falta número de cuenta del empleado.');
    }
    if (_first([e.sueldoBasico, _cfg(config, 'sueldoBasico')]).isEmpty) {
      add('Sueldo básico', 'TH debe configurar el sueldo/default Zeus.');
    }
    if (_first([
      e.fechaInicioContrato,
      _cfg(config, 'fechaInicioContrato'),
    ]).isEmpty) {
      add('Fecha inicio contrato', 'TH debe configurar la fecha/default Zeus.');
    }
  }

  void _writeSheet(
    Excel excel,
    String name,
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    final sheet = excel[name];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#C28942'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(c, headers[c].length.clamp(12, 32).toDouble());
    }
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(
          c < row.length ? row[c].toString() : '',
        );
      }
    }
  }

  List<dynamic> _buildEmpleadoRow(
    ZeusEmployeeBundle e,
    ZeusIndexes indexes,
    Map<String, String> config,
  ) {
    final ciudad = _cityCode(e.residenciaCiudadCod, e.ciudad, indexes);
    final nacimiento = _cityCode(
      e.nacimientoCiudadCod,
      e.lugarNacimiento,
      indexes,
    );
    return _withWidth([
        e.cedula,
        e.tipoDocumento.isEmpty ? 'CC' : e.tipoDocumento,
        e.primerNombre,
        e.segundoNombre,
        e.primerApellido,
        e.segundoApellido,
        _date(e.fechaNacimiento),
        e.numeroHijos,
        e.personasCargo,
        _cfg(config, 'extranjero', fallback: '0'),
        _cfg(config, 'discapacitado', fallback: '0'),
        e.tipoSangre,
        _cfg(config, 'cabezaFamilia', fallback: '0'),
        _gender(e.genero),
        _estadoCivil(e.estadoCivil),
        ciudad,
        nacimiento,
        _first([e.lugarExpedicionCiudadCod, e.lugarExpedicion]),
        e.email,
        _nivelEstudio(e),
        _professionCode(e, indexes),
        _first([e.uniInst, e.bachInst]),
        _cfg(config, 'enviarRecibosEmail', fallback: '1'),
        e.direccion,
        e.barrio,
      ], _empleadosHeaders.length)
      ..[31] = _first([e.areaId, _catalogCode(e.area, indexes.areas)])
      ..[40] = e.telefono;
  }

  List<dynamic> _buildContratoRow(
    ZeusEmployeeBundle e,
    ZeusIndexes indexes,
    Map<String, String> config,
  ) {
    final centroCode = _first([
      e.centroTrabajoCodigo,
      _catalogCode(e.centroNombre, indexes.centros),
      _cfg(config, 'centroTrabajoCodigo'),
    ]);
    final ciudad = _cityCode(e.residenciaCiudadCod, e.ciudad, indexes);
    final bancoCode = _catalogCode(e.banco, indexes.catalogs.bancos);
    return _withWidth([
        e.cedula,
        _first([e.codigoContrato, _cfg(config, 'codigoContrato'), e.cedula]),
        _cfg(config, 'categoriaContrato'),
        _first([e.sueldoBasico, _cfg(config, 'sueldoBasico')]),
        _first([e.horasTrabajadasMes, _cfg(config, 'horasTrabajadasMes')]),
        _date(
          _first([e.fechaInicioContrato, _cfg(config, 'fechaInicioContrato')]),
        ),
        _cfg(config, 'etapaPrueba', fallback: '0'),
        _first([e.tipoContrato, _cfg(config, 'tipoContrato', fallback: 'I')]),
        _date(
          _first([
            e.fechaVencimientoContrato,
            _cfg(config, 'fechaVencimientoContrato'),
          ]),
        ),
        _cfg(config, 'tipoRemuneracion', fallback: 'U'),
        _cfg(config, 'tipoSalario', fallback: 'F'),
        _first([e.tipoNomina, _cfg(config, 'tipoNomina')]),
        _first([e.formaPago, _cfg(config, 'formaPago')]),
        _cfg(config, 'procedimientoRetencion'),
        _cfg(config, 'baseTipoRetencion2'),
        _cfg(config, 'altoRiesgo', fallback: '0'),
        _cfg(config, 'pensionado', fallback: '0'),
        _cfg(config, 'ley50', fallback: '0'),
        _date(_cfg(config, 'fechaIngresoLey50')),
        '',
        '',
        _cfg(config, 'noUsarAportes', fallback: '0'),
        _cargoCode(e, indexes),
        '',
        centroCode,
        _first([e.unidadNegocio, _cfg(config, 'unidadNegocio')]),
        ciudad,
      ], _contratoHeaders.length)
      ..[44] = _catalogCode(e.eps, indexes.catalogs.eps)
      ..[45] = _catalogCode(e.fondoPensiones, indexes.catalogs.pension)
      ..[46] = _catalogCode(e.fondoCesantias, indexes.catalogs.cesantias)
      ..[48] = _cfg(config, 'cajaCompensacionCodigo')
      ..[49] = _cfg(config, 'fondoRiesgoCodigo')
      ..[56] = _cfg(config, 'tipoCotizante')
      ..[69] = _first([e.centroCodigo, centroCode])
      ..[70] = _cfg(config, 'nivelOrganizacion')
      ..[75] = _first([e.cuentaBancaria, _cfg(config, 'cuentaBancaria')])
      ..[76] = _first([bancoCode, _cfg(config, 'entidadBancaria')])
      ..[78] = _cfg(config, 'ciudadEntidad', fallback: ciudad)
      ..[79] = _first([e.tipoCuenta, _cfg(config, 'tipoCuenta')])
      ..[106] = _first([e.jefeId, _cfg(config, 'jefe')])
      ..[118] = _cfg(config, 'exportarNomina', fallback: '1')
      ..[121] = _cfg(config, 'grupo')
      ..[124] = _cfg(config, 'valorHora');
  }

  List<dynamic> _buildDistribucionRow(
    ZeusEmployeeBundle e,
    ZeusIndexes indexes,
    Map<String, String> config,
  ) {
    return [
      _first([e.codigoContrato, _cfg(config, 'codigoContrato'), e.cedula]),
      _first([
        e.zeus('centroTrabajoCodigo'),
        e.centroTrabajoCodigo,
        _catalogCode(e.centroNombre, indexes.centros),
      ]),
      _cfg(config, 'distribucionCuenta'),
      _cfg(config, 'distribucionPorcentaje', fallback: '100'),
      _cfg(config, 'distribucionTipoCuenta'),
      _first([e.unidadNegocio, _cfg(config, 'unidadNegocio')]),
    ];
  }

  List<List<dynamic>> _catalogRows(
    Iterable<String> names,
    Map<String, ZeusCatalogItem> index,
    int width,
  ) {
    final used = names.map(_norm).where((e) => e.isNotEmpty).toSet().toList();
    used.sort();
    return [
      for (final key in used)
        if (index[key] != null)
          _withWidth([
            index[key]!.code,
            index[key]!.name,
            index[key]!.nationalCode,
            index[key]!.nit,
          ], width),
    ];
  }

  List<dynamic> _fixedCatalogRow(
    Map<String, String> config, {
    required String codeKey,
    required String nameKey,
    required String nationalKey,
    required String nitKey,
    required int width,
  }) {
    return _withWidth([
      _cfg(config, codeKey),
      _cfg(config, nameKey),
      _cfg(config, nationalKey),
      _cfg(config, nitKey),
    ], width);
  }

  List<List<dynamic>> _cargoRows(ZeusExportSummary summary) {
    final rows = <String, List<dynamic>>{};
    for (final e in summary.empleados) {
      final code = _cargoCode(e, summary.indexes);
      if (code.isEmpty || e.cargo.isEmpty) continue;
      rows[code] = _withWidth([
        code,
        e.cargo,
        e.cargoId,
        '',
        '',
        e.descripcionCargo,
        '',
      ], 7);
    }
    return rows.values.toList();
  }

  List<List<dynamic>> _profesionRows(ZeusExportSummary summary) {
    final rows = <String, List<dynamic>>{};
    for (final e in summary.empleados) {
      final code = _professionCode(e, summary.indexes);
      final name = _first([e.uniCarr, e.secCarr, e.espProg, e.maeProg]);
      if (code.isEmpty || name.isEmpty) continue;
      rows[code] = [code, name];
    }
    return rows.values.toList();
  }

  List<List<dynamic>> _centroRows(ZeusExportSummary summary) {
    final rows = <String, List<dynamic>>{};
    for (final e in summary.empleados) {
      final code = _first([
        e.zeus('centroTrabajoCodigo'),
        e.centroTrabajoCodigo,
        _catalogCode(e.centroNombre, summary.indexes.centros),
        _cfg(summary.config, 'centroTrabajoCodigo'),
      ]);
      final name = _first([
        e.centroNombre,
        _cfg(summary.config, 'centroTrabajoNombre'),
      ]);
      if (code.isEmpty || name.isEmpty) continue;
      rows[code] = [
        code,
        name,
        _cfg(summary.config, 'centroTrabajoCodigoNacional'),
        _cfg(summary.config, 'centroTrabajoPorcentaje', fallback: '100'),
      ];
    }
    return rows.values.toList();
  }

  ZeusMapIndex _indexDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required List<String> nameKeys,
    List<String> codeKeys = const ['codigoZeus', 'codigo_zeus', 'codigo', 'id'],
  }) {
    final out = <String, ZeusCatalogItem>{};
    for (final d in docs) {
      final data = d.data();
      final name = _first([...nameKeys.map((k) => data[k]), d.id]);
      if (name.isEmpty) continue;
      out[_norm(name)] = ZeusCatalogItem(
        code: _first([...codeKeys.map((k) => data[k]), d.id]),
        name: name,
        nationalCode: _first([data['codigoNacional'], data['codigo_nacional']]),
        nit: _first([data['nit'], data['NIT']]),
      );
    }
    return out;
  }
}

class ZeusEmployeeBundle {
  final String userId;
  final String cedula;
  final Map<String, dynamic> user;
  final Map<String, dynamic> hv;
  final Map<String, dynamic> org;
  final Map<String, dynamic> empresaDetail;
  final Map<String, String> zeusData;

  const ZeusEmployeeBundle({
    required this.userId,
    required this.cedula,
    required this.user,
    required this.hv,
    required this.org,
    required this.empresaDetail,
    this.zeusData = const {},
  });

  String zeus(String key) => zeusData[key]?.trim() ?? '';

  String get primerNombre => _first([
    hv['primerNombre'],
    user['primerNombre'],
    _namePart(user['nombres'], 0),
  ]);
  String get segundoNombre => _first([
    hv['segundoNombre'],
    user['segundoNombre'],
    _remainingName(user['nombres'], 1),
  ]);
  String get primerApellido => _first([
    hv['primerApellido'],
    user['primerApellido'],
    _namePart(user['apellidos'], 0),
  ]);
  String get segundoApellido => _first([
    hv['segundoApellido'],
    user['segundoApellido'],
    _remainingName(user['apellidos'], 1),
  ]);
  String get nombreCompleto => _first([
    '${primerNombre.trim()} ${segundoNombre.trim()} ${primerApellido.trim()} ${segundoApellido.trim()}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim(),
    user['nombreCompleto'],
    user['nombre'],
    cedula,
  ]);
  String get tipoDocumento => _first([
    user['tipo_documento'],
    user['tipoDocumento'],
    hv['tipoDocumento'],
  ]);
  String get email => _first([hv['email'], user['correo'], user['email']]);
  String get telefono =>
      _first([hv['telefono'], user['telefono'], user['celular']]);
  String get fotoUrl => _first([
    hv['fotoUrl'],
    hv['foto_url'],
    hv['fotoPerfilUrl'],
    hv['imagenUrl'],
    user['fotoUrl'],
    user['foto_url'],
    user['photoUrl'],
    user['avatarUrl'],
  ]);
  String get fechaNacimiento =>
      _first([hv['fechaNacimiento'], user['fechaNacimiento']]);
  String get numeroHijos => _first([hv['numeroHijos']]);
  String get personasCargo => _first([hv['personasCargo']]);
  String get tipoSangre => _first([hv['tipoSangre']]);
  String get genero => _first([hv['genero']]);
  String get estadoCivil => _first([hv['estadoCivil']]);
  String get direccion => _first([hv['direccion'], user['direccion']]);
  String get barrio => _first([hv['barrio']]);
  String get ciudad =>
      _first([hv['residenciaCiudadNombre'], hv['ciudad'], user['ciudad']]);
  String get residenciaCiudadCod =>
      _first([hv['residenciaCiudadCod'], hv['ciudadCod']]);
  String get lugarNacimiento =>
      _first([hv['nacimientoCiudadNombre'], hv['lugarNacimiento']]);
  String get nacimientoCiudadCod => _first([hv['nacimientoCiudadCod']]);
  String get lugarExpedicion =>
      _first([hv['lugarExpedicion'], hv['lugarExpedicionCiudadNombre']]);
  String get lugarExpedicionCiudadCod =>
      _first([hv['lugarExpedicionCiudadCod']]);
  String get eps => _first([hv['eps'], user['eps'], user['EPS']]);
  String get fondoPensiones =>
      _first([hv['fondoPensiones'], user['fondoPensiones'], user['pension']]);
  String get fondoCesantias =>
      _first([hv['fondoCesantias'], user['fondoCesantias'], user['cesantias']]);
  String get banco =>
      _field(['banco', 'entidadBancaria', 'entidad_bancaria', 'BANCO']);
  String get tipoCuenta => _field([
    'tipoCuenta',
    'tipo_cuenta',
    'tipo_de_cuenta',
    'tipoCuentaBancaria',
    'TIPO_CUENTA',
  ]);
  String get cuentaBancaria => _field([
    'cuentaBancaria',
    'numeroCuenta',
    'numero_cuenta',
    'noCuenta',
    'no_cuenta',
    'n_cuenta',
    'cuenta',
    'CUENTA',
  ]);
  String get sueldoBasico => _field([
    'sueldoBasico',
    'sueldo',
    'salario',
    'salarioBasico',
    'salario_basico',
    'basico',
    'sueldo_básico',
    'SUELDO',
    'SALARIO',
  ]);
  String get fechaInicioContrato => _field([
    'fechaInicioContrato',
    'fechaIngreso',
    'fecha_ingreso',
    'fechaInicio',
    'fecha_inicio',
    'fechaContratacion',
    'fecha_contratacion',
    'FECHA_INGRESO',
  ]);
  String get fechaVencimientoContrato => _field([
    'fechaVencimientoContrato',
    'fechaFinContrato',
    'fecha_fin_contrato',
    'fechaRetiro',
    'fecha_retiro',
    'vencimientoContrato',
  ]);
  String get tipoContrato =>
      _field(['tipoContrato', 'tipo_contrato', 'contratoTipo', 'contrato']);
  String get tipoNomina =>
      _field(['tipoNomina', 'tipo_nomina', 'nomina', 'nómina']);
  String get formaPago => _field([
    'formaPago',
    'forma_pago',
    'metodoPago',
    'metodo_pago',
    'medioPago',
  ]);
  String get horasTrabajadasMes =>
      _field(['horasTrabajadasMes', 'horasMes', 'horas_mes', 'horas']);
  String get unidadNegocio =>
      _field(['unidadNegocio', 'unidad_negocio', 'unidadDeNegocio']);
  String get codigoContrato =>
      _field(['codigoContrato', 'codigo_contrato', 'contratoId', 'idContrato']);
  String get centroTrabajoCodigo => _first([
    _cleanInternalCode(zeus('centroTrabajoCodigo')),
    _cleanInternalCode(
      _field([
        'centroTrabajoCodigo',
        'centro_trabajo_codigo',
        'codigoCentroTrabajo',
        'codigo_centro_trabajo',
        'centroCodigoZeus',
        'codigoZeusCentro',
      ], includeZeus: false),
    ),
  ]);
  String get estado => _first([user['estadoHojaDeVida'], hv['estadoRevision']]);
  String get area => _first([
    org['area'],
    empresaDetail['areaNombre'],
    user['areaNombre'],
    user['area'],
  ]);
  String get areaId =>
      _first([org['areaId'], empresaDetail['areaId'], user['areaId']]);
  String get cargo =>
      _first([org['cargo'], empresaDetail['cargo'], user['cargo']]);
  String get cargoId =>
      _first([org['cargoId'], empresaDetail['cargoId'], user['cargoId']]);
  String get centroNombre => _first([
    org['centroCostos'],
    empresaDetail['centroCostos'],
    user['centroCostos'],
  ]);
  String get centroCodigo => _first([
    org['centro_codigo'],
    empresaDetail['centroCodigo'],
    user['centroCodigo'],
  ]);
  String get jefeId => _first([
    org['jefe_id'],
    org['jefeId'],
    empresaDetail['jefeId'],
    user['jefeId'],
  ]);
  String get descripcionCargo =>
      _first([org['descripcion'], user['descripcionCargo']]);
  String get bachInst => _first([hv['bachInst']]);
  String get uniInst => _first([hv['uniInst']]);
  String get uniCarr => _first([hv['uniCarr']]);
  String get secCarr => _first([hv['secCarr']]);
  String get espProg => _first([hv['espProg']]);
  String get maeProg => _first([hv['maeProg']]);

  String _field(List<String> keys, {bool includeZeus = true}) {
    final values = <dynamic>[];
    if (includeZeus) {
      for (final key in keys) {
        values.add(zeus(key));
      }
    }
    for (final key in keys) {
      values.add(empresaDetail[key]);
    }
    for (final key in keys) {
      values.add(hv[key]);
    }
    for (final key in keys) {
      values.add(user[key]);
    }
    final nested = user['zeus'];
    if (nested is Map) {
      for (final key in keys) {
        values.add(nested[key]);
      }
    }
    final payroll = user['nomina'];
    if (payroll is Map) {
      for (final key in keys) {
        values.add(payroll[key]);
      }
    }
    return _first(values);
  }
}

class ZeusIndexes {
  final ZeusMapIndex cargos;
  final ZeusMapIndex areas;
  final ZeusMapIndex centros;
  final ZeusMapIndex ciudades;
  final ZeusCatalogs catalogs;

  const ZeusIndexes({
    required this.cargos,
    required this.areas,
    required this.centros,
    required this.ciudades,
    required this.catalogs,
  });
}

class ZeusCatalogs {
  final Map<String, ZeusCatalogItem> eps;
  final Map<String, ZeusCatalogItem> pension;
  final Map<String, ZeusCatalogItem> cesantias;
  final Map<String, ZeusCatalogItem> bancos;
  final Map<String, ZeusCatalogItem> profesiones;

  const ZeusCatalogs({
    required this.eps,
    required this.pension,
    required this.cesantias,
    required this.bancos,
    required this.profesiones,
  });
}

typedef ZeusMapIndex = Map<String, ZeusCatalogItem>;

class ZeusCatalogItem {
  final String code;
  final String name;
  final String nationalCode;
  final String nit;

  const ZeusCatalogItem({
    required this.code,
    required this.name,
    this.nationalCode = '',
    this.nit = '',
  });
}

Map<String, dynamic> _empresaDetail(
  Map<String, dynamic> data,
  String empresaId,
) {
  final raw = data['empresasDetalle'];
  if (raw is Map && raw[empresaId] is Map) {
    return Map<String, dynamic>.from(raw[empresaId] as Map);
  }
  return const {};
}

String _first(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _cfg(Map<String, String> config, String key, {String fallback = ''}) {
  final value = config[key]?.trim() ?? '';
  return value.isNotEmpty ? value : fallback;
}

String _namePart(dynamic value, int index) {
  final parts = value?.toString().trim().split(RegExp(r'\s+')) ?? const [];
  if (index >= parts.length) return '';
  return parts[index];
}

String _remainingName(dynamic value, int index) {
  final parts = value?.toString().trim().split(RegExp(r'\s+')) ?? const [];
  if (index >= parts.length) return '';
  return parts.sublist(index).join(' ');
}

String _norm(String value) {
  var text = value.toLowerCase().trim();
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  for (var i = 0; i < from.length; i++) {
    text = text.replaceAll(from[i], to[i]);
  }
  return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String _catalogCode(String name, Map<String, ZeusCatalogItem> index) {
  if (name.trim().isEmpty) return '';
  return index[_norm(name)]?.code ?? '';
}

String _cargoCode(ZeusEmployeeBundle e, ZeusIndexes indexes) {
  return _first([_catalogCode(e.cargo, indexes.cargos), e.cargoId]);
}

String _professionCode(ZeusEmployeeBundle e, ZeusIndexes indexes) {
  final name = _first([e.uniCarr, e.secCarr, e.espProg, e.maeProg]);
  return _catalogCode(name, indexes.catalogs.profesiones);
}

String _cityCode(String code, String name, ZeusIndexes indexes) {
  final direct = code.trim();
  if (direct.isNotEmpty) {
    if (direct.length == 5) return '57$direct';
    return direct;
  }
  final catalog = _catalogCode(name, indexes.ciudades);
  if (catalog.length == 5) return '57$catalog';
  return catalog;
}

String _cleanInternalCode(String value) {
  final text = value.trim();
  if (RegExp(r'^EMPRESA_\d+_', caseSensitive: false).hasMatch(text)) {
    return '';
  }
  return text;
}

String _date(dynamic value) {
  if (value == null) return '';
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  final text = value.toString().trim();
  date ??= DateTime.tryParse(text);
  if (date == null && RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
    final p = text.split('/');
    date = DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
  }
  if (date == null) return text;
  return '${date.year.toString().padLeft(4, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

String _gender(String value) {
  final n = _norm(value);
  if (n.startsWith('m')) return 'M';
  if (n.startsWith('f')) return 'F';
  return value;
}

String _estadoCivil(String value) {
  final n = _norm(value);
  if (n.startsWith('soltero')) return 'S';
  if (n.startsWith('casado')) return 'C';
  if (n.contains('union')) return 'U';
  if (n.startsWith('divorciado')) return 'D';
  if (n.startsWith('viudo')) return 'V';
  return value;
}

String _nivelEstudio(ZeusEmployeeBundle e) {
  if (e.maeProg.isNotEmpty || e.espProg.isNotEmpty) return '05';
  if (e.uniCarr.isNotEmpty) return '04';
  if (e.secCarr.isNotEmpty) return '06';
  if (e.bachInst.isNotEmpty) return '02';
  return '';
}

List<dynamic> _withWidth(List<dynamic> values, int width) {
  return [for (var i = 0; i < width; i++) i < values.length ? values[i] : ''];
}

const _empleadosHeaders = [
  'Identificación',
  'Tipo de Identificación CC=CEDULA TI=TARJETA IDENTIDAD',
  'Primer Nombre',
  'Segundo Nombre',
  'Primer Apellido',
  'Segundo Apellido',
  'Fecha de Nacimiento AAAA/MM/DD',
  'Numero de Hijos',
  'Personas a Cargo',
  'Empleado de Nacionalidad Extranjera',
  'Discapacitado',
  'Tipo Sangre',
  'Cabeza Familia',
  'Sexo',
  'Estado Civil',
  'Código de la División Politica',
  'Lugar Nacimiento',
  'Lugar Expedición Identificación',
  'Email',
  'Nivel de Estudio (00 Ninguno, 01 Primaria, 02 Bachiller, 03 Tecnológico, 04 Universitario, 05 Especialización, 06 Técnico )',
  'Profesión del Empleado',
  'Centro de Formación',
  'Enviar Recibos de Pago por Email',
  'Dirección',
  'Barrio',
  'Urbanización',
  'Numero de Casa',
  'Etapa',
  'Lote',
  'Kilómetro',
  'Manzana',
  'Código Área',
  'Vía',
  'Zona',
  'Tipo Discapacidad',
  'Grado Discapacidad',
  'Porcentaje Discapaciada',
  'No. Carnet Discapacidad',
  'Fecha Expedición Carnet Discapacidad',
  'Fecha Vencimiento Carnet Discapacidad',
  'Telefono',
  'Telefono 2',
  'Pasaporte',
  'Fecha Expedición Pasaporte',
  'Fecha Vencimiento Pasaporte',
  'Certificado Judicial',
  'Fecha Expedición Certificado Judicial',
  'Vencimiento Certificado Judicial',
  'Identificación Cónyuge',
  'Tipo Identificación Cónyuge',
  'Primer Nombre Cónyuge',
  'Segundo Nombre Cónyuge',
  'Primer Apellido Cónyuge',
  'Segundo Apellido Cónyuge',
  'Fecha Nacimiento Cónyuge',
  'Dependiente',
  'Tipo Discapacidad Cónyuge',
  'Grado Discapacidad Cónyuge',
  'Porcentaje Discapacidad Cónyuge',
  'No. Carnet Discapacidad Cónyuge',
  'Fecha Expedición Carnet Discapacidad Cónyuge',
  'Fecha Vencimiento Carnet Discapacidad Cónyuge',
  'Tarjeta Dispositivo Externo',
];

const _contratoHeaders = [
  'Identificación del Empleado',
  'Código del Contrato',
  'Categoria de Contrato',
  'Sueldo Basico',
  'Horas Trabajadas del Mes',
  'Fecha Inicio Contrato',
  'Etapa Prueba 0=NO 1=SI',
  'Tipo de Contrato I=INDEFINIDO D=DEFINIDO F=FINALIZACION DE OBRA',
  'Fecha Vencimiento de Contrato',
  'Tipo Remuneracion U=Unidad de tiempo y unidad de obra  SI=Salario integral',
  'Tipo de Salario F=FIJO V=VARIABLE',
  'Tipo de Nomina',
  'Forma de Pago',
  'Procedimiento Retencion',
  'Base Tipo Retencion 2',
  'Empleado de Alto Riesgo 0=NO  1=si',
  'Empleado Pensionado 0=NO  1=SI',
  'Empleado en Ley 50',
  'Fecha de ingreso a Ley 50 =Fecha de inicio del Contrato',
  'Empleado Estudiante SENA LECTIVA Y UNIVERSITARIO=1 0=SENA PRODUCTIVA Y NORMAL',
  'Etapa del Estudiante',
  'No Usar en Archivo de Pagos de Aportes',
  'Cargo',
  'Fecha de Retiro VACIA',
  'Centro de Trabajo',
  'Unidad de Negocio',
  'Código de la División Politica 5713001=CARTAGENA',
  'Formato Impresión',
  'Zona Geográfica',
  'Código Externo',
  'Declarante de Renta',
  'Aplicar Pago día 31',
  'Periodos Vacaciones',
  'No usar en calculo de utilidades',
  'Tipo Vinculación',
  'Días Legales de Vacaciones',
  'Modalidad Formativa',
  'Régimen de Salud',
  'Jornada de Trabajo Máxima',
  'Horario Nocturno',
  'Regimen Alternativo',
  'Moneda CTS',
  'Entidad CTS',
  'Cuenta CTS',
  'Fondo de Salud',
  'Fondo de Pensión',
  'Fondo de Cesantias',
  'Fondo Pensión Voluntaria',
  'Caja de Compensación',
  'Fondo de Riesgo',
  'No Afiliación Salud',
  'No Afiliación Pensión',
  'No Afiliación Cesantías',
  'No Afiliación Pensión Voluntaria',
  'No Afiliación Caja de Compensación',
  'No Afiliación Riesgo',
  'Tipo Cotizante',
  'SubTipo Cotizante para pensionados',
  'Pensión Empleador',
  'Aplica Prioridad de Descuento',
  'Valor Anticipo',
  'Fecha de Vacaciones Cubiertas',
  'Días de Vacaciones Pendiente',
  'Días de Vacaciones por Disfrutar',
  'Fecha de Intereses de Cesastías',
  'Desahabilitar Seguridad Social',
  'Vacaciones',
  'Primas',
  'Cesantías',
  'Código Pensionado',
  'Centro de Costo',
  'Nivel de Organización',
  'Propiedad Contable 1',
  'Propiedad Contable 2',
  'Propiedad Contable 3',
  'Propiedad Contable 4',
  'Propiedad Contable 5',
  'Cuenta Bancaria',
  'Entidad Bancaria',
  'Oficina Entidad',
  'Ciudad Entidad',
  'Tipo de Cuenta',
  'Cuenta contable x pagar Nómina',
  'Tipo Cuenta Nomina',
  'Cuenta contable x pagar Nómina',
  'Cuenta Efectivo Configuración 1',
  'Cuenta Efectivo Configuración 2',
  'Cuenta Efectivo Configuración 3',
  'Cuenta Efectivo Configuración 4',
  'Cuenta Pago Cheque',
  'Cuenta Cheque Configuración 1',
  'Cuenta Cheque Configuración 2',
  'Cuenta Cheque Configuración 3',
  'Cuenta Cheque Configuración 4',
  'Cuenta Transferencia',
  'Cuenta Transferencia Configuración 1',
  'Cuenta Transferencia Configuración 2',
  'Cuenta Transferencia Configuración 3',
  'Cuenta Transferencia Configuración 4',
  'Pago CxP',
  'CxP Configuración 1',
  'CxP Configuración 2',
  'CxP Configuración 3',
  'CxP Configuración 4',
  'Auxiliar Abierto',
  'Item Contable',
  'Cliente',
  'Base Retención Manual',
  'Jefe',
  'Valida Programación',
  'Valida Entrada',
  'Valida Salida',
  'Comparar Marcación con la Programación',
  'Turno Default',
  'Validar Tipo Marcación',
  'Tipo Marcación 1 ',
  'Tipo Marcación 2 ',
  'Imprime Tiquete Entrada',
  'Imprime Tiquete Salida',
  'Exportar a Nomina',
  'Tipo de Liquidación',
  'Grupo',
  'Código de Barra',
  'Minutos Cotrol Asistencia',
  'Valor/Hora',
  'Minutos Normales',
  'Clasificación Turno',
];

const _familiaresHeaders = [
  'Identificación Empleado',
  'Identificación Pariente',
  'Tipo de Identificación',
  'Primer Nombre',
  'Segundo Nombre',
  'Primer Apellido',
  'Segundo Apellido',
  'Fecha de Nacimiento',
  'Parentesco',
  'Dependiente',
  'Tipo Discapacidad',
  'Grado Discapacidad',
  'Porcentaje Discapaciada',
  'No. Carnet Discapacidad',
  'Fecha Expedición Carnet Discapacidad',
  'Fecha Vencimiento Carnet Discapacidad',
  'Sexo',
];

const _distribucionHeaders = [
  'Código del Contrato',
  'Centro de Costos',
  'Cuenta',
  'Porcentaje',
  'Tipo de cuenta',
  'Unidad de Negocio',
];

const _epsHeaders = [
  'Código EPS',
  'Nombre EPS',
  'Código Nacional',
  'N.I.T EPS',
  'Movimiento Detallado Contable Gasto',
  'Cuenta de Gasto',
  'Complemento 1 Gasto',
  'Complemento 2 Gasto',
  'Complemento 3 Gasto',
  'Complemento 4 Gasto',
  'Pagos a Terceros Gasto',
  'Tipo Centro de Costo Gasto',
  'Centro de Costo Gasto',
  'Tipo Auxiliar Abierto Gasto',
  'Auxiliar Abierto Gasto',
  'Tipo Item Gasto',
  'Item Contable Gasto',
  'Movimiento Detallado Contable Contrapartida',
  'Cuenta Contrapartida del Gasto',
  'Complemento 1 Contrapartida',
  'Complemento 2 Contrapartida',
  'Complemento 3 Contrapartida',
  'Complemento 4 Contrapartida',
  'Pagos a Terceros Contrapartida',
  'Terceros Contrapartida',
  'Tipo Centro de Costo Contrapartida',
  'Centro de Costo Contrapartida',
  'Tipo Auxiliar Abierto Contrapartida',
  'Auxiliar Abierto Contrapartida',
  'Tipo Item Contrapartida',
  'Item Contrapartida',
  'Solicitar Datos de Cuentas de Cartera',
  'Cuenta de Cartera Contrapartida',
  'Proveedor/Cliente Contrapartida',
  'Factura 1 Contrapartida',
  'Factura 2 Contrapartida',
  'Factura 3 Contrapartida',
  'Factura 4 Contrapartida',
  'Tipo Factura Default Contrapartida',
  'Prefijo Factura Contrapartida',
  'Configuración 1 Transacciones Contable Gasto',
  'Configuración 2 Transacciones Contable Gasto',
  'Configuración 3 Transacciones Contable Gasto',
  'Configuración 4 Transacciones Contable Gasto',
  'Descripción Transacciones Contable Gasto',
  'Configuración 1 Transacciones Contable Contrapartida',
  'Configuración 2 Transacciones Contable Contrapartida',
  'Configuración 3 Transacciones Contable Contrapartida',
  'Configuración 4 Transacciones Contable Contrapartida',
  'Descripción Transacciones Contable Contrapartida',
];

const _cesantiasHeaders = [
  'Código Fondo de Cesantias',
  'Nombre del Fondo de Cesantias',
  'Código Nacional',
  'N.I.T Fondo de Cesantias',
  'Cuenta Contrapartida del Gasto',
];

const _cajaHeaders = [
  'Código Caja Compensación',
  'Nombre Caja Compensación',
  'Código Nacional',
  'N.I.T Caja Compensación',
  'Cuenta Contrapartida del Gasto',
];

const _cargosHeaders = [
  'Código del Cargo',
  'Nombre del Cargo',
  'Código Externo del Cargo',
  'Código de Ocupación',
  'Descripción del Perfil del Cargo',
  'Descripción de las Funcionalidades del Cargo',
  'Descripción de las Responsabilidades del Cargo',
];

const _profesionesHeaders = [
  'Código de la Profesión',
  'Nombre de la Profesión',
];

const _centrosHeaders = [
  'Código Centro Trabajo',
  'Nombre Centro Trabajo',
  'Código Nacional',
  'Porcentaje',
];
