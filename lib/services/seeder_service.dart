// lib/services/seeder_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'seed_excel_parser.dart';

class _InferredCatalogs {
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> cargos;
  final List<Map<String, dynamic>> centros;
  const _InferredCatalogs({
    required this.areas,
    required this.cargos,
    required this.centros,
  });
}

class SeederService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Apps base por empresa
  static const List<Map<String, String>> _defaultApps = [
    {
      'appId': 'tareas',
      'nombre': 'Gestión de Tareas',
      'descripcion': 'Crear y hacer seguimiento de tareas',
    },
    {
      'appId': 'notificaciones',
      'nombre': 'Notificaciones',
      'descripcion': 'Mensajería interna / avisos',
    },
  ];

  Future<void> importWorkbook({
    required SeedWorkbook wb,
    required String empresaId,
    required String empresaNombre,
    bool crearUsuarios = true,
  }) async {
    // 0) Catálogos GLOBALes opcionales (si vienen en el Excel)
    if (wb.tiposDocumento.isNotEmpty) {
      await _upsertTiposDocumento(wb.tiposDocumento);
    }
    if (wb.departamentos.isNotEmpty) {
      await _upsertDepartamentos(wb.departamentos);
    }
    if (wb.ciudades.isNotEmpty) {
      await _upsertCiudades(wb.ciudades);
    }

    // 1) Asegurar apps base por empresa
    await _ensureDefaultApps(empresaId);

    // 2) Catálogos por empresa desde hojas + inferencia PERSONAL
    final inferred   = _inferCatalogsFromPersonal(wb.personal);
    final areasAll   = _mergeCatalogByName(_normalizeNombreFallback(wb.areas), inferred.areas);
    final cargosAll  = _mergeCatalogByName(_normalizeNombreFallback(wb.cargos), inferred.cargos);
    final centrosAll = _mergeCentros(wb.centrosCostos, inferred.centros);

    await _upsertAreas(areasAll, empresaId);
    await _upsertCargos(cargosAll, empresaId);
    await _upsertCentros(centrosAll, empresaId);

    // 3) Apps definidas por Excel (además de las default)
    await _upsertApps(wb.apps, empresaId);

    // 4) Personal + estructura + (opcional) usuarios
    if (crearUsuarios) {
      await _upsertPersonalConUsuarios(
        rows: wb.personal,
        empresaId: empresaId,
        empresaNombre: empresaNombre,
      );
    } else {
      await _upsertSoloPersonalEstructura(
        rows: wb.personal,
        empresaId: empresaId,
      );
    }
  }

  // ------------------ DEFAULT APPS ------------------
  Future<void> _ensureDefaultApps(String empresaId) async {
    final col = _db.collection('TBL_APPS');
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    for (final app in _defaultApps) {
      final appId = app['appId']!;
      final docId = '${empresaId}_$appId';
      batch.set(col.doc(docId), {
        'empresaId': empresaId,
        'appId': appId,
        'nombre': app['nombre'],
        'descripcion': app['descripcion'],
        'enabled': true,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ------------------ INFERENCIAS ------------------
  _InferredCatalogs _inferCatalogsFromPersonal(List<Map<String, dynamic>> personal) {
    final areas   = <String>{};
    final cargos  = <String>{};
    final centros = <Map<String, String>>[];
    final seenCentroByName = <String>{};

    for (final r in personal) {
      final area   = _s(r['area']);
      final cargo  = _s(r['cargo']);
      final centro = _s(r['centroCostos']);

      if (area.isNotEmpty) areas.add(area);
      if (cargo.isNotEmpty) cargos.add(cargo);

      if (centro.isNotEmpty) {
        final key = centro.toLowerCase().trim();
        if (!seenCentroByName.contains(key)) {
          seenCentroByName.add(key);
          centros.add({'nombre': centro});
        }
      }
    }

    return _InferredCatalogs(
      areas : areas.map((n) => {'nombre': n}).toList(),
      cargos: cargos.map((n) => {'nombre': n}).toList(),
      centros: centros,
    );
  }

  // Si vienen filas con 'descripcion' pero sin 'nombre', las normalizamos.
  List<Map<String, dynamic>> _normalizeNombreFallback(List<Map<String, dynamic>> rows) {
    return rows.map((r) {
      final nombre = _s(r['nombre']).isNotEmpty ? _s(r['nombre']) : _s(r['descripcion']);
      final out = Map<String, dynamic>.from(r);
      out['nombre'] = nombre;
      return out;
    }).toList();
  }

  List<Map<String, dynamic>> _mergeCatalogByName(
      List<Map<String, dynamic>> a,
      List<Map<String, dynamic>> b,
      ) {
    final out = <String, Map<String, dynamic>>{};
    for (final r in [...a, ...b]) {
      final nombre = _s(r['nombre']).isNotEmpty ? _s(r['nombre']) : _s(r['descripcion']);
      if (nombre.isEmpty) continue;
      final key = nombre.toLowerCase().trim();
      out[key] = {'nombre': nombre};
    }
    return out.values.toList();
  }

  List<Map<String, dynamic>> _mergeCentros(
      List<Map<String, dynamic>> a,
      List<Map<String, dynamic>> b,
      ) {
    final out = <String, Map<String, dynamic>>{};
    for (final r in [...a, ...b]) {
      final nombre = _s(r['nombre']);
      final codigo = _s(r['codigo']);
      if (nombre.isEmpty && codigo.isEmpty) continue;
      final key = (codigo.isNotEmpty ? 'c:$codigo' : 'n:${nombre.toLowerCase().trim()}');
      out[key] = {'nombre': nombre, 'codigo': codigo};
    }
    return out.values.toList();
  }

  // ------------------ UPSERTS POR EMPRESA ------------------
  Future<void> _upsertAreas(List<Map<String, dynamic>> rows, String empresaId) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_AREAS');
    await _writeInChunks(rows, (batch, r) {
      final nombre = _s(r['nombre']).isNotEmpty ? _s(r['nombre']) : _s(r['descripcion']);
      if (nombre.isEmpty) return;
      final areaId = '${empresaId}_${_idFromName(nombre)}';
      batch.set(col.doc(areaId), {
        'empresaId': empresaId,
        'areaId': areaId,
        'nombre': nombre,
        if (_s(r['descripcion']).isNotEmpty) 'descripcion': _s(r['descripcion']),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertCargos(List<Map<String, dynamic>> rows, String empresaId) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_CARGOS');
    await _writeInChunks(rows, (batch, r) {
      final nombre = _s(r['nombre']).isNotEmpty ? _s(r['nombre']) : _s(r['descripcion']);
      if (nombre.isEmpty) return;
      final cargoId = '${empresaId}_${_idFromName(nombre)}';
      batch.set(col.doc(cargoId), {
        'empresaId': empresaId,
        'cargoId': cargoId,
        'nombre': nombre,
        if (_s(r['descripcion']).isNotEmpty) 'descripcion': _s(r['descripcion']),
        if (_s(r['area']).isNotEmpty) 'area': _s(r['area']),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertCentros(List<Map<String, dynamic>> rows, String empresaId) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_CENTROS_COSTOS');
    await _writeInChunks(rows, (batch, r) {
      final nombre = _s(r['nombre']);
      final codigo = _s(r['codigo']);
      if (nombre.isEmpty && codigo.isEmpty) return;
      final idBase = codigo.isNotEmpty ? codigo : _idFromName(nombre);
      final centroId = '${empresaId}_$idBase';
      batch.set(col.doc(centroId), {
        'empresaId': empresaId,
        'centroId': centroId,
        'codigo': codigo.isEmpty ? null : codigo,
        'nombre': nombre,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertApps(List<Map<String, dynamic>> rows, String empresaId) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_APPS');
    await _writeInChunks(rows, (batch, r) {
      final rawId = _s(r['appId']);
      final nombre = _s(r['nombre']);
      final appId = rawId.isNotEmpty ? rawId : _idFromName(nombre);
      if (appId.isEmpty) return;

      final descripcion = _s(r['descripcion']);
      final enabled = _toBool(r['enabled']);

      final docId = '${empresaId}_$appId';
      batch.set(col.doc(docId), {
        'empresaId': empresaId,
        'appId': appId,
        'nombre': nombre.isEmpty ? _pretty(appId) : nombre,
        'descripcion': descripcion.isEmpty ? null : descripcion,
        'enabled': enabled,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // ------------------ UPSERTS GLOBALES (sin empresaId) ------------------
  Future<void> _upsertTiposDocumento(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_TIPO_DOCUMENTO');
    await _writeInChunks(rows, (batch, r) {
      final codigo = _s(r['codigo']).toUpperCase();
      final desc   = _s(r['descripcion']);
      final tipo   = _s(r['tipo_persona']);
      if (codigo.isEmpty) return;
      batch.set(col.doc(codigo), {
        'codigo': codigo,
        'descripcion': desc.isEmpty ? null : desc,
        if (tipo.isNotEmpty) 'tipo_persona': tipo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertDepartamentos(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_DEPARTAMENTOS');
    await _writeInChunks(rows, (batch, r) {
      final codigo = _s(r['codigo_dane']);
      final nombre = _s(r['nombre']);
      if (codigo.isEmpty || nombre.isEmpty) return;
      batch.set(col.doc(codigo), {
        'cod_dane': codigo,
        'nombre': nombre,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertCiudades(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_CIUDADES');
    await _writeInChunks(rows, (batch, r) {
      final codigo = _s(r['codigo_dane']);
      final codDepto = _s(r['cod_departamento']);
      final nombre = _s(r['nombre']);
      if (codigo.isEmpty || nombre.isEmpty) return;
      batch.set(col.doc(codigo), {
        'cod_departamento': codDepto.isEmpty ? null : codDepto,
        'nombre': nombre,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // ------------------ PERSONAL + ESTRUCTURA + USUARIOS ------------------
  Future<void> _upsertSoloPersonalEstructura({
    required List<Map<String, dynamic>> rows,
    required String empresaId,
  }) async {
    if (rows.isEmpty) return;
    final estructuraCol = _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL');

    await _writeInChunks(rows, (batch, r) {
      final cedula = _digits(_s(r['cedula']));
      if (cedula.isEmpty) return;

      final areaNombre  = _s(r['area']);
      final cargoNombre = _s(r['cargo']);
      final centroNom   = _s(r['centroCostos']);

      final areaId   = areaNombre.isEmpty  ? null : '${empresaId}_${_idFromName(areaNombre)}';
      final cargoId  = cargoNombre.isEmpty ? null : '${empresaId}_${_idFromName(cargoNombre)}';
      final centroId = centroNom.isEmpty   ? null : '${empresaId}_${_idFromName(centroNom)}';

      final jefeId = _digits(_s(r['jefeId']));
      final jefeNombre = _s(r['jefeNombre']);
      final cargoJefe = _s(r['cargoJefe']);

      batch.set(estructuraCol.doc(cedula), {
        'empresaId': empresaId,
        'cedula': cedula,
        'area': areaNombre.isEmpty ? null : areaNombre,
        'areaId': areaId,
        'cargo': cargoNombre.isEmpty ? null : cargoNombre,
        'cargoId': cargoId,
        'centroCostos': centroNom.isEmpty ? null : centroNom,
        'centroId': centroId,
        'jefeId': jefeId.isEmpty ? null : jefeId,
        'jefeNombre': jefeNombre.isEmpty ? null : jefeNombre,
        'cargoJefe': cargoJefe.isEmpty ? null : cargoJefe,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upsertPersonalConUsuarios({
    required List<Map<String, dynamic>> rows,
    required String empresaId,
    required String empresaNombre,
  }) async {
    if (rows.isEmpty) return;

    final usuariosCol   = _db.collection('TBL_USUARIOS');
    final estructuraCol = _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL');
    final cedulasCol    = _db.collection('TBL_CEDULAS');

    await _writeInChunks(rows, (batch, r) {
      final cedula = _digits(_s(r['cedula']));
      if (cedula.isEmpty) return;

      final tipoDoc = _s(r['tipo_documento']);
      String nombres = _s(r['nombres']);
      String apellidos = _s(r['apellidos']);
      final nombreCompleto = _s(r['nombreCompleto']);
      final correo = _s(r['correo']);

      if (nombres.isEmpty && apellidos.isEmpty && nombreCompleto.isNotEmpty) {
        final parts = nombreCompleto.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          nombres = parts.sublist(0, parts.length - 1).join(' ');
          apellidos = parts.last;
        } else {
          nombres = nombreCompleto;
          apellidos = '';
        }
      }

      final areaNombre  = _s(r['area']);
      final cargoNombre = _s(r['cargo']);
      final centroNom   = _s(r['centroCostos']);

      final areaId   = areaNombre.isEmpty  ? null : '${empresaId}_${_idFromName(areaNombre)}';
      final cargoId  = cargoNombre.isEmpty ? null : '${empresaId}_${_idFromName(cargoNombre)}';
      final centroId = centroNom.isEmpty   ? null : '${empresaId}_${_idFromName(centroNom)}';

      final jefeId = _digits(_s(r['jefeId']));
      final jefeNombre = _s(r['jefeNombre']);
      final cargoJefe = _s(r['cargoJefe']);

      final estado = _s(r['estado']).isEmpty ? 'activo' : _s(r['estado']).toLowerCase();

      final appsCsv = _s(r['apps']);
      final apps = appsCsv.isEmpty ? <String>[] : _splitApps(appsCsv);

      batch.set(usuariosCol.doc(cedula), {
        'usuario': cedula,
        'cedula': cedula,
        'tipo_documento': tipoDoc.isEmpty ? 'CC' : tipoDoc,
        'nombres': nombres,
        'apellidos': apellidos,
        'correo': correo.isEmpty ? null : correo,
        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'area': areaNombre.isEmpty ? null : areaNombre,
        'areaId': areaId,
        'cargo': cargoNombre.isEmpty ? null : cargoNombre,
        'cargoId': cargoId,
        'centroCostos': centroNom.isEmpty ? null : centroNom,
        'centroId': centroId,
        'jefeId': jefeId.isEmpty ? null : jefeId,
        'jefeNombre': jefeNombre.isEmpty ? null : jefeNombre,
        'cargoJefe': cargoJefe.isEmpty ? null : cargoJefe,
        'estado': estado,
        'apps': apps,
        'password': '123456',
        'needsPasswordChange': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(estructuraCol.doc(cedula), {
        'empresaId': empresaId,
        'cedula': cedula,
        'area': areaNombre.isEmpty ? null : areaNombre,
        'areaId': areaId,
        'cargo': cargoNombre.isEmpty ? null : cargoNombre,
        'cargoId': cargoId,
        'centroCostos': centroNom.isEmpty ? null : centroNom,
        'centroId': centroId,
        'jefeId': jefeId.isEmpty ? null : jefeId,
        'jefeNombre': jefeNombre.isEmpty ? null : jefeNombre,
        'cargoJefe': cargoJefe.isEmpty ? null : cargoJefe,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(cedulasCol.doc(cedula), {
        'cedula': cedula,
        'usuarioRef': usuariosCol.doc(cedula),
        'empresaId': empresaId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // ------------------ HELPERS ------------------
  String _s(dynamic v) => (v == null) ? '' : v.toString().trim();
  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  String _idFromName(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'item_${Random().nextInt(999999)}' : base;
  }

  String _pretty(String appId) {
    var s = appId.replaceAll('_', ' ').replaceAll('-', ' ');
    s = s.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      final f = w[0].toUpperCase();
      final r = w.length > 1 ? w.substring(1).toLowerCase() : '';
      return '$f$r';
    }).join(' ');
  }

  List<String> _splitApps(String csv) {
    return csv
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _writeInChunks(
      List<Map<String, dynamic>> rows,
      void Function(WriteBatch batch, Map<String, dynamic> r) writer,
      ) async {
    const size = 400; // bajo el límite de 500 por batch
    for (int i = 0; i < rows.length; i += size) {
      final chunk = rows.sublist(i, i + size > rows.length ? rows.length : i + size);
      final batch = _db.batch();
      for (final r in chunk) {
        writer(batch, r);
      }
      await batch.commit();
    }
  }

  bool _toBool(dynamic v) {
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'si' || s == 'sí' || s == 'x';
  }
}
