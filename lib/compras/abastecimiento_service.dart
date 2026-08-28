import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import '../services/compras_abastecimiento_excel_parser.dart';
import 'abastecimiento_models.dart';
import 'abastecimiento_recepcion_sync.dart';
import 'compras_models.dart';
import 'compras_recepcion_logic.dart';

class AbastecimientoImportResult {
  final int creados;
  final int actualizados;
  final int sinCambios;
  final int omitidosCatalogo;

  const AbastecimientoImportResult({
    required this.creados,
    required this.actualizados,
    required this.sinCambios,
    this.omitidosCatalogo = 0,
  });

  int get procesados => creados + actualizados + sinCambios;
}

class AbastecimientoCatalogValidation {
  final List<AbastecimientoImportRow> filas;
  final List<AbastecimientoExcelIssue> incidencias;
  final List<String> proveedoresPendientes;
  final List<String> productosPendientes;
  final List<String> gruposPendientes;

  const AbastecimientoCatalogValidation({
    required this.filas,
    required this.incidencias,
    required this.proveedoresPendientes,
    required this.productosPendientes,
    required this.gruposPendientes,
  });
}

class AbastecimientoService {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  AbastecimientoService({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Stream<List<AbastecimientoDoc>> stream(String empresaId) => _db
      .collection(kAbastecimientoCollection)
      .where('empresaId', isEqualTo: empresaId.trim())
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => AbastecimientoDoc.fromMap(doc.id, doc.data()))
            .where((row) => !row.eliminado)
            .toList();
        rows.sort((a, b) {
          final left = a.fechaProgramada;
          final right = b.fechaProgramada;
          if (left == null && right == null) {
            return a.proveedor.compareTo(b.proveedor);
          }
          if (left == null) return 1;
          if (right == null) return -1;
          return left.compareTo(right);
        });
        return rows;
      });

  Stream<List<AbastecimientoReporteDoc>> streamReportes(String empresaId) => _db
      .collection(kAbastecimientoReportesCollection)
      .where('empresaId', isEqualTo: empresaId.trim())
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => AbastecimientoReporteDoc.fromMap(doc.id, doc.data()))
            .toList();
        rows.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
        return rows.take(40).toList();
      });

  Future<int> generarReportesAhora({required String empresaId}) async {
    final callable = _functions.httpsCallable(
      'comprasGenerarReporteAbastecimiento',
    );
    final result = await callable.call<Map<String, dynamic>>({
      'empresaId': empresaId.trim(),
    });
    return (result.data['generados'] as num?)?.toInt() ?? 0;
  }

  /// Repara vínculos históricos y deja ambos documentos enlazados. Las nuevas
  /// recepciones se sincronizan en tiempo real desde [ComprasService].
  Future<int> sincronizarConRecepciones({
    required String empresaId,
    required String usuarioId,
  }) async {
    final empresa = empresaId.trim();
    final snapshots = await Future.wait([
      _db
          .collection(kAbastecimientoCollection)
          .where('empresaId', isEqualTo: empresa)
          .get(),
      _db
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: empresa)
          .get(),
    ]);
    final entregas = snapshots[0].docs;
    final recepciones =
        snapshots[1].docs
            .map(
              (doc) => (
                snapshot: doc,
                recepcion: RecepcionDoc.fromMap(doc.id, doc.data()),
              ),
            )
            .toList()
          ..sort((a, b) => b.recepcion.fecha.compareTo(a.recepcion.fecha));

    var actualizados = 0;
    var operations = 0;
    var batch = _db.batch();
    Future<void> flush() async {
      if (operations == 0) return;
      await batch.commit();
      batch = _db.batch();
      operations = 0;
    }

    for (final snapshot in entregas) {
      final entrega = AbastecimientoDoc.fromMap(snapshot.id, snapshot.data());
      if (entrega.eliminado ||
          (entrega.recepcionId.isNotEmpty &&
              entrega.estado == AbastecimientoEstado.recibido)) {
        continue;
      }
      ({
        QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
        RecepcionDoc recepcion,
      })?
      match;
      for (final candidate in recepciones) {
        if (abastecimientoCoincideConRecepcion(entrega, candidate.recepcion)) {
          match = candidate;
          break;
        }
      }
      if (match == null) continue;

      final now = Timestamp.now();
      final history = [
        ...entrega.historial,
        if (entrega.estado != AbastecimientoEstado.recibido)
          AbastecimientoCambio(
            campo: 'estado',
            anterior: entrega.estado.value,
            nuevo: AbastecimientoEstado.recibido.value,
            origen: 'recepcion',
            usuarioId: usuarioId,
            fecha: now,
          ),
        AbastecimientoCambio(
          campo: 'recepcionId',
          anterior: entrega.recepcionId,
          nuevo: match.recepcion.id,
          origen: 'recepcion',
          usuarioId: usuarioId,
          fecha: now,
        ),
      ];
      batch.update(snapshot.reference, {
        'estado': AbastecimientoEstado.recibido.value,
        if (entrega.estado != AbastecimientoEstado.recibido)
          'estadoAntesRecepcion': entrega.estado.value,
        'recepcionId': match.recepcion.id,
        'fechaRecibido': match.recepcion.fecha,
        'novedadEstado':
            'Vinculada con recepción ${match.recepcion.id} durante sincronización.',
        'actualizadoPor': usuarioId,
        'updatedAt': now,
        'historial': history
            .skip(history.length > 100 ? history.length - 100 : 0)
            .map((item) => item.toMap())
            .toList(),
      });
      batch.update(match.snapshot.reference, {
        'abastecimientoIds': FieldValue.arrayUnion([entrega.id]),
      });
      actualizados++;
      operations += 2;
      if (operations >= 400) await flush();
    }
    await flush();
    return actualizados;
  }

  Future<List<ProveedorDoc>> getProveedoresActivos(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: empresaId.trim())
        .get();
    final result = snapshot.docs
        .map((doc) => ProveedorDoc.fromMap(doc.id, doc.data()))
        .where((provider) => provider.activo)
        .toList();
    result.sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
    return result;
  }

  Future<List<ProductoDoc>> getProductos(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_COMPRAS_PRODUCTOS')
        .where('empresaId', isEqualTo: empresaId.trim())
        .get();
    final result = snapshot.docs
        .map((doc) => ProductoDoc.fromMap(doc.id, doc.data()))
        .toList();
    result.sort((a, b) => a.nombre.compareTo(b.nombre));
    return result;
  }

  Future<List<ComprasGrupoDoc>> getGrupos(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_COMPRAS_GRUPOS')
        .where('empresaId', isEqualTo: empresaId.trim())
        .get();
    final result = snapshot.docs
        .map((doc) => ComprasGrupoDoc.fromMap(doc.id, doc.data()))
        .where((group) => group.activo)
        .toList();
    result.sort((a, b) => a.nombre.compareTo(b.nombre));
    return result;
  }

  /// Devuelve únicamente las bodegas configuradas para la empresa activa.
  /// Conserva las mismas fuentes de compatibilidad usadas por Recepción.
  Future<List<String>> getBodegas(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return const [];

    final bodegas = <String>[];
    try {
      final snapshot = await _db
          .collection('TBL_COMPRAS_BODEGAS')
          .where('empresaId', isEqualTo: id)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['activo'] == false) continue;
        final nombre = (data['nombre'] ?? data['bodega'] ?? data['label'] ?? '')
            .toString()
            .trim();
        if (nombre.isNotEmpty) bodegas.add(nombre);
      }
    } catch (_) {
      // Continúa con las fuentes de compatibilidad de la empresa.
    }

    String empresaNombre = '';
    if (bodegas.isEmpty) {
      try {
        final empresa = await _db.collection('TBL_EMPRESAS').doc(id).get();
        final data = empresa.data() ?? const <String, dynamic>{};
        empresaNombre = (data['nombre'] ?? data['razonSocial'] ?? '')
            .toString()
            .trim();
        final raw = data['bodegas'];
        if (raw is List) {
          for (final item in raw) {
            final nombre = item is Map
                ? (item['nombre'] ?? item['bodega'] ?? item['label'] ?? '')
                      .toString()
                      .trim()
                : item.toString().trim();
            if (nombre.isNotEmpty) bodegas.add(nombre);
          }
        }
      } catch (_) {
        // Continúa con el catálogo legado, limitado a la empresa activa.
      }
    }

    if (bodegas.isEmpty) {
      bodegas.addAll(
        bodegasLegacyParaEmpresa(empresaId: id, empresaNombre: empresaNombre),
      );
    }
    final unique = <String, String>{};
    for (final bodega in bodegas) {
      unique.putIfAbsent(bodega.toLowerCase(), () => bodega);
    }
    return unique.values.toList()..sort((a, b) => a.compareTo(b));
  }

  Future<AbastecimientoCatalogValidation> validarCatalogo({
    required String empresaId,
    required List<AbastecimientoImportRow> filas,
  }) async {
    final empresa = empresaId.trim();
    final results = await Future.wait([
      _db
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: empresa)
          .get(),
      _db
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: empresa)
          .get(),
      _db
          .collection('TBL_COMPRAS_GRUPOS')
          .where('empresaId', isEqualTo: empresa)
          .get(),
    ]);
    final providerSnapshot = results[0];
    final receptionSnapshot = results[1];
    final groupSnapshot = results[2];

    final providers = <String, ProveedorDoc>{};
    for (final doc in providerSnapshot.docs) {
      final provider = ProveedorDoc.fromMap(doc.id, doc.data());
      providers[_catalogKey(provider.razonSocial)] = provider;
    }
    final receptions = <String, List<RecepcionDoc>>{};
    for (final doc in receptionSnapshot.docs) {
      final reception = RecepcionDoc.fromMap(doc.id, doc.data());
      final order = reception.ordenCompra;
      if (order.trim().isNotEmpty) {
        receptions.putIfAbsent(_catalogKey(order), () => []).add(reception);
      }
    }
    final groups = <String, ComprasGrupoDoc>{};
    for (final doc in groupSnapshot.docs) {
      final group = ComprasGrupoDoc.fromMap(doc.id, doc.data());
      if (!group.activo) continue;
      groups[_groupKey(group.nombre)] = group;
      groups[_groupKey(group.id)] = group;
    }

    final valid = <AbastecimientoImportRow>[];
    final issues = <AbastecimientoExcelIssue>[];
    final missingProviders = <String, String>{};
    final missingGroups = <String, String>{};
    for (final row in filas) {
      if (row.ordenCompra.trim().isEmpty) {
        issues.add(
          AbastecimientoExcelIssue(
            hoja: row.hoja,
            fila: row.fila,
            mensaje: 'Falta la orden de compra (OC/OS).',
          ),
        );
        continue;
      }

      final provider = providers[_catalogKey(row.proveedor)];
      if (provider == null) {
        missingProviders.putIfAbsent(
          _catalogKey(row.proveedor),
          () => row.proveedor,
        );
        issues.add(
          AbastecimientoExcelIssue(
            hoja: row.hoja,
            fila: row.fila,
            mensaje:
                'Proveedor "${row.proveedor}" no existe; debe crearse en Proveedores.',
          ),
        );
        continue;
      }
      if (!provider.activo) {
        issues.add(
          AbastecimientoExcelIssue(
            hoja: row.hoja,
            fila: row.fila,
            mensaje: 'El proveedor "${provider.razonSocial}" está inactivo.',
          ),
        );
        continue;
      }

      final categories = {
        for (final category in provider.categorias)
          _catalogKey(category): category,
      };
      String category;
      if (row.categoria.trim().isEmpty && categories.length == 1) {
        category = categories.values.first;
      } else {
        category = categories[_catalogKey(row.categoria)] ?? '';
      }
      if (category.isEmpty) {
        issues.add(
          AbastecimientoExcelIssue(
            hoja: row.hoja,
            fila: row.fila,
            mensaje: row.categoria.trim().isEmpty
                ? 'Falta categoría o el proveedor tiene varias para escoger.'
                : 'La categoría "${row.categoria}" no está asociada a ${provider.razonSocial}.',
          ),
        );
        continue;
      }

      final group = groups[_groupKey(row.grupo)];
      if (group == null) {
        missingGroups.putIfAbsent(_groupKey(row.grupo), () => row.grupo);
        issues.add(
          AbastecimientoExcelIssue(
            hoja: row.hoja,
            fila: row.fila,
            mensaje: row.grupo.trim().isEmpty
                ? 'Falta el grupo de Compras.'
                : 'Grupo "${row.grupo}" no existe en el catálogo de Compras.',
          ),
        );
        continue;
      }
      RecepcionDoc? reception;
      for (final candidate
          in receptions[_catalogKey(row.ordenCompra)] ??
              const <RecepcionDoc>[]) {
        final sameProvider = candidate.proveedorId.isNotEmpty
            ? candidate.proveedorId == provider.id
            : _catalogKey(candidate.razonSocial) ==
                  _catalogKey(provider.razonSocial);
        final sameGroup =
            candidate.grupoId.isEmpty || candidate.grupoId == group.id;
        final sameProduct = candidate.productos.any(
          (item) => _catalogKey(item.nombre) == _catalogKey(row.producto),
        );
        if (sameProvider && sameGroup && sameProduct) {
          reception = candidate;
          break;
        }
      }
      valid.add(
        row.copyWith(
          proveedorId: provider.id,
          proveedor: provider.razonSocial,
          categoria: category,
          productoId: '',
          producto: row.producto.trim(),
          grupoId: group.id,
          grupo: group.nombre,
          recepcionId: reception?.id ?? '',
          fechaRecibido: reception?.fecha.toDate() ?? row.fechaRecibido,
        ),
      );
    }

    final pending = missingProviders.values.toList()
      ..sort((a, b) => a.compareTo(b));
    final pendingGroups =
        missingGroups.values.where((value) => value.trim().isNotEmpty).toList()
          ..sort((a, b) => a.compareTo(b));
    return AbastecimientoCatalogValidation(
      filas: valid,
      incidencias: issues,
      proveedoresPendientes: pending,
      productosPendientes: const [],
      gruposPendientes: pendingGroups,
    );
  }

  Future<AbastecimientoImportResult> importar({
    required String empresaId,
    required String archivoNombre,
    required String usuarioId,
    required List<AbastecimientoImportRow> filas,
  }) async {
    final empresa = empresaId.trim();
    if (empresa.isEmpty) throw StateError('No hay una empresa activa.');
    if (filas.isEmpty) {
      return const AbastecimientoImportResult(
        creados: 0,
        actualizados: 0,
        sinCambios: 0,
      );
    }

    final validation = await validarCatalogo(empresaId: empresa, filas: filas);
    final validRows = validation.filas;
    if (validRows.isEmpty) {
      return AbastecimientoImportResult(
        creados: 0,
        actualizados: 0,
        sinCambios: 0,
        omitidosCatalogo: validation.incidencias.length,
      );
    }

    final currentSnapshot = await _db
        .collection(kAbastecimientoCollection)
        .where('empresaId', isEqualTo: empresa)
        .get();
    final existingByKey = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in currentSnapshot.docs)
        (doc.data()['importKey'] ?? '').toString(): doc,
    };

    final now = Timestamp.now();
    final batchId = now.millisecondsSinceEpoch.toString();
    var created = 0;
    var updated = 0;
    var unchanged = 0;
    var batch = _db.batch();
    var operations = 0;
    final processedKeys = <String>{};

    Future<void> flush() async {
      if (operations == 0) return;
      await batch.commit();
      batch = _db.batch();
      operations = 0;
    }

    for (final row in validRows) {
      if (!processedKeys.add(row.importKey)) {
        unchanged++;
        continue;
      }
      final existing = existingByKey[row.importKey];
      final ref =
          existing?.reference ??
          _db
              .collection(kAbastecimientoCollection)
              .doc(_documentId(empresa, row.importKey));

      if (existing == null) {
        final estado =
            row.estadoExplicito ??
            (row.fechaRecibido != null || row.recepcionId.isNotEmpty
                ? AbastecimientoEstado.recibido
                : AbastecimientoEstado.programado);
        final initial = AbastecimientoCambio(
          campo: 'registro',
          anterior: '',
          nuevo: 'Creado desde ${row.hoja}, fila ${row.fila}',
          origen: 'excel',
          usuarioId: usuarioId,
          fecha: now,
        );
        final doc = AbastecimientoDoc(
          empresaId: empresa,
          importKey: row.importKey,
          hojaOrigen: row.hoja,
          filaOrigen: row.fila,
          proveedorId: row.proveedorId,
          proveedor: row.proveedor,
          categoria: row.categoria,
          productoId: row.productoId,
          producto: row.producto,
          grupoId: row.grupoId,
          grupo: row.grupo,
          destino: row.destino,
          condicion: row.condicion,
          cantidad: row.cantidad,
          unidad: row.unidad,
          precio: row.precio,
          fechaProgramada: row.fechaProgramada,
          fechaSegundaEntrega: row.fechaSegundaEntrega,
          ordenCompra: row.ordenCompra,
          recepcionId: row.recepcionId,
          fechaRecibido: row.fechaRecibido,
          numeroEntrada: row.numeroEntrada,
          entradaRegistradaPor: row.numeroEntrada.trim().isEmpty
              ? ''
              : usuarioId,
          entradaRegistradaAt: row.numeroEntrada.trim().isEmpty ? null : now,
          consumoDesde: row.fechaProgramada == null
              ? null
              : inicioPeriodoConsumo(row.fechaProgramada!),
          consumoHasta: row.fechaProgramada == null
              ? null
              : finPeriodoConsumo(inicioPeriodoConsumo(row.fechaProgramada!)),
          estado: estado,
          observaciones: row.observaciones,
          pendencias: row.pendencias,
          archivoOrigen: archivoNombre,
          importBatchId: batchId,
          creadoPor: usuarioId,
          actualizadoPor: usuarioId,
          createdAt: now,
          updatedAt: now,
          historial: [initial],
        );
        batch.set(ref, doc.toMap());
        created++;
        operations++;
      } else {
        final current = AbastecimientoDoc.fromMap(existing.id, existing.data());
        final data = current.toMap();
        final changes = <AbastecimientoCambio>[];

        void changeText(String field, String next, {bool acceptEmpty = false}) {
          if (!acceptEmpty && next.trim().isEmpty) return;
          final old = (data[field] ?? '').toString();
          if (old.trim() == next.trim()) return;
          data[field] = next.trim();
          changes.add(
            _change(field, old, next.trim(), usuarioId, now, 'excel'),
          );
        }

        void changeNumber(String field, double? next) {
          if (next == null) return;
          final old = (data[field] as num?)?.toDouble();
          if (old == next) return;
          data[field] = next;
          changes.add(_change(field, '$old', '$next', usuarioId, now, 'excel'));
        }

        void changeDate(String field, DateTime? next) {
          if (next == null) return;
          final oldTimestamp = data[field] as Timestamp?;
          final old = oldTimestamp?.toDate();
          if (old != null && _sameMoment(old, next)) return;
          data[field] = Timestamp.fromDate(next);
          changes.add(
            _change(
              field,
              old?.toIso8601String() ?? '',
              next.toIso8601String(),
              usuarioId,
              now,
              'excel',
            ),
          );
        }

        changeText('proveedorId', row.proveedorId);
        changeText('proveedor', row.proveedor);
        changeText('categoria', row.categoria);
        changeText('productoId', '', acceptEmpty: true);
        changeText('producto', row.producto);
        changeText('grupoId', row.grupoId);
        changeText('grupo', row.grupo);
        changeText('destino', row.destino);
        changeText('condicion', row.condicion);
        changeText('unidad', row.unidad);
        changeText('ordenCompra', row.ordenCompra);
        changeText('recepcionId', row.recepcionId);
        final previousEntry = (data['numeroEntrada'] ?? '').toString().trim();
        changeText('numeroEntrada', row.numeroEntrada);
        if (row.numeroEntrada.trim().isNotEmpty &&
            previousEntry != row.numeroEntrada.trim()) {
          data['entradaRegistradaPor'] = usuarioId;
          data['entradaRegistradaAt'] = now;
        }
        changeText('observaciones', row.observaciones);
        changeNumber('cantidad', row.cantidad);
        changeNumber('precio', row.precio);
        changeDate('fechaProgramada', row.fechaProgramada);
        changeDate('fechaSegundaEntrega', row.fechaSegundaEntrega);
        changeDate('fechaRecibido', row.fechaRecibido);
        if (row.fechaProgramada != null) {
          final periodStart = inicioPeriodoConsumo(row.fechaProgramada!);
          changeDate('consumoDesde', periodStart);
          changeDate('consumoHasta', finPeriodoConsumo(periodStart));
        }

        final pendingValues = row.pendencias.map((item) => item.value).toList();
        final oldPending = (data['pendencias'] as List? ?? const [])
            .map((item) => item.toString())
            .toList();
        if (!_sameList(oldPending, pendingValues)) {
          data['pendencias'] = pendingValues;
          changes.add(
            _change(
              'pendencias',
              oldPending.join(', '),
              pendingValues.join(', '),
              usuarioId,
              now,
              'excel',
            ),
          );
        }

        if (row.estadoExplicito != null &&
            row.estadoExplicito!.value != current.estado.value) {
          data['estado'] = row.estadoExplicito!.value;
          changes.add(
            _change(
              'estado',
              current.estado.value,
              row.estadoExplicito!.value,
              usuarioId,
              now,
              'excel',
            ),
          );
        }
        if (row.estadoExplicito == null &&
            row.recepcionId.isNotEmpty &&
            current.estado != AbastecimientoEstado.recibido) {
          data['estado'] = AbastecimientoEstado.recibido.value;
          changes.add(
            _change(
              'estado',
              current.estado.value,
              AbastecimientoEstado.recibido.value,
              usuarioId,
              now,
              'recepcion',
            ),
          );
        }

        if (changes.isEmpty) {
          unchanged++;
          continue;
        }
        final history = [...current.historial, ...changes];
        data.addAll({
          'hojaOrigen': row.hoja,
          'filaOrigen': row.fila,
          'archivoOrigen': archivoNombre,
          'importBatchId': batchId,
          'actualizadoPor': usuarioId,
          'updatedAt': now,
          'historial': history
              .skip(history.length > 100 ? history.length - 100 : 0)
              .map((item) => item.toMap())
              .toList(),
        });
        batch.set(ref, data);
        updated++;
        operations++;
      }

      if (operations >= 400) await flush();
    }
    await flush();

    return AbastecimientoImportResult(
      creados: created,
      actualizados: updated,
      sinCambios: unchanged,
      omitidosCatalogo: validation.incidencias.length,
    );
  }

  Future<String> crearManual({
    required String empresaId,
    required String usuarioId,
    required String proveedorId,
    required String proveedor,
    required String categoria,
    required String producto,
    required String grupoId,
    required String grupo,
    required String destino,
    required String condicion,
    required DateTime? fechaProgramada,
    required DateTime consumoDesde,
    required String ordenCompra,
    required String observaciones,
  }) async {
    if (proveedorId.trim().isEmpty) {
      throw StateError('Debes seleccionar un proveedor registrado.');
    }
    if (ordenCompra.trim().isEmpty) {
      throw StateError('La orden de compra es obligatoria.');
    }
    if (producto.trim().isEmpty || grupoId.trim().isEmpty) {
      throw StateError('Debes escribir el producto y seleccionar un grupo.');
    }
    final now = Timestamp.now();
    final rawKey =
        'manual|$empresaId|$proveedor|$producto|'
        '${now.millisecondsSinceEpoch}';
    final importKey = rawKey.toLowerCase();
    final ref = _db.collection(kAbastecimientoCollection).doc();
    final created = AbastecimientoCambio(
      campo: 'registro',
      anterior: '',
      nuevo: 'Creado manualmente',
      origen: 'entorno',
      usuarioId: usuarioId,
      fecha: now,
    );
    final doc = AbastecimientoDoc(
      id: ref.id,
      empresaId: empresaId,
      importKey: importKey,
      proveedorId: proveedorId.trim(),
      proveedor: proveedor.trim(),
      categoria: categoria.trim(),
      productoId: '',
      producto: producto.trim(),
      grupoId: grupoId.trim(),
      grupo: grupo.trim(),
      destino: destino.trim(),
      condicion: condicion.trim(),
      fechaProgramada: fechaProgramada,
      consumoDesde: inicioPeriodoConsumo(consumoDesde),
      consumoHasta: finPeriodoConsumo(inicioPeriodoConsumo(consumoDesde)),
      ordenCompra: ordenCompra.trim(),
      observaciones: observaciones.trim(),
      pendencias: detectarPendenciasAbastecimiento(observaciones),
      creadoPor: usuarioId,
      actualizadoPor: usuarioId,
      createdAt: now,
      updatedAt: now,
      historial: [created],
    );
    await ref.set(doc.toMap());
    return ref.id;
  }

  Future<void> actualizarEstado({
    required String id,
    required AbastecimientoEstado estado,
    required String usuarioId,
    required String motivo,
    String? rolCompras,
    DateTime? nuevaFecha,
  }) async {
    final reason = motivo.trim();
    final rol = normalizeComprasRol(rolCompras);
    final esAdmin = rol == null || rol == kRolAdmin;
    final esBodega = rol == kRolBodega;
    final esCompras = rol == kRolCompras;
    if (!esAdmin && esBodega && estado != AbastecimientoEstado.recibido) {
      throw StateError('Bodega solo puede marcar la entrega como Entregada.');
    }
    if (!esAdmin && esCompras && estado == AbastecimientoEstado.recibido) {
      throw StateError('Solo Bodega puede marcar una entrega como Entregada.');
    }
    if (!esAdmin && !esBodega && !esCompras) {
      throw StateError('Tu rol no tiene permiso para cambiar este estado.');
    }
    if ((estado == AbastecimientoEstado.cancelado ||
            estado == AbastecimientoEstado.reprogramado) &&
        reason.isEmpty) {
      throw StateError('Debes indicar el motivo del cambio.');
    }
    if (estado == AbastecimientoEstado.reprogramado && nuevaFecha == null) {
      throw StateError('Debes indicar la nueva fecha de entrega.');
    }

    final ref = _db.collection(kAbastecimientoCollection).doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('La entrega ya no existe.');
      }
      final current = AbastecimientoDoc.fromMap(id, snapshot.data()!);
      if (!esAdmin &&
          current.estado == AbastecimientoEstado.recibido &&
          estado != AbastecimientoEstado.recibido) {
        throw StateError(
          'Una entrega confirmada por Bodega solo puede corregirla un administrador.',
        );
      }
      final now = Timestamp.now();
      final changes = <AbastecimientoCambio>[];
      if (current.estado != estado) {
        changes.add(
          _change(
            'estado',
            current.estado.value,
            estado.value,
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      if (estado != AbastecimientoEstado.recibido &&
          current.fechaRecibido != null) {
        changes.add(
          _change(
            'fechaRecibido',
            current.fechaRecibido!.toIso8601String(),
            '',
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      if (nuevaFecha != null &&
          (current.fechaProgramada == null ||
              !_sameMoment(current.fechaProgramada!, nuevaFecha))) {
        changes.add(
          _change(
            'fechaProgramada',
            current.fechaProgramada?.toIso8601String() ?? '',
            nuevaFecha.toIso8601String(),
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      if (reason.isNotEmpty && current.novedadEstado.trim() != reason) {
        changes.add(
          _change(
            'novedadEstado',
            current.novedadEstado,
            reason,
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      if (changes.isEmpty) return;

      final history = [...current.historial, ...changes];
      transaction.update(ref, {
        'estado': estado.value,
        if (nuevaFecha != null)
          'fechaProgramada': Timestamp.fromDate(nuevaFecha),
        if (estado == AbastecimientoEstado.recibido) 'fechaRecibido': now,
        if (estado != AbastecimientoEstado.recibido &&
            current.fechaRecibido != null)
          'fechaRecibido': FieldValue.delete(),
        if (reason.isNotEmpty) 'novedadEstado': reason,
        'actualizadoPor': usuarioId,
        'updatedAt': now,
        'historial': history
            .skip(history.length > 100 ? history.length - 100 : 0)
            .map((item) => item.toMap())
            .toList(),
      });
    });
  }

  Future<void> actualizarNumeroEntrada({
    required String id,
    required String usuarioId,
    required String numeroEntrada,
  }) async {
    final next = numeroEntrada.trim();
    if (next.isEmpty) {
      throw StateError('Debes indicar el número del documento de entrada.');
    }
    final ref = _db.collection(kAbastecimientoCollection).doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('La entrega ya no existe.');
      }
      final current = AbastecimientoDoc.fromMap(id, snapshot.data()!);
      if (current.estado != AbastecimientoEstado.recibido) {
        throw StateError(
          'El número de entrada solo se registra después de la entrega.',
        );
      }
      if (current.numeroEntrada == next) return;
      final now = Timestamp.now();
      final history = [
        ...current.historial,
        _change(
          'numeroEntrada',
          current.numeroEntrada,
          next,
          usuarioId,
          now,
          'entorno',
        ),
      ];
      transaction.update(ref, {
        'numeroEntrada': next,
        'entradaRegistradaPor': usuarioId,
        'entradaRegistradaAt': now,
        'actualizadoPor': usuarioId,
        'updatedAt': now,
        'historial': history
            .skip(history.length > 100 ? history.length - 100 : 0)
            .map((item) => item.toMap())
            .toList(),
      });
    });
  }

  Future<void> actualizarObservaciones({
    required String id,
    required String usuarioId,
    required String observaciones,
  }) async {
    final ref = _db.collection(kAbastecimientoCollection).doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('La entrega ya no existe.');
      }
      final current = AbastecimientoDoc.fromMap(id, snapshot.data()!);
      final next = observaciones.trim();
      final pending = detectarPendenciasAbastecimiento(next);
      final now = Timestamp.now();
      final changes = <AbastecimientoCambio>[];
      if (current.observaciones != next) {
        changes.add(
          _change(
            'observaciones',
            current.observaciones,
            next,
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      final oldPending = current.pendencias.map((item) => item.value).toList();
      final nextPending = pending.map((item) => item.value).toList();
      if (!_sameList(oldPending, nextPending)) {
        changes.add(
          _change(
            'pendencias',
            oldPending.join(', '),
            nextPending.join(', '),
            usuarioId,
            now,
            'entorno',
          ),
        );
      }
      if (changes.isEmpty) return;
      final history = [...current.historial, ...changes];
      transaction.update(ref, {
        'observaciones': next,
        'pendencias': nextPending,
        'actualizadoPor': usuarioId,
        'updatedAt': now,
        'historial': history
            .skip(history.length > 100 ? history.length - 100 : 0)
            .map((item) => item.toMap())
            .toList(),
      });
    });
  }

  Future<void> eliminar({
    required String id,
    required String usuarioId,
    required String motivo,
  }) async {
    final reason = motivo.trim();
    if (reason.isEmpty) {
      throw StateError('Debes indicar el motivo de la eliminación.');
    }
    final ref = _db.collection(kAbastecimientoCollection).doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('La entrega ya no existe.');
      }
      final current = AbastecimientoDoc.fromMap(id, snapshot.data()!);
      if (current.eliminado) return;
      final now = Timestamp.now();
      final history = [
        ...current.historial,
        _change('eliminado', 'false', reason, usuarioId, now, 'entorno'),
      ];
      transaction.update(ref, {
        'eliminado': true,
        'eliminadoPor': usuarioId,
        'eliminadoAt': now,
        'motivoEliminacion': reason,
        'actualizadoPor': usuarioId,
        'updatedAt': now,
        'historial': history
            .skip(history.length > 100 ? history.length - 100 : 0)
            .map((item) => item.toMap())
            .toList(),
      });
    });
  }

  static String _documentId(String empresaId, String importKey) =>
      sha256.convert(utf8.encode('$empresaId|$importKey')).toString();

  static bool _sameMoment(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (index) => a[index] == b[index],
      ).every((same) => same);

  static String _catalogKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _groupKey(String value) {
    final key = _catalogKey(value);
    return key.startsWith('grupo ') ? key.substring(6).trim() : key;
  }

  static AbastecimientoCambio _change(
    String field,
    String oldValue,
    String newValue,
    String userId,
    Timestamp date,
    String origin,
  ) => AbastecimientoCambio(
    campo: field,
    anterior: oldValue,
    nuevo: newValue,
    origen: origin,
    usuarioId: userId,
    fecha: date,
  );
}
