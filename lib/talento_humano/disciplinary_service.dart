import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'personnel_status_service.dart';

class DisciplinaryStatus {
  static const pendingResponse = 'pendiente_respuesta';
  static const inReview = 'en_descargos';
  static const followUp = 'en_seguimiento';
  static const closed = 'cerrado';
  static const cancelled = 'anulado';

  static const active = <String>{pendingResponse, inReview, followUp};

  static String normalize(dynamic value) {
    final status = (value ?? '').toString().trim().toLowerCase();
    return const {
          pendingResponse,
          inReview,
          followUp,
          closed,
          cancelled,
        }.contains(status)
        ? status
        : pendingResponse;
  }

  static String label(String status) {
    switch (normalize(status)) {
      case inReview:
        return 'En descargos';
      case followUp:
        return 'En seguimiento';
      case closed:
        return 'Cerrado';
      case cancelled:
        return 'Anulado';
      default:
        return 'Pendiente de respuesta';
    }
  }
}

class DisciplinaryPerson {
  final String cedula;
  final String name;
  final String area;
  final String role;
  final String costCenter;
  final String photoUrl;
  final String status;

  const DisciplinaryPerson({
    required this.cedula,
    required this.name,
    this.area = '',
    this.role = '',
    this.costCenter = '',
    this.photoUrl = '',
    this.status = PersonnelStatusService.active,
  });

  bool get isActive => status == PersonnelStatusService.active;
}

class DisciplinaryRecord {
  final String id;
  final String empresaId;
  final String cedula;
  final String personName;
  final String area;
  final String role;
  final String subject;
  final String description;
  final String type;
  final String severity;
  final String status;
  final String policyReference;
  final String expectedAction;
  final String employeeResponse;
  final String conclusion;
  final String createdBy;
  final String updatedBy;
  final DateTime incidentDate;
  final DateTime? responseDeadline;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final DateTime? closedAt;
  final List<DisciplinaryAttachment> attachments;

  const DisciplinaryRecord({
    required this.id,
    required this.empresaId,
    required this.cedula,
    required this.personName,
    required this.subject,
    required this.description,
    required this.type,
    required this.severity,
    required this.status,
    required this.incidentDate,
    this.area = '',
    this.role = '',
    this.policyReference = '',
    this.expectedAction = '',
    this.employeeResponse = '',
    this.conclusion = '',
    this.createdBy = '',
    this.updatedBy = '',
    this.responseDeadline,
    this.createdAt,
    this.respondedAt,
    this.closedAt,
    this.attachments = const [],
  });

  bool get isOpen => DisciplinaryStatus.active.contains(status);

  factory DisciplinaryRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    DateTime date(dynamic value, {DateTime? fallback}) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return fallback ?? DateTime.now();
    }

    DateTime? optionalDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return DisciplinaryRecord(
      id: document.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      personName: (data['nombre'] ?? '').toString(),
      area: (data['area'] ?? '').toString(),
      role: (data['cargo'] ?? '').toString(),
      subject: (data['asunto'] ?? '').toString(),
      description: (data['descripcion'] ?? '').toString(),
      type: (data['tipo'] ?? 'escrito').toString(),
      severity: (data['gravedad'] ?? 'leve').toString(),
      status: DisciplinaryStatus.normalize(data['estado']),
      policyReference: (data['referenciaNormativa'] ?? '').toString(),
      expectedAction: (data['accionEsperada'] ?? '').toString(),
      employeeResponse: (data['respuestaEmpleado'] ?? '').toString(),
      conclusion: (data['conclusion'] ?? '').toString(),
      createdBy: (data['creadoPor'] ?? '').toString(),
      updatedBy: (data['actualizadoPor'] ?? '').toString(),
      incidentDate: date(data['fechaHecho']),
      responseDeadline: optionalDate(data['fechaLimiteRespuesta']),
      createdAt: optionalDate(data['creadoAt']),
      respondedAt: optionalDate(data['respondidoAt']),
      closedAt: optionalDate(data['cerradoAt']),
      attachments: (data['adjuntos'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => DisciplinaryAttachment.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
    );
  }
}

