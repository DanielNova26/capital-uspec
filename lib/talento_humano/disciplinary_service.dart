import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/festivos_colombia.dart';
import 'personnel_status_service.dart';

/// Plazo entre la entrega de la citación y la diligencia de descargos.
const kDiasHabilesDescargos = 5;

/// Etapas del proceso disciplinario.
///
/// El proceso avanza en un solo sentido y cada etapa exige su documento: no se
/// puede citar a descargos sin haber recibido la solicitud, ni cerrar sin la
/// diligencia. La etapa guardada es siempre **la última completada**, así que
/// lo que falta se deduce sin campos adicionales.
class DisciplinaryStage {
  /// Paso 1: se recibió la solicitud de apertura. Falta la citación.
  static const solicitud = 'solicitud';

  /// Paso 2: se entregó la citación. Falta la diligencia. Genera alerta.
  static const citacion = 'citacion';

  /// Paso 3: se realizó la diligencia. Falta el resultado. Genera alerta.
  static const diligencia = 'diligencia';

  /// Paso 4: hay sanción y documento del resultado. Proceso cerrado.
  static const cerrado = 'cerrado';

  static const abiertas = <String>{solicitud, citacion, diligencia};

  static const _todas = <String>{solicitud, citacion, diligencia, cerrado};

  static String normalize(dynamic value) {
    final stage = (value ?? '').toString().trim().toLowerCase();
    return _todas.contains(stage) ? stage : solicitud;
  }

  static String label(String stage) {
    switch (normalize(stage)) {
      case citacion:
        return 'Citado a descargos';
      case diligencia:
        return 'Diligencia realizada';
      case cerrado:
        return 'Cerrado';
      default:
        return 'Solicitud recibida';
    }
  }

  /// Lo que la etapa deja pendiente, en lenguaje de la operación.
  static String pendingLabel(String stage) {
    switch (normalize(stage)) {
      case citacion:
        return 'Pendiente la diligencia de descargos';
      case diligencia:
        return 'Pendiente el resultado';
      case cerrado:
        return 'Sin pendientes';
      default:
        return 'Pendiente la citación a descargos';
    }
  }

  /// Nombre del paso que sigue, para el botón de avance.
  static String nextActionLabel(String stage) {
    switch (normalize(stage)) {
      case citacion:
        return 'Montar acta de diligencia';
      case diligencia:
        return 'Cerrar con resultado';
      case cerrado:
        return 'Proceso cerrado';
      default:
        return 'Generar citación a descargos';
    }
  }
}

/// Las cuatro únicas formas de cerrar un proceso disciplinario **después de la
/// diligencia**, más el descarte temprano.
///
/// Es una lista cerrada por decisión de Talento Humano: el cierre no admite
/// conclusiones redactadas a mano porque la sanción tiene efectos laborales.
class DisciplinarySanction {
  static const exonerado = 'exonerado';
  static const llamadoEscrito = 'llamado_escrito';
  static const suspension = 'suspension';
  static const terminacion = 'terminacion_justa_causa';

  /// Cierre sin proceso: al evaluar la solicitud se concluye que el caso no
  /// da para disciplinario. No es una sanción y por eso no entra en [values]:
  /// solo puede aplicarse desde la etapa de solicitud, antes de citar a nadie.
  static const noCorresponde = 'no_corresponde';

  static const values = <String>[
    exonerado,
    llamadoEscrito,
    suspension,
    terminacion,
  ];

  static bool isValid(String value) => values.contains(value.trim());

  static String label(String value) {
    switch (value.trim()) {
      case exonerado:
        return 'Exonerado';
      case llamadoEscrito:
        return 'Llamado de Atención Escrito';
      case suspension:
        return 'Suspensión del contrato';
      case terminacion:
        return 'Terminación de contrato por justa causa';
      case noCorresponde:
        return 'No corresponde a proceso disciplinario';
      default:
        return '—';
    }
  }
}

/// Calificación del caso. Se elige **solo al cerrar**: al recibir la solicitud
/// nadie sabe todavía qué tan grave es, y pedirla antes obligaba a Talento
/// Humano a prejuzgar.
class DisciplinarySeverity {
  static const leve = 'leve';
  static const grave = 'grave';
  static const gravisima = 'gravisima';

  static const values = <String>[leve, grave, gravisima];

  static bool isValid(String value) => values.contains(value.trim());

