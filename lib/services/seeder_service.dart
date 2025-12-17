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
    final out = <Map<String, dynamic>>[];

    bool matches(Map<String, dynamic> existing, String codigo, String nombreNorm) {
      final existingCodigo = _s(existing['codigo']).toLowerCase();
      final existingNombre = _s(existing['nombre']).toLowerCase();
      if (codigo.isNotEmpty && existingCodigo.isNotEmpty && existingCodigo == codigo) {
        return true;
      }
      if (nombreNorm.isNotEmpty && existingNombre.isNotEmpty && existingNombre == nombreNorm) {
        return true;
      }
      return false;
    }

    for (final r in [...a, ...b]) {
      final nombre = _s(r['nombre']);
      final codigoRaw = _s(r['codigo']);
      final codigo = codigoRaw.toLowerCase();
      final nombreNorm = nombre.toLowerCase().trim();
      if (nombreNorm.isEmpty && codigo.isEmpty) continue;

      Map<String, dynamic>? existing;
      for (final e in out) {
        if (matches(e, codigo, nombreNorm)) {
          existing = e;
          break;
        }
      }

      if (existing != null) {
        if (_s(existing['codigo']).isEmpty && codigoRaw.isNotEmpty) {
          existing['codigo'] = codigoRaw;
        }
        if (_s(existing['nombre']).isEmpty && nombre.isNotEmpty) {
          existing['nombre'] = nombre;
        }
      } else {
        out.add({'nombre': nombre, 'codigo': codigoRaw});
      }
    }

    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _loadExistingUsers(
      Set<String> cedulas) async {
    final out = <String, Map<String, dynamic>>{};
    if (cedulas.isEmpty) return out;

    final col = _db.collection('TBL_USUARIOS');
    final ids = cedulas.toList();
    const chunkSize = 10; // whereIn máximo 10

    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }

    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _loadExistingDocs(
      String collection,
      Set<String> ids,
      ) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;

    final col = _db.collection(collection);
    const chunkSize = 10;
    final allIds = ids.toList();

    for (int i = 0; i < allIds.length; i += chunkSize) {
      final chunk = allIds.sublist(i, i + chunkSize > allIds.length ? allIds.length : i + chunkSize);
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }

    return out;
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

    final cedulas = rows
        .map((r) => _digits(_s(r['cedula'])))
        .where((c) => c.isNotEmpty)
        .toSet();
    final existingUsers = await _loadExistingUsers(cedulas);
    final existingEstructuras = await _loadExistingDocs('TBL_ESTRUCTURA_ORGANIZACIONAL', cedulas);
    final existingCedulasDocs = await _loadExistingDocs('TBL_CEDULAS', cedulas);

    await _writeInChunks(rows, (batch, r) {
      final cedula = _digits(_s(r['cedula']));
      if (cedula.isEmpty) return;

      final existing = existingUsers[cedula];
      final exists = existing != null;

      final tipoDoc = _s(r['tipo_documento']);
      String nombres = _s(r['nombres']).isNotEmpty
          ? _s(r['nombres'])
          : _s(existing?['nombres']);
      String apellidos = _s(r['apellidos']).isNotEmpty
          ? _s(r['apellidos'])
          : _s(existing?['apellidos']);
      final nombreCompleto = _s(r['nombreCompleto']);
      final correo = _s(r['correo']).isNotEmpty
          ? _s(r['correo'])
          : _s(existing?['correo']);
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

      final areaNombre  = _s(r['area']).isNotEmpty ? _s(r['area']) : _s(existing?['area']);
      final cargoNombre = _s(r['cargo']).isNotEmpty ? _s(r['cargo']) : _s(existing?['cargo']);
      final centroNom   = _s(r['centroCostos']).isNotEmpty
          ? _s(r['centroCostos'])
          : _s(existing?['centroCostos']);

      final areaId   = areaNombre.isEmpty  ? '' : '${empresaId}_${_idFromName(areaNombre)}';
      final cargoId  = cargoNombre.isEmpty ? '' : '${empresaId}_${_idFromName(cargoNombre)}';
      final centroId = centroNom.isEmpty   ? '' : '${empresaId}_${_idFromName(centroNom)}';

      final jefeId = _digits(_s(r['jefeId']).isNotEmpty ? _s(r['jefeId']) : _s(existing?['jefeId']));
      final jefeNombre = _s(r['jefeNombre']).isNotEmpty
          ? _s(r['jefeNombre'])
          : _s(existing?['jefeNombre']);
      final cargoJefe = _s(r['cargoJefe']).isNotEmpty
          ? _s(r['cargoJefe'])
          : _s(existing?['cargoJefe']);

      final estadoRaw = _s(r['estado']);
      final estado = estadoRaw.isNotEmpty
          ? estadoRaw.toLowerCase()
          : (_s(existing?['estado']).isNotEmpty ? _s(existing?['estado']) : 'activo');

      final appsCsv = _s(r['apps']);
      final apps = appsCsv.isEmpty ? <String>[] : _splitApps(appsCsv);
      final existingApps =
      (existing?['apps'] as List<dynamic>? ?? []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      final effectiveApps = apps.isNotEmpty ? apps : existingApps;

      // Permitir múltiples empresas por usuario sin sobrescribir la principal existente
      final empresas = <String>[];
      final existingEmpresaId = _s(existing?['empresaId']);
      final existingEmpresasList = existing?['empresas'] as List<dynamic>?;
      final existingAreaId = _s(existing?['areaId']);
      final existingCargoId = _s(existing?['cargoId']);
      final existingCentroId = _s(existing?['centroId']);

      if (existingEmpresaId.isNotEmpty) empresas.add(existingEmpresaId);
      if (existingEmpresasList != null) {
        for (final e in existingEmpresasList) {
          final id = _s(e);
          if (id.isNotEmpty && !empresas.contains(id)) {
            empresas.add(id);
          }
        }
      }
      if (!empresas.contains(empresaId)) {
        empresas.add(empresaId);
      }

      final primaryEmpresaId = existingEmpresaId.isNotEmpty ? existingEmpresaId : empresaId;
      final primaryEmpresaNombre = _s(existing?['empresaNombre']).isNotEmpty
          ? _s(existing?['empresaNombre'])
          : empresaNombre;

      final updatingPrimary = primaryEmpresaId == empresaId || existingEmpresaId.isEmpty;

      final areaForPrimary = updatingPrimary
          ? (areaNombre.isNotEmpty ? areaNombre : _s(existing?['area']))
          : _s(existing?['area']);
      final cargoForPrimary = updatingPrimary
          ? (cargoNombre.isNotEmpty ? cargoNombre : _s(existing?['cargo']))
          : _s(existing?['cargo']);
      final centroForPrimary = updatingPrimary
          ? (centroNom.isNotEmpty ? centroNom : _s(existing?['centroCostos']))
          : _s(existing?['centroCostos']);
      final jefeIdForPrimary = updatingPrimary
          ? (jefeId.isNotEmpty ? jefeId : _s(existing?['jefeId']))
          : _s(existing?['jefeId']);
      final jefeNombreForPrimary = updatingPrimary
          ? (jefeNombre.isNotEmpty ? jefeNombre : _s(existing?['jefeNombre']))
          : _s(existing?['jefeNombre']);
      final cargoJefeForPrimary = updatingPrimary
          ? (cargoJefe.isNotEmpty ? cargoJefe : _s(existing?['cargoJefe']))
          : _s(existing?['cargoJefe']);

      final areaIdForPrimary = updatingPrimary
          ? (areaId.isNotEmpty ? areaId : existingAreaId)
          : existingAreaId;
      final cargoIdForPrimary = updatingPrimary
          ? (cargoId.isNotEmpty ? cargoId : existingCargoId)
          : existingCargoId;
      final centroIdForPrimary = updatingPrimary
          ? (centroId.isNotEmpty ? centroId : existingCentroId)
          : existingCentroId;

      final empresasDetalle = <String, dynamic>{};
      final existingEmpresasDetalle = existing?['empresasDetalle'] as Map<String, dynamic>?;
      if (existingEmpresasDetalle != null) {
        empresasDetalle.addAll(existingEmpresasDetalle);
      }
      empresasDetalle[empresaId] = {
        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'area': areaNombre.isEmpty ? null : areaNombre,
        'areaId': areaId.isEmpty ? null : areaId,
        'cargo': cargoNombre.isEmpty ? null : cargoNombre,
        'cargoId': cargoId.isEmpty ? null : cargoId,
        'centroCostos': centroNom.isEmpty ? null : centroNom,
        'centroId': centroId.isEmpty ? null : centroId,
        'jefeId': jefeId.isEmpty ? null : jefeId,
        'jefeNombre': jefeNombre.isEmpty ? null : jefeNombre,
        'cargoJefe': cargoJefe.isEmpty ? null : cargoJefe,
      };

      final userPayload = <String, dynamic>{
        'usuario': cedula,
        'cedula': cedula,
        'tipo_documento': tipoDoc.isNotEmpty
            ? tipoDoc
            : (_s(existing?['tipo_documento']).isNotEmpty ? _s(existing?['tipo_documento']) : 'CC'),
        'nombres': nombres,
        'apellidos': apellidos,
        'correo': correo.isEmpty ? null : correo,
        'empresaId': primaryEmpresaId,
        'empresaNombre': primaryEmpresaNombre,
        'empresas': empresas,
        'empresasDetalle': empresasDetalle,
        'area': areaForPrimary.isEmpty ? null : areaForPrimary,
        'areaId': areaIdForPrimary.isEmpty ? null : areaIdForPrimary,
        'cargo': cargoForPrimary.isEmpty ? null : cargoForPrimary,
        'cargoId': cargoIdForPrimary.isEmpty ? null : cargoIdForPrimary,
        'centroCostos': centroForPrimary.isEmpty ? null : centroForPrimary,
        'centroId': centroIdForPrimary.isEmpty ? null : centroIdForPrimary,
        'jefeId': jefeIdForPrimary.isEmpty ? null : jefeIdForPrimary,
        'jefeNombre': jefeNombreForPrimary.isEmpty ? null : jefeNombreForPrimary,
        'cargoJefe': cargoJefeForPrimary.isEmpty ? null : cargoJefeForPrimary,
        'estado': estado,
        'apps': effectiveApps,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!exists) {
        userPayload.addAll({
          'password': '123456',
          'needsPasswordChange': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(usuariosCol.doc(cedula), userPayload, SetOptions(merge: true));
      final existingEstr = existingEstructuras[cedula];
      final existingEstrEmpresaId = _s(existingEstr?['empresaId']);
      final estructuraPrimaryEmpresa = existingEstrEmpresaId.isNotEmpty ? existingEstrEmpresaId : empresaId;
      final estructuraMatchesPrimary = estructuraPrimaryEmpresa == empresaId || existingEstrEmpresaId.isEmpty;
      final estructuraArea = estructuraMatchesPrimary
          ? (areaNombre.isNotEmpty ? areaNombre : _s(existingEstr?['area']))
          : _s(existingEstr?['area']);
      final estructuraCargo = estructuraMatchesPrimary
          ? (cargoNombre.isNotEmpty ? cargoNombre : _s(existingEstr?['cargo']))
          : _s(existingEstr?['cargo']);
      final estructuraCentro = estructuraMatchesPrimary
          ? (centroNom.isNotEmpty ? centroNom : _s(existingEstr?['centroCostos']))
          : _s(existingEstr?['centroCostos']);
      final estructuraJefeId = estructuraMatchesPrimary
          ? (jefeId.isNotEmpty ? jefeId : _s(existingEstr?['jefeId']))
          : _s(existingEstr?['jefeId']);
      final estructuraJefeNombre = estructuraMatchesPrimary
          ? (jefeNombre.isNotEmpty ? jefeNombre : _s(existingEstr?['jefeNombre']))
          : _s(existingEstr?['jefeNombre']);
      final estructuraCargoJefe = estructuraMatchesPrimary
          ? (cargoJefe.isNotEmpty ? cargoJefe : _s(existingEstr?['cargoJefe']))
          : _s(existingEstr?['cargoJefe']);

      final estructuraAreaId = estructuraMatchesPrimary
          ? (areaId.isNotEmpty ? areaId : _s(existingEstr?['areaId']))
          : _s(existingEstr?['areaId']);
      final estructuraCargoId = estructuraMatchesPrimary
          ? (cargoId.isNotEmpty ? cargoId : _s(existingEstr?['cargoId']))
          : _s(existingEstr?['cargoId']);
      final estructuraCentroId = estructuraMatchesPrimary
          ? (centroId.isNotEmpty ? centroId : _s(existingEstr?['centroId']))
          : _s(existingEstr?['centroId']);

      final estructuraDetalle = <String, dynamic>{};
      final existingEstrDetalle = existingEstr?['empresasDetalle'] as Map<String, dynamic>?;
      if (existingEstrDetalle != null) estructuraDetalle.addAll(existingEstrDetalle);
      estructuraDetalle[empresaId] = {
        'empresaId': empresaId,
        'empresaNombre': empresaNombre,
        'area': areaNombre.isNotEmpty ? areaNombre : estructuraArea,
        'areaId': areaId.isNotEmpty
            ? areaId
            : (estructuraAreaId.isNotEmpty ? estructuraAreaId : null),
        'cargo': cargoNombre.isNotEmpty ? cargoNombre : estructuraCargo,
        'cargoId': cargoId.isNotEmpty
            ? cargoId
            : (estructuraCargoId.isNotEmpty ? estructuraCargoId : null),
        'centroCostos': centroNom.isNotEmpty ? centroNom : estructuraCentro,
        'centroId': centroId.isNotEmpty
            ? centroId
            : (estructuraCentroId.isNotEmpty ? estructuraCentroId : null),
        'jefeId': jefeId.isNotEmpty ? jefeId : estructuraJefeId,
        'jefeNombre': jefeNombre.isNotEmpty ? jefeNombre : estructuraJefeNombre,
        'cargoJefe': cargoJefe.isNotEmpty ? cargoJefe : estructuraCargoJefe,
      };

      batch.set(estructuraCol.doc(cedula), {
        'empresaId': estructuraPrimaryEmpresa,
        'cedula': cedula,
        'empresas': FieldValue.arrayUnion([empresaId]),
        'empresasDetalle': estructuraDetalle,
        'area': estructuraArea.isEmpty ? null : estructuraArea,
        'areaId': estructuraAreaId.isEmpty ? null : estructuraAreaId,
        'cargo': estructuraCargo.isEmpty ? null : estructuraCargo,
        'cargoId': estructuraCargoId.isEmpty ? null : estructuraCargoId,
        'centroCostos': estructuraCentro.isEmpty ? null : estructuraCentro,
        'centroId': estructuraCentroId.isEmpty ? null : estructuraCentroId,
        'jefeId': estructuraJefeId.isEmpty ? null : estructuraJefeId,
        'jefeNombre': estructuraJefeNombre.isEmpty ? null : estructuraJefeNombre,
        'cargoJefe': estructuraCargoJefe.isEmpty ? null : estructuraCargoJefe,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final existingCedulaDoc = existingCedulasDocs[cedula];
      final cedulaPrimaryEmpresa = _s(existingCedulaDoc?['empresaId']).isNotEmpty
          ? _s(existingCedulaDoc?['empresaId'])
          : empresaId;

      batch.set(cedulasCol.doc(cedula), {
        'cedula': cedula,
        'usuarioRef': usuariosCol.doc(cedula),
        'empresaId': cedulaPrimaryEmpresa,
        'empresas': FieldValue.arrayUnion([empresaId]),
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