class DisciplinaryAttachment {
  final String name;
  final String url;
  final String storagePath;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const DisciplinaryAttachment({
    required this.name,
    required this.url,
    required this.storagePath,
    required this.uploadedBy,
    this.uploadedAt,
  });

  factory DisciplinaryAttachment.fromMap(Map<String, dynamic> data) {
    final rawDate = data['fecha'];
    return DisciplinaryAttachment(
      name: (data['nombre'] ?? 'Adjunto').toString(),
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      uploadedBy: (data['subidoPor'] ?? '').toString(),
      uploadedAt: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

class DisciplinaryMetrics {
  final int total;
  final int pendingResponse;
  final int followUp;
  final int closed;
  final int highSeverity;

  const DisciplinaryMetrics({
    required this.total,
    required this.pendingResponse,
    required this.followUp,
    required this.closed,
    required this.highSeverity,
  });

  factory DisciplinaryMetrics.fromRecords(
    Iterable<DisciplinaryRecord> records,
  ) {
    final items = records.toList();
    return DisciplinaryMetrics(
      total: items.length,
      pendingResponse: items
          .where((item) => item.status == DisciplinaryStatus.pendingResponse)
          .length,
      followUp: items
          .where(
            (item) =>
                item.status == DisciplinaryStatus.followUp ||
                item.status == DisciplinaryStatus.inReview,
          )
          .length,
      closed: items
          .where((item) => item.status == DisciplinaryStatus.closed)
          .length,
      highSeverity: items
          .where((item) => item.severity.toLowerCase() == 'alta')
          .length,
    );
  }
}

class DisciplinaryService {
  static const recordsCollection = 'TBL_LLAMADOS_ATENCION';
  static const historyCollection = 'TBL_HISTORIAL_LLAMADOS_ATENCION';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  DisciplinaryService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  Stream<List<DisciplinaryRecord>> watchCompany(String empresaId) {
    return _db
        .collection(recordsCollection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .map(DisciplinaryRecord.fromDoc)
              .toList();
          records.sort((a, b) {
            final aDate = a.createdAt ?? a.incidentDate;
            final bDate = b.createdAt ?? b.incidentDate;
            return bDate.compareTo(aDate);
          });
          return records;
        });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecordHistory(
    String recordId,
  ) {
    return _db
        .collection(historyCollection)
        .where('llamadoId', isEqualTo: recordId)
        .snapshots();
  }

  Future<List<DisciplinaryPerson>> loadPeople(String empresaId) async {
    final results = await Future.wait([
      _db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get(),
      _db
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .where('empresas', arrayContains: empresaId)
          .get(),
      _db
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection(recordsCollection)
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection('TBL_HISTORIAL_PERSONAL')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);

    final users = <String, Map<String, dynamic>>{};
    for (final snapshot in results.take(2)) {
      for (final document in snapshot.docs) {
        users[document.id] = document.data();
      }
    }
    final organization = <String, Map<String, dynamic>>{};
    for (final snapshot in results.skip(2).take(2)) {
      for (final document in snapshot.docs) {
        final data = document.data();
        final cedula = _first(data, const ['cedula']).isNotEmpty
            ? _first(data, const ['cedula'])
            : document.id;
        organization[cedula] = data;
      }
    }

    // Recuperación defensiva para datos creados por versiones antiguas: la
    // carpeta sigue visible aunque los documentos principales se hayan
    // retirado físicamente por fuera del flujo actual de inactivación.
    final archived = <String, Map<String, dynamic>>{};
    for (final document in results[4].docs) {
      final data = document.data();
      final cedula = _first(data, const ['cedula']);
      if (cedula.isNotEmpty) archived.putIfAbsent(cedula, () => data);
    }
    final historyDates = <String, int>{};
    for (final document in results[5].docs) {
      final data = document.data();
      final cedula = _first(data, const ['cedula']);
      if (cedula.isEmpty) continue;
      final date = data['fecha'] is Timestamp
          ? (data['fecha'] as Timestamp).millisecondsSinceEpoch
          : 0;
      if (date >= (historyDates[cedula] ?? -1)) {
        historyDates[cedula] = date;
        final labor = data['datosLaborales'];
        archived[cedula] = <String, dynamic>{
          ...data,
          if (labor is Map) ...{
            for (final entry in labor.entries)
              entry.key.toString(): entry.value,
          },
        };
      }
    }

    final ids = <String>{...users.keys, ...organization.keys, ...archived.keys};
    final people = <DisciplinaryPerson>[];
    for (final cedula in ids) {
      final user = users[cedula] ?? const <String, dynamic>{};
      final org = organization[cedula] ?? const <String, dynamic>{};
      final archive = archived[cedula] ?? const <String, dynamic>{};
      final userScope = _scope(user, empresaId);
      final orgScope = _scope(org, empresaId);
      final name = _personName(user, <String, dynamic>{
        ...archive,
        ...orgScope,
      }, cedula);
      final area = _firstCombined(
        [orgScope, userScope, org, user, archive],
        const ['areaNombre', 'area'],
      );
      final role = _firstCombined(
        [orgScope, userScope, org, user, archive],
        const ['cargoNombre', 'cargo', 'cargoDesc'],
      );
      final costCenter = _firstCombined(
        [orgScope, userScope, org, user, archive],
        const ['centroCostos', 'centro_nombre'],
      );
      final status = PersonnelStatusService.normalizeStatus(
        _firstCombined(
          [orgScope, userScope, org, archive],
          const ['estado', 'estadoLaboral', 'estadoLaboralAlRegistrar'],
        ),
      );
      people.add(
        DisciplinaryPerson(
          cedula: cedula,
          name: name,
          area: area,
          role: role,
          costCenter: costCenter,
          photoUrl: _first(user, const ['fotoUrl', 'photoUrl']),
          status: status,
        ),
      );
    }
    people.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return people;
  }

  Future<String> createRecord({
    required String empresaId,
    required DisciplinaryPerson person,
    required String type,
    required String severity,
    required String subject,
    required String description,
    required DateTime incidentDate,
    required String createdBy,
    DateTime? responseDeadline,
    String policyReference = '',
    String expectedAction = '',
  }) async {
    final recordRef = _db.collection(recordsCollection).doc();
    final historyRef = _db.collection(historyCollection).doc();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.set(recordRef, {
      'personaKey': '${empresaId}_${person.cedula}',
      'empresaId': empresaId,
      'cedula': person.cedula,
      'nombre': person.name,
      'area': person.area,
      'cargo': person.role,
      'centroCostos': person.costCenter,
      'estadoLaboralAlRegistrar': person.status,
      'tipo': type,
      'gravedad': severity,
      'asunto': subject.trim(),
      'descripcion': description.trim(),
      'referenciaNormativa': policyReference.trim(),
      'accionEsperada': expectedAction.trim(),
      'estado': DisciplinaryStatus.pendingResponse,
      'fechaHecho': Timestamp.fromDate(incidentDate),
      if (responseDeadline != null)
        'fechaLimiteRespuesta': Timestamp.fromDate(responseDeadline),
      'creadoPor': createdBy,
      'creadoAt': now,
      'actualizadoPor': createdBy,
      'actualizadoAt': now,
    });
    batch.set(
      historyRef,
      _historyData(
        recordId: recordRef.id,
        empresaId: empresaId,
        cedula: person.cedula,
        event: 'creacion',
        detail: 'Se registró el llamado de atención: ${subject.trim()}',
        performedBy: createdBy,
        date: now,
      ),
    );
    await batch.commit();
    return recordRef.id;
  }

  Future<void> registerResponse({
    required DisciplinaryRecord record,
    required String response,
    required String performedBy,
  }) async {
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('La respuesta no puede estar vacía.');
    }
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'respuestaEmpleado': trimmed,
      'respondidoAt': now,
      'estado': DisciplinaryStatus.followUp,
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'respuesta',
        detail: 'Se registró la respuesta o los descargos del colaborador.',
        performedBy: performedBy,
        date: now,
      ),
    );
    await batch.commit();
  }

  Future<void> closeRecord({
    required DisciplinaryRecord record,
    required String conclusion,
    required String performedBy,
  }) async {
    final trimmed = conclusion.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('La conclusión no puede estar vacía.');
    }
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'conclusion': trimmed,
      'estado': DisciplinaryStatus.closed,
      'cerradoAt': now,
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'cierre',
        detail: trimmed,
        performedBy: performedBy,
        date: now,
      ),
    );
    await batch.commit();
  }

  Future<void> reopenRecord({
    required DisciplinaryRecord record,
    required String reason,
    required String performedBy,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'estado': DisciplinaryStatus.followUp,
      'motivoReapertura': reason.trim(),
      'cerradoAt': FieldValue.delete(),
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'reapertura',
        detail: reason.trim(),
        performedBy: performedBy,
        date: now,
      ),
    );
    await batch.commit();
  }

  Future<void> addEvidence({
    required DisciplinaryRecord record,
    required Uint8List bytes,
    required String fileName,
    required String performedBy,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('El archivo está vacío.');
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      throw ArgumentError('El archivo supera el límite de 10 MB.');
    }
    final safeName = fileName.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]+'),
      '_',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        'talento_humano/llamados/${record.empresaId}/${record.cedula}/'
        '${record.id}/${timestamp}_$safeName';
    final reference = _storage.ref(path);
    await reference.putData(
      bytes,
      SettableMetadata(contentType: _contentType(fileName)),
    );
    final url = await reference.getDownloadURL();
    final now = FieldValue.serverTimestamp();
    final attachment = <String, dynamic>{
      'nombre': fileName.trim(),
      'url': url,
      'storagePath': path,
      'subidoPor': performedBy,
      'fecha': Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'adjuntos': FieldValue.arrayUnion([attachment]),
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'adjunto',
        detail: 'Se agregó la evidencia ${fileName.trim()}.',
        performedBy: performedBy,
        date: now,
      ),
    );
    await batch.commit();
  }

  Map<String, dynamic> _historyData({
    required String recordId,
    required String empresaId,
    required String cedula,
    required String event,
    required String detail,
    required String performedBy,
    required FieldValue date,
  }) {
    return {
      'llamadoId': recordId,
      'empresaId': empresaId,
      'cedula': cedula,
      'evento': event,
      'detalle': detail,
      'realizadoPor': performedBy,
      'fecha': date,
    };
  }

  static Map<String, dynamic> _scope(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final details = data['empresasDetalle'];
    if (details is Map && details[empresaId] is Map) {
      return {
        for (final entry in (details[empresaId] as Map).entries)
          entry.key.toString(): entry.value,
      };
    }
    return const <String, dynamic>{};
  }

  static String _personName(
    Map<String, dynamic> user,
    Map<String, dynamic> org,
    String fallback,
  ) {
    final direct = _firstCombined(
      [org, user],
      const ['nombreCompleto', 'nombre', 'nombres'],
    );
    if (direct.isNotEmpty) return direct;
    final parts =
        [
              user['primerNombre'],
              user['segundoNombre'],
              user['primerApellido'],
              user['segundoApellido'],
            ]
            .map((value) => (value ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();
    return parts.isEmpty ? fallback : parts.join(' ');
  }

  static String _firstCombined(
    Iterable<Map<String, dynamic>> maps,
    List<String> keys,
  ) {
    for (final data in maps) {
      final value = _first(data, keys);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _first(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  static String _contentType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }
}