  static String label(String value) {
    switch (value.trim()) {
      case leve:
        return 'Leve';
      case grave:
        return 'Grave';
      case gravisima:
        return 'Gravísima';
      default:
        return '—';
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
  final String stage;
  final String createdBy;
  final String updatedBy;

  /// Paso 1 — solicitud de apertura.
  final DateTime receivedAt;
  final DisciplinaryAttachment? requestDocument;

  /// Paso 2 — citación a descargos.
  final DateTime? summonDeliveredAt;
  final DateTime? hearingDate;
  final DisciplinaryAttachment? summonDocument;

  /// Paso 3 — diligencia de descargos.
  final DateTime? hearingHeldAt;
  final DateTime? resultDeadline;
  final DisciplinaryAttachment? hearingDocument;

  /// Paso 4 — resultado y cierre.
  final String sanction;
  final String severity;
  final DateTime? resultAt;
  final DisciplinaryAttachment? resultDocument;

  final DateTime? createdAt;

  const DisciplinaryRecord({
    required this.id,
    required this.empresaId,
    required this.cedula,
    required this.personName,
    required this.stage,
    required this.receivedAt,
    this.area = '',
    this.role = '',
    this.createdBy = '',
    this.updatedBy = '',
    this.requestDocument,
    this.summonDeliveredAt,
    this.hearingDate,
    this.summonDocument,
    this.hearingHeldAt,
    this.resultDeadline,
    this.hearingDocument,
    this.sanction = '',
    this.severity = '',
    this.resultAt,
    this.resultDocument,
    this.createdAt,
  });

  bool get isOpen => DisciplinaryStage.abiertas.contains(stage);
  bool get isClosed => stage == DisciplinaryStage.cerrado;

  /// Cerrado en la evaluación de la solicitud, sin citar ni oír a nadie. La
  /// carpeta no puede pintarlo como si hubiera recorrido las cuatro etapas.
  bool get closedWithoutProcess =>
      isClosed && sanction == DisciplinarySanction.noCorresponde;

  /// Estado en lenguaje de la operación, que no siempre es el de la etapa: un
  /// descarte temprano también es "cerrado", pero no por sanción.
  String get statusLabel => closedWithoutProcess
      ? 'Cerrado: no corresponde'
      : DisciplinaryStage.label(stage);

  /// Fecha límite de la etapa en curso, o null si no hay nada que vigilar.
  DateTime? get currentDeadline {
    switch (stage) {
      case DisciplinaryStage.citacion:
        return hearingDate;
      case DisciplinaryStage.diligencia:
        return resultDeadline;
      default:
        return null;
    }
  }

  /// Días que faltan para la fecha límite. Negativo si ya se venció.
  int? get daysToDeadline {
    final deadline = currentDeadline;
    if (deadline == null) return null;
    return atMidnight(deadline).difference(atMidnight(DateTime.now())).inDays;
  }

  bool get isOverdue => (daysToDeadline ?? 1) < 0;
  bool get isDueToday => daysToDeadline == 0;

  List<DisciplinaryAttachment> get attachments => [
    ?requestDocument,
    ?summonDocument,
    ?hearingDocument,
    ?resultDocument,
  ];

  factory DisciplinaryRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    DateTime? optionalDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    DisciplinaryAttachment? doc(String key) {
      final raw = data[key];
      if (raw is! Map) return null;
      return DisciplinaryAttachment.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    // Compatibilidad con registros del modelo anterior (asunto + gravedad, sin
    // etapa): se leen como "solicitud recibida" para que la carpeta del
    // colaborador nunca aparezca vacía ni reviente por un campo ausente.
    final legacyDate =
        optionalDate(data['fechaHecho']) ?? optionalDate(data['creadoAt']);

    return DisciplinaryRecord(
      id: document.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      personName: (data['nombre'] ?? '').toString(),
      area: (data['area'] ?? '').toString(),
      role: (data['cargo'] ?? '').toString(),
      stage: DisciplinaryStage.normalize(data['etapa']),
      createdBy: (data['creadoPor'] ?? '').toString(),
      updatedBy: (data['actualizadoPor'] ?? '').toString(),
      receivedAt:
          optionalDate(data['fechaRecibido']) ?? legacyDate ?? DateTime.now(),
      requestDocument: doc('docSolicitud'),
      summonDeliveredAt: optionalDate(data['fechaCitacion']),
      hearingDate: optionalDate(data['fechaDiligencia']),
      summonDocument: doc('docCitacion'),
      hearingHeldAt: optionalDate(data['fechaDiligenciaRealizada']),
      resultDeadline: optionalDate(data['fechaLimiteResultado']),
      hearingDocument: doc('docDiligencia'),
      sanction: (data['sancion'] ?? '').toString(),
      severity: (data['gravedad'] ?? '').toString(),
      resultAt: optionalDate(data['fechaResultado']),
      resultDocument: doc('docResultado'),
      createdAt: optionalDate(data['creadoAt']),
    );
  }
}

class DisciplinaryAttachment {
  final String name;
  final String url;
  final String storagePath;
  final String stage;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const DisciplinaryAttachment({
    required this.name,
    required this.url,
    required this.storagePath,
    required this.uploadedBy,
    this.stage = '',
    this.uploadedAt,
  });

  factory DisciplinaryAttachment.fromMap(Map<String, dynamic> data) {
    final rawDate = data['fecha'];
    return DisciplinaryAttachment(
      name: (data['nombre'] ?? 'Documento').toString(),
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      stage: (data['etapa'] ?? '').toString(),
      uploadedBy: (data['subidoPor'] ?? '').toString(),
      uploadedAt: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

/// Documento que aún no se ha subido a Storage: bytes y nombre elegidos por el
/// usuario. Cada etapa exige uno, así que viaja junto con las fechas del paso.
class DisciplinaryUpload {
  final Uint8List bytes;
  final String fileName;

  const DisciplinaryUpload({required this.bytes, required this.fileName});
}

class DisciplinaryMetrics {
  final int total;
  final int inProgress;
  final int overdue;
  final int closed;

  const DisciplinaryMetrics({
    required this.total,
    required this.inProgress,
    required this.overdue,
    required this.closed,
  });

  factory DisciplinaryMetrics.fromRecords(
    Iterable<DisciplinaryRecord> records,
  ) {
    final items = records.toList();
    return DisciplinaryMetrics(
      total: items.length,
      inProgress: items.where((item) => item.isOpen).length,
      overdue: items.where((item) => item.isOverdue).length,
      closed: items.where((item) => item.isClosed).length,
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

  /// Fecha sugerida de la diligencia: 5 días hábiles desde la citación.
  static DateTime fechaDiligenciaSugerida(DateTime entregaCitacion) =>
      sumarDiasHabilesColombia(entregaCitacion, kDiasHabilesDescargos);

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
            final aDate = a.createdAt ?? a.receivedAt;
            final bDate = b.createdAt ?? b.receivedAt;
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

  /// Paso 1. Se recibe la solicitud de apertura: fecha de recibido y el
  /// documento que llegó. Talento Humano no describe la falta aquí: radica.
  Future<String> abrirProceso({
    required String empresaId,
    required DisciplinaryPerson person,
    required DateTime receivedAt,
    required DisciplinaryUpload document,
    required String createdBy,
  }) async {
    final recordRef = _db.collection(recordsCollection).doc();
    final attachment = await _uploadDocument(
      empresaId: empresaId,
      cedula: person.cedula,
      recordId: recordRef.id,
      stage: DisciplinaryStage.solicitud,
      upload: document,
      performedBy: createdBy,
    );
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
      'etapa': DisciplinaryStage.solicitud,
      'fechaRecibido': Timestamp.fromDate(receivedAt),
      'docSolicitud': attachment,
      'creadoPor': createdBy,
      'creadoAt': now,
      'actualizadoPor': createdBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: recordRef.id,
        empresaId: empresaId,
        cedula: person.cedula,
        event: 'solicitud',
        detail:
            'Se recibió la solicitud de apertura del proceso disciplinario '
            '(${_formatDate(receivedAt)}).',
        performedBy: createdBy,
      ),
    );
    await batch.commit();
    return recordRef.id;
  }

  /// Paso 2. Se monta la citación a descargos con el documento entregado al
  /// colaborador y la fecha de la diligencia: esa fecha es la que se vigila.
  Future<void> registrarCitacion({
    required DisciplinaryRecord record,
    required DateTime deliveredAt,
    required DateTime hearingDate,
    required DisciplinaryUpload document,
    required String performedBy,
  }) async {
    _requireStage(
      record,
      DisciplinaryStage.solicitud,
      'la citación a descargos',
    );
    if (atMidnight(hearingDate).isBefore(atMidnight(deliveredAt))) {
      throw ArgumentError(
        'La fecha de la diligencia no puede ser anterior a la entrega de la '
        'citación.',
      );
    }
    final attachment = await _uploadDocument(
      empresaId: record.empresaId,
      cedula: record.cedula,
      recordId: record.id,
      stage: DisciplinaryStage.citacion,
      upload: document,
      performedBy: performedBy,
    );
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'etapa': DisciplinaryStage.citacion,
      'fechaCitacion': Timestamp.fromDate(deliveredAt),
      'fechaDiligencia': Timestamp.fromDate(hearingDate),
      'docCitacion': attachment,
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'citacion',
        detail:
            'Se entregó la citación a descargos el '
            '${_formatDate(deliveredAt)}. Diligencia programada para el '
            '${_formatDate(hearingDate)}.',
        performedBy: performedBy,
      ),
    );
    await batch.commit();
  }

  /// Paso 3. Se monta la diligencia realizada y la fecha en que debe salir el
  /// resultado: esa fecha genera la segunda alerta.
  Future<void> registrarDiligencia({
    required DisciplinaryRecord record,
    required DateTime heldAt,
    required DateTime resultDeadline,
    required DisciplinaryUpload document,
    required String performedBy,
  }) async {
    _requireStage(record, DisciplinaryStage.citacion, 'la diligencia');
    if (atMidnight(resultDeadline).isBefore(atMidnight(heldAt))) {
      throw ArgumentError(
        'La fecha del resultado no puede ser anterior a la diligencia.',
      );
    }
    final attachment = await _uploadDocument(
      empresaId: record.empresaId,
      cedula: record.cedula,
      recordId: record.id,
      stage: DisciplinaryStage.diligencia,
      upload: document,
      performedBy: performedBy,
    );
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'etapa': DisciplinaryStage.diligencia,
      'fechaDiligenciaRealizada': Timestamp.fromDate(heldAt),
      'fechaLimiteResultado': Timestamp.fromDate(resultDeadline),
      'docDiligencia': attachment,
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'diligencia',
        detail:
            'Se realizó la diligencia de descargos el ${_formatDate(heldAt)}. '
            'El resultado debe darse a más tardar el '
            '${_formatDate(resultDeadline)}.',
        performedBy: performedBy,
      ),
    );
    await batch.commit();
  }

  /// Cierre temprano: al evaluar la solicitud se concluye que el caso no da
  /// para proceso disciplinario. Se cierra sin citar ni oír a nadie, así que
  /// no hay sanción ni gravedad que calificar. El documento es opcional
  /// porque aquí no hay pieza obligatoria que adjuntar: la decisión queda en
  /// la trazabilidad con su autor y su fecha.
  Future<void> descartarSolicitud({
    required DisciplinaryRecord record,
    required String performedBy,
    DisciplinaryUpload? document,
  }) async {
    _requireStage(
      record,
      DisciplinaryStage.solicitud,
      'que la solicitud no corresponde',
    );
    final attachment = document == null
        ? null
        : await _uploadDocument(
            empresaId: record.empresaId,
            cedula: record.cedula,
            recordId: record.id,
            stage: 'resultado',
            upload: document,
            performedBy: performedBy,
          );
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'etapa': DisciplinaryStage.cerrado,
      'sancion': DisciplinarySanction.noCorresponde,
      'fechaResultado': Timestamp.fromDate(DateTime.now()),
      'docResultado': ?attachment,
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
        event: 'descarte',
        detail:
            'Se evaluó la solicitud y se concluyó que el caso no corresponde '
            'a un proceso disciplinario. Se cerró sin citación a descargos.',
        performedBy: performedBy,
      ),
    );
    await batch.commit();
  }

  /// Paso 4. El resultado cierra el proceso, y solo con una de las cuatro
  /// sanciones definidas. La gravedad se califica aquí y no antes: al recibir
  /// la solicitud todavía no se sabe.
  Future<void> cerrarConResultado({
    required DisciplinaryRecord record,
    required String sanction,
    required String severity,
    required DateTime resultAt,
    required DisciplinaryUpload document,
    required String performedBy,
  }) async {
    _requireStage(record, DisciplinaryStage.diligencia, 'el resultado');
    if (!DisciplinarySanction.isValid(sanction)) {
      throw ArgumentError('La sanción registrada no es válida.');
    }
    if (!DisciplinarySeverity.isValid(severity)) {
      throw ArgumentError('La gravedad registrada no es válida.');
    }
    final attachment = await _uploadDocument(
      empresaId: record.empresaId,
      cedula: record.cedula,
      recordId: record.id,
      stage: 'resultado',
      upload: document,
      performedBy: performedBy,
    );
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      'etapa': DisciplinaryStage.cerrado,
      'sancion': sanction.trim(),
      'gravedad': severity.trim(),
      'fechaResultado': Timestamp.fromDate(resultAt),
      'docResultado': attachment,
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
        event: 'resultado',
        detail:
            'Se cerró el proceso con la sanción: '
            '${DisciplinarySanction.label(sanction)}. '
            'Gravedad calificada: ${DisciplinarySeverity.label(severity)} '
            '(${_formatDate(resultAt)}).',
        performedBy: performedBy,
      ),
    );
    await batch.commit();
  }

  /// Reemplaza el documento de una etapa ya cumplida sin mover el proceso.
  /// Sirve cuando se sube el archivo equivocado; el anterior queda en Storage
  /// y el cambio queda anotado en la trazabilidad.
  Future<void> reemplazarDocumento({
    required DisciplinaryRecord record,
    required String stage,
    required DisciplinaryUpload document,
    required String performedBy,
  }) async {
    final field = _documentField[stage];
    if (field == null) throw ArgumentError('Etapa desconocida: $stage');
    final attachment = await _uploadDocument(
      empresaId: record.empresaId,
      cedula: record.cedula,
      recordId: record.id,
      stage: stage,
      upload: document,
      performedBy: performedBy,
    );
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_db.collection(recordsCollection).doc(record.id), {
      field: attachment,
      'actualizadoPor': performedBy,
      'actualizadoAt': now,
    });
    batch.set(
      _db.collection(historyCollection).doc(),
      _historyData(
        recordId: record.id,
        empresaId: record.empresaId,
        cedula: record.cedula,
        event: 'documento',
        detail:
            'Se reemplazó el documento de "${_stageDocumentLabel(stage)}" por '
            '${document.fileName.trim()}.',
        performedBy: performedBy,
      ),
    );
    await batch.commit();
  }

  static const _documentField = <String, String>{
    DisciplinaryStage.solicitud: 'docSolicitud',
    DisciplinaryStage.citacion: 'docCitacion',
    DisciplinaryStage.diligencia: 'docDiligencia',
    'resultado': 'docResultado',
  };

  static String _stageDocumentLabel(String stage) {
    switch (stage) {
      case DisciplinaryStage.citacion:
        return 'Citación a descargos';
      case DisciplinaryStage.diligencia:
        return 'Diligencia de descargos';
      case 'resultado':
        return 'Resultado de la diligencia';
      default:
        return 'Solicitud de apertura';
    }
  }

  static String stageDocumentLabel(String stage) =>
      _stageDocumentLabel(stage);

  void _requireStage(
    DisciplinaryRecord record,
    String expected,
    String action,
  ) {
    if (record.stage == expected) return;
    throw StateError(
      'No se puede registrar $action: el proceso está en '
      '"${DisciplinaryStage.label(record.stage)}".',
    );
  }

  Future<Map<String, dynamic>> _uploadDocument({
    required String empresaId,
    required String cedula,
    required String recordId,
    required String stage,
    required DisciplinaryUpload upload,
    required String performedBy,
  }) async {
    if (upload.bytes.isEmpty) throw ArgumentError('El archivo está vacío.');
    if (upload.bytes.lengthInBytes > 10 * 1024 * 1024) {
      throw ArgumentError('El archivo supera el límite de 10 MB.');
    }
    final safeName = upload.fileName.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]+'),
      '_',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        'talento_humano/llamados/$empresaId/$cedula/'
        '$recordId/${stage}_${timestamp}_$safeName';
    final reference = _storage.ref(path);
    await reference.putData(
      upload.bytes,
      SettableMetadata(contentType: _contentType(upload.fileName)),
    );
    final url = await reference.getDownloadURL();
    return <String, dynamic>{
      'nombre': upload.fileName.trim(),
      'url': url,
      'storagePath': path,
      'etapa': stage,
      'subidoPor': performedBy,
      'fecha': Timestamp.now(),
    };
  }

  Map<String, dynamic> _historyData({
    required String recordId,
    required String empresaId,
    required String cedula,
    required String event,
    required String detail,
    required String performedBy,
  }) {
    return {
      'llamadoId': recordId,
      'empresaId': empresaId,
      'cedula': cedula,
      'evento': event,
      'detalle': detail,
      'realizadoPor': performedBy,
      'fecha': FieldValue.serverTimestamp(),
    };
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
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

/// Normaliza una fecha a medianoche: los plazos del proceso se comparan por
/// día, nunca por hora.
DateTime atMidnight(DateTime value) =>
    DateTime(value.year, value.month, value.day);
