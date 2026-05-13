import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../services/org_service.dart';
import 'interventoria_models.dart';

// Re-exportamos Area para que el dashboard no tenga que importar org_service.dart
export '../services/org_service.dart' show Area;

class InterventoriaOcrResult {
  final DateTime? fechaVisita;
  final Map<String, InterventoriaItem> items;
  final String observaciones;
  final Map<String, dynamic> raw;

  const InterventoriaOcrResult({
    this.fechaVisita,
    required this.items,
    this.observaciones = '',
    this.raw = const {},
  });
}

class InterventoriaService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  InterventoriaService({FirebaseFirestore? db, FirebaseStorage? storage})
    : _db = db ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  Stream<List<CentroCostoRef>> streamCentrosCosto(String empresaId) => _db
      .collection('TBL_CENTROS_COSTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .where((d) => (d.data()['enabled'] as bool?) ?? true)
            .map((d) => CentroCostoRef.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          final byCode = a.codigo.compareTo(b.codigo);
          return byCode != 0 ? byCode : a.nombre.compareTo(b.nombre);
        });
        return list;
      });

  Stream<List<InterventoriaVisita>> streamVisitas(String empresaId) => _db
      .collection('TBL_INTERVENTORIA_VISITAS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => InterventoriaVisita.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
        return list;
      });

  Future<String> guardarVisita(InterventoriaVisita visita) async {
    final ref = visita.id.isEmpty
        ? _db.collection('TBL_INTERVENTORIA_VISITAS').doc()
        : _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visita.id);
    await ref.set(visita.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> eliminarVisita(String visitaId) async {
    final hallazgos = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('visitaId', isEqualTo: visitaId)
        .get();
    final batch = _db.batch();
    for (final doc in hallazgos.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('TBL_INTERVENTORIA_VISITAS').doc(visitaId));
    await batch.commit();
  }

  Future<InterventoriaAdjunto> subirActaBytes({
    required Uint8List bytes,
    required String empresaId,
    required String visitaId,
    required String nombre,
    required String contentType,
    required String origen,
  }) async {
    final safeName = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'interventoria/$empresaId/visitas/$visitaId/${ts}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    return InterventoriaAdjunto(
      url: url,
      nombre: nombre,
      path: path,
      contentType: contentType,
      origen: origen,
      fechaSubida: Timestamp.now(),
    );
  }

  Future<void> agregarAdjuntos({
    required String visitaId,
    required List<InterventoriaAdjunto> adjuntos,
  }) async {
    if (adjuntos.isEmpty) return;
    final firstUrl = adjuntos.first.url;
    await _db.collection('TBL_INTERVENTORIA_VISITAS').doc(visitaId).set({
      'imagenesActa': FieldValue.arrayUnion(
        adjuntos.map((a) => a.toMap()).toList(),
      ),
      if (firstUrl.isNotEmpty) 'actaOriginalUrl': firstUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<InterventoriaRolDoc>> streamRoles(String empresaId) => _db
      .collection('TBL_INTERVENTORIA_ROLES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => InterventoriaRolDoc.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
        return list;
      });

  Future<InterventoriaRolDoc?> getRolUsuario(
    String empresaId,
    String userId,
  ) async {
    final byUserId = await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (byUserId.docs.isNotEmpty) {
      return InterventoriaRolDoc.fromMap(
        byUserId.docs.first.id,
        byUserId.docs.first.data(),
      );
    }
    final byCedula = await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .where('cedula', isEqualTo: userId)
        .limit(1)
        .get();
    if (byCedula.docs.isEmpty) return null;
    return InterventoriaRolDoc.fromMap(
      byCedula.docs.first.id,
      byCedula.docs.first.data(),
    );
  }

  Future<void> guardarRol(
    InterventoriaRolDoc rol, {
    required bool isNew,
  }) async {
    final docId = isNew ? '${rol.empresaId}_${rol.userId}' : rol.id;
    await _db
        .collection('TBL_INTERVENTORIA_ROLES')
        .doc(docId)
        .set(rol.toMap(), SetOptions(merge: true));
  }

  Future<void> eliminarRol(String id) =>
      _db.collection('TBL_INTERVENTORIA_ROLES').doc(id).delete();

  // ── Hallazgos ────────────────────────────────────────────────────────────

  Stream<List<InterventoriaHallazgo>> streamHallazgos(
    String empresaId, {
    String? centroId,
    String? estado,
  }) {
    var q = _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('empresaId', isEqualTo: empresaId);
    if (centroId != null && centroId.isNotEmpty) {
      q = q.where('centroCostoId', isEqualTo: centroId);
    }
    if (estado != null && estado.isNotEmpty) {
      q = q.where('estado', isEqualTo: estado);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => InterventoriaHallazgo.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
        return byFecha != 0
            ? byFecha
            : a.numeroHallazgo.compareTo(b.numeroHallazgo);
      });
      return list;
    });
  }

  Future<String> guardarHallazgo(InterventoriaHallazgo hallazgo) async {
    final ref = hallazgo.id.isEmpty
        ? _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc()
        : _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgo.id);
    await ref.set(hallazgo.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> guardarHallazgos(List<InterventoriaHallazgo> hallazgos) async {
    final batch = _db.batch();
    for (final h in hallazgos) {
      final ref = h.id.isEmpty
          ? _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc()
          : _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(h.id);
      batch.set(ref, h.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> eliminarHallazgo(String hallazgoId) =>
      _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).delete();

  Future<void> marcarSubsanado({
    required String hallazgoId,
    required DateTime fechaSubsanacion,
    String seguimiento = '',
  }) => _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
    'estado': 'subsanado',
    'fechaSubsanacion': Timestamp.fromDate(fechaSubsanacion),
    if (seguimiento.isNotEmpty) 'seguimiento': seguimiento,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> reabrirHallazgo(String hallazgoId) =>
      _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId).set({
        'estado': 'activo',
        'fechaSubsanacion': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── OCR hallazgos parser ─────────────────────────────────────────────────

  /// Toma el texto pegado/OCR y detecta hallazgos numerados (ej. "1.1 El contratista...")
  List<InterventoriaHallazgo> parseHallazgosOcr({
    required String texto,
    required String empresaId,
    required String centroCostoId,
    required String centroCostoNombre,
    String visitaId = '',
    String grupoId = '',
    String? tipoActa,
  }) {
    final hallazgos = <InterventoriaHallazgo>[];
    // Detecta líneas que empiezan por número tipo 1.1 / 10.20
    final numRx = RegExp(r'^(\d{1,2}\.\d{1,3})\s+(.+)');
    // Detecta fechas para asignar al hallazgo
    DateTime? fechaGlobal = _extractFecha(texto);

    final lines = texto.split('\n');
    String? currentNum;
    final descBuf = StringBuffer();

    void flush() {
      if (currentNum == null) return;
      final desc = descBuf.toString().trim();
      if (desc.isNotEmpty) {
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: empresaId,
            visitaId: visitaId,
            centroCostoId: centroCostoId,
            centroCostoNombre: centroCostoNombre,
            grupoId: grupoId,
            tipoActa: tipoActa,
            numeroHallazgo: currentNum!,
            descripcion: desc,
            fechaHallazgo: Timestamp.fromDate(fechaGlobal ?? DateTime.now()),
            fuente: 'ocr',
            createdAt: Timestamp.now(),
          ),
        );
      }
      currentNum = null;
      descBuf.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final m = numRx.firstMatch(line);
      if (m != null) {
        flush();
        currentNum = m.group(1)!;
        descBuf.write(m.group(2)!);
      } else if (currentNum != null) {
        if (descBuf.isNotEmpty) descBuf.write(' ');
        descBuf.write(line);
      }
    }
    flush();
    return hallazgos;
  }

  // ── Excel export ─────────────────────────────────────────────────────────

  Uint8List exportarHallazgosExcel(List<InterventoriaHallazgo> hallazgos) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Seguimiento');
    final sheet = excel['Seguimiento'];
    final fmt = DateFormat('dd/MM/yyyy');

    final headers = [
      'GRUPO',
      'ESTRUCTURA',
      'ESTADO',
      'TIPO DE ACTA',
      'N° HALLAZGO',
      'HALLAZGOS',
      'FECHA DEL HALLAZGO',
      'PERSISTE',
      'DPTO ENCARGADO',
      'OBSERVACIONES',
      'PLAN DE MEJORA',
      'VALOR DE LA CORRECCIÓN',
      'FECHA DE SUBSANACIÓN',
      'SEGUIMIENTO',
    ];
    sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

    for (final h in hallazgos) {
      sheet.appendRow([
        xl.TextCellValue(h.grupoId),
        xl.TextCellValue(h.centroCostoNombre),
        xl.TextCellValue(h.estado.toUpperCase()),
        xl.TextCellValue(h.tipoActa ?? ''),
        xl.TextCellValue(h.numeroHallazgo),
        xl.TextCellValue(h.descripcion),
        xl.TextCellValue(fmt.format(h.fechaHallazgo.toDate())),
        xl.TextCellValue(h.persiste ? 'SI' : ''),
        xl.TextCellValue(h.dptoEncargado),
        xl.TextCellValue(h.observaciones),
        xl.TextCellValue(h.planMejora),
        h.valorCorreccion != null
            ? xl.DoubleCellValue(h.valorCorreccion!)
            : xl.TextCellValue(''),
        xl.TextCellValue(
          h.fechaSubsanacion != null
              ? fmt.format(h.fechaSubsanacion!.toDate())
              : '',
        ),
        xl.TextCellValue(h.seguimiento),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Exporta la matriz de puntajes por visita/establecimiento al formato Excel.
  Uint8List exportarVisitasExcel(List<InterventoriaVisita> visitas) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Análisis');
    final sheet = excel['Análisis'];
    final fmt = DateFormat('dd/MM/yyyy');

    // Cabecera: SECCIÓN + un centro por columna
    final headers = <xl.CellValue>[
      xl.TextCellValue('SECCIÓN'),
      ...visitas.map(
        (v) => xl.TextCellValue(
          '${v.centroCostoCodigo.isNotEmpty ? v.centroCostoCodigo : v.centroCostoNombre}\n${fmt.format(v.fechaVisita.toDate())}',
        ),
      ),
    ];
    sheet.appendRow(headers);

    // Filas de sección
    for (final cat in kInterventoriaCategorias) {
      final row = <xl.CellValue>[xl.TextCellValue(cat.label)];
      for (final v in visitas) {
        final item = v.items[cat.key];
        if (item == null || item.noEvaluado || item.valor == null) {
          row.add(xl.TextCellValue('NE'));
        } else {
          row.add(xl.DoubleCellValue(item.valor!));
        }
      }
      sheet.appendRow(row);
    }

    // Fila de total
    final totalRow = <xl.CellValue>[
      xl.TextCellValue('Total condiciones del servicio'),
    ];
    for (final v in visitas) {
      totalRow.add(xl.DoubleCellValue(v.porcentajeGeneral));
    }
    sheet.appendRow(totalRow);

    return Uint8List.fromList(excel.encode()!);
  }

  Future<void> asegurarConfigBase(String empresaId) async {
    await _db.collection('TBL_INTERVENTORIA_CONFIG').doc(empresaId).set({
      'empresaId': empresaId,
      'categorias': kInterventoriaCategorias
          .map((c) => {'key': c.key, 'label': c.label, 'activo': true})
          .toList(),
      'semaforo': {'verdeDesde': 90, 'amarilloDesde': 70},
      'ocr': {'modo': 'prellenado_editable', 'requiereRevision': true},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  InterventoriaOcrResult analizarTextoOcr(String texto) {
    final items = defaultInterventoriaItems();
    final normalizedText = _normalize(texto);

    for (final categoria in kInterventoriaCategorias) {
      final value = _extractValueForLabel(normalizedText, categoria.label);
      if (value == null) continue;
      items[categoria.key] = items[categoria.key]!.copyWith(
        valor: value,
        noEvaluado: false,
        fuente: 'ocr',
        confianzaOcr: 0.72,
      );
    }

    for (final categoria in kInterventoriaCategorias) {
      if (_extractNeForLabel(normalizedText, categoria.label)) {
        items[categoria.key] = items[categoria.key]!.copyWith(
          noEvaluado: true,
          clearValor: true,
          fuente: 'ocr',
          confianzaOcr: 0.68,
        );
      }
    }

    final fecha = _extractFecha(texto);
    return InterventoriaOcrResult(
      fechaVisita: fecha,
      items: items,
      observaciones: _extractObservaciones(texto),
      raw: {
        'fechaDetectada': fecha?.toIso8601String(),
        'porcentajeGeneral': calcularPorcentajeGeneral(items),
        'categoriasDetectadas': items.values
            .where((i) => i.fuente == 'ocr')
            .length,
      },
    );
  }

  double? _extractValueForLabel(String normalizedText, String label) {
    final labelTokens = _normalize(label)
        .split(' ')
        .where((token) => token.length > 2 && !RegExp(r'^\d+$').hasMatch(token))
        .take(3)
        .toList();
    if (labelTokens.isEmpty) return null;

    final lines = normalizedText.split('\n');
    for (final line in lines) {
      final matches = labelTokens.where(line.contains).length;
      if (matches < (labelTokens.length == 1 ? 1 : 2)) continue;
      final percent = RegExp(r'(\d{1,3})([,.]\d+)?\s*%?').firstMatch(line);
      if (percent == null) continue;
      final raw = percent
          .group(0)!
          .replaceAll('%', '')
          .replaceAll(',', '.')
          .trim();
      final value = double.tryParse(raw);
      if (value == null || value > 100) continue;
      return value;
    }
    return null;
  }

  bool _extractNeForLabel(String normalizedText, String label) {
    final labelTokens = _normalize(label)
        .split(' ')
        .where((token) => token.length > 2 && !RegExp(r'^\d+$').hasMatch(token))
        .take(3)
        .toList();
    for (final line in normalizedText.split('\n')) {
      if (!line.contains(' ne ') && !line.endsWith(' ne')) continue;
      final matches = labelTokens.where(line.contains).length;
      if (matches >= (labelTokens.length == 1 ? 1 : 2)) return true;
    }
    return false;
  }

  DateTime? _extractFecha(String texto) {
    final match = RegExp(
      r'(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})',
    ).firstMatch(texto);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    return DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
  }

  String _extractObservaciones(String texto) {
    final lower = texto.toLowerCase();
    final idx = lower.indexOf('observ');
    if (idx < 0) return '';
    final tail = texto.substring(idx).trim();
    return tail.length > 600 ? tail.substring(0, 600) : tail;
  }

  String _normalize(String text) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ñ': 'n',
      'Á': 'a',
      'É': 'e',
      'Í': 'i',
      'Ó': 'o',
      'Ú': 'u',
      'Ñ': 'n',
    };
    var out = text;
    accents.forEach((a, b) => out = out.replaceAll(a, b));
    return out.toLowerCase().replaceAll(RegExp(r'[^\w%,.\n ]+'), ' ');
  }

  // ── Áreas de la empresa ──────────────────────────────────────────────────

  Future<List<Area>> getAreas(String empresaId) =>
      OrgService(db: _db).listAreas(empresaId: empresaId);

  // ── Director de un área ──────────────────────────────────────────────────

  /// Busca en TBL_USUARIOS el usuario del área cuyo cargo contenga 'director'.
  /// Devuelve un map con los campos: id (cédula/docId), nombre, cargo, areaId.
  Future<Map<String, dynamic>?> getDirectorDeArea(String areaId) async {
    if (areaId.trim().isEmpty) return null;
    final q = await _db
        .collection('TBL_USUARIOS')
        .where('areaId', isEqualTo: areaId)
        .get();
    for (final doc in q.docs) {
      final data = doc.data();
      final cargo = (data['cargo'] ?? data['cargoNombre'] ?? '')
          .toString()
          .toLowerCase();
      if (cargo.contains('director')) {
        final nombre = _nombreUsuario(data);
        return {'id': doc.id, 'nombre': nombre, ...data};
      }
    }
    // Fallback: busca en empresasDetalle (multi-empresa)
    final qAll = await _db.collection('TBL_USUARIOS').get();
    for (final doc in qAll.docs) {
      final data = doc.data();
      final detalle = data['empresasDetalle'];
      if (detalle is! Map) continue;
      for (final entry in detalle.entries) {
        final det = entry.value;
        if (det is! Map) continue;
        if ((det['areaId'] ?? '').toString() != areaId) continue;
        final cargo = (det['cargo'] ?? det['cargoNombre'] ?? '')
            .toString()
            .toLowerCase();
        if (cargo.contains('director')) {
          return {'id': doc.id, 'nombre': _nombreUsuario(data), ...data};
        }
      }
    }
    return null;
  }

  String _nombreUsuario(Map<String, dynamic> data) {
    final nombres = (data['nombres'] ?? data['nombre'] ?? '').toString().trim();
    final apellidos =
        (data['apellidos'] ?? data['apellido'] ?? '').toString().trim();
    if (nombres.isNotEmpty && apellidos.isNotEmpty) return '$nombres $apellidos';
    if (nombres.isNotEmpty) return nombres;
    return (data['displayName'] ?? data['email'] ?? data['id'] ?? '')
        .toString()
        .trim();
  }

  // ── Crear tarea + notificar al director ─────────────────────────────────

  /// Crea una tarea en TBL_TAREAS asignada al director del área y le envía
  /// una notificación. Retorna el ID de la tarea creada o null si no hay director.
  Future<String?> crearTareaYNotificarHallazgo({
    required InterventoriaHallazgo hallazgo,
    required String creadorId,
    String creadorNombre = '',
  }) async {
    // Resolver nombre real del creador desde TBL_USUARIOS
    String creadorNombreReal = creadorNombre;
    if (creadorId.isNotEmpty) {
      try {
        final userDoc = await _db
            .collection('TBL_USUARIOS')
            .doc(creadorId)
            .get();
        if (userDoc.exists) {
          creadorNombreReal = _nombreUsuario(userDoc.data()!);
        }
      } catch (_) {}
    }
    if (creadorNombreReal.isEmpty) creadorNombreReal = creadorId;

    final director = await getDirectorDeArea(hallazgo.areaId);
    final directorId = director?['id']?.toString() ?? '';
    final directorNombre =
        director != null ? _nombreUsuario(director) : '';

    // Crear tarea
    final titulo =
        'Hallazgo ${hallazgo.numeroHallazgo.isNotEmpty ? hallazgo.numeroHallazgo : ''}'
        ' — ${hallazgo.centroCostoNombre}';
    final descripcion =
        '${hallazgo.descripcion}\n\n'
        'Centro: ${hallazgo.centroCostoNombre}\n'
        'Sección: ${hallazgo.dptoEncargado}\n'
        'Fecha: ${DateFormat('dd/MM/yyyy').format(hallazgo.fechaHallazgo.toDate())}\n'
        'Origen: Interventoría';

    final payload = <String, dynamic>{
      'titulo': titulo,
      'descripcion': descripcion,
      'prioridad': 'alta',
      'fecha_creacion': FieldValue.serverTimestamp(),
      'fecha_limite': null,
      'estado': 'en_progreso',
      'visto': false,
      'reasignado': false,
      'areaId': hallazgo.areaId,
      'areaNombre': hallazgo.dptoEncargado,
      'asignado_uid': directorId,
      'asignado_nombre': directorNombre,
      'creador_id': creadorId,
      'creador_nombre': creadorNombreReal,
      'empresaId': hallazgo.empresaId,
      'empresas': [hallazgo.empresaId],
      // Metadata de enlace con interventoría
      'hallazgoId': hallazgo.id,
      'visitaId': hallazgo.visitaId,
      'centroCostoId': hallazgo.centroCostoId,
      'origen': 'interventoria',
      'notify': true,
    };

    final ref = await _db.collection('TBL_TAREAS').add(payload);

    // Notificar al director si se encontró
    if (directorId.isNotEmpty) {
      await _db
          .collection('TBL_NOTIFICACIONES')
          .doc(directorId)
          .collection('notifications')
          .add({
        'title': '📋 Nuevo hallazgo de interventoría',
        'description':
            'Hallazgo ${hallazgo.numeroHallazgo} asignado a ${hallazgo.dptoEncargado} '
            '— ${hallazgo.centroCostoNombre}',
        'type': 'hallazgo_interventoria',
        'taskId': ref.id,
        'hallazgoId': hallazgo.id,
        'fromId': creadorId,
        'fromName': creadorNombreReal,
        'empresaId': hallazgo.empresaId,
        'createdAt': Timestamp.now(),
        'read': false,
      });
    }

    return ref.id;
  }
}
