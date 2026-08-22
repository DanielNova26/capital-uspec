import '../core/festivos_colombia.dart';

enum PersonnelRequisitionStage {
  requested,
  recruitment,
  preselection,
  interview,
  exams,
  documents,
  hired,
  cancelled,
}

extension PersonnelRequisitionStageX on PersonnelRequisitionStage {
  String get value => switch (this) {
    PersonnelRequisitionStage.requested => 'solicitado',
    PersonnelRequisitionStage.recruitment => 'reclutamiento',
    PersonnelRequisitionStage.preselection => 'preseleccion',
    PersonnelRequisitionStage.interview => 'entrevista',
    PersonnelRequisitionStage.exams => 'examenes',
    PersonnelRequisitionStage.documents => 'documentos',
    PersonnelRequisitionStage.hired => 'contratado',
    PersonnelRequisitionStage.cancelled => 'cancelado',
  };

  String get label => switch (this) {
    PersonnelRequisitionStage.requested => 'Solicitud recibida',
    PersonnelRequisitionStage.recruitment => 'Reclutamiento',
    PersonnelRequisitionStage.preselection => 'Preselección',
    PersonnelRequisitionStage.interview => 'Entrevistas',
    PersonnelRequisitionStage.exams => 'Exámenes y estudio',
    PersonnelRequisitionStage.documents => 'Documentación',
    PersonnelRequisitionStage.hired => 'Contratado',
    PersonnelRequisitionStage.cancelled => 'Cancelado',
  };

  bool get isClosed =>
      this == PersonnelRequisitionStage.hired ||
      this == PersonnelRequisitionStage.cancelled;

  static PersonnelRequisitionStage parse(Object? raw) {
    final normalized = (raw ?? '').toString().trim().toLowerCase().replaceAll(
      RegExp(r'[^a-záéíóúñ0-9]+'),
      '_',
    );
    if (normalized.contains('cancel') || normalized.contains('anulad')) {
      return PersonnelRequisitionStage.cancelled;
    }
    if (normalized.contains('contrat') || normalized.contains('finaliz')) {
      return PersonnelRequisitionStage.hired;
    }
    if (normalized.contains('document') || normalized.contains('firma')) {
      return PersonnelRequisitionStage.documents;
    }
    if (normalized.contains('examen') || normalized.contains('estudio')) {
      return PersonnelRequisitionStage.exams;
    }
    if (normalized.contains('entrevista')) {
      return PersonnelRequisitionStage.interview;
    }
    if (normalized.contains('presele') || normalized.contains('terna')) {
      return PersonnelRequisitionStage.preselection;
    }
    if (normalized.contains('reclut')) {
      return PersonnelRequisitionStage.recruitment;
    }
    return PersonnelRequisitionStage.requested;
  }
}

enum PersonnelRequisitionTraffic { green, yellow, red, closed }

int businessDaysElapsed(DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  if (!end.isAfter(start)) return 0;
  var cursor = start;
  var result = 0;
  while (cursor.isBefore(end)) {
    cursor = cursor.add(const Duration(days: 1));
    if (!esNoHabil(cursor)) result++;
  }
  return result;
}

PersonnelRequisitionTraffic requisitionTraffic({
  required int businessDays,
  required bool closed,
}) {
  if (closed) return PersonnelRequisitionTraffic.closed;
  if (businessDays >= 15) return PersonnelRequisitionTraffic.red;
  if (businessDays >= 8) return PersonnelRequisitionTraffic.yellow;
  return PersonnelRequisitionTraffic.green;
}

class PersonnelHire {
  final String document;
  final String documentType;
  final String names;
  final String surnames;
  final String email;
  final String phone;
  final DateTime? hiredAt;
  final String createdBy;

  const PersonnelHire({
    required this.document,
    required this.names,
    required this.surnames,
    this.documentType = 'CC',
    this.email = '',
    this.phone = '',
    this.hiredAt,
    this.createdBy = '',
  });

  String get fullName => '$names $surnames'.trim();

  factory PersonnelHire.fromMap(Map<String, dynamic> data) => PersonnelHire(
    document: _text(data['documento'] ?? data['cedula']),
    documentType: _text(data['tipoDocumento']).isEmpty
        ? 'CC'
        : _text(data['tipoDocumento']),
    names: _text(data['nombres']),
    surnames: _text(data['apellidos']),
    email: _text(data['correo']),
    phone: _text(data['telefono']),
    hiredAt: _date(data['fechaContratacion']),
    createdBy: _text(data['creadoPor']),
  );

  Map<String, dynamic> toMap({Object? hiredAtValue}) => {
    'documento': document,
    'tipoDocumento': documentType,
    'nombres': names,
    'apellidos': surnames,
    'nombreCompleto': fullName,
    'correo': email,
    'telefono': phone,
    'fechaContratacion': hiredAtValue ?? hiredAt,
    'creadoPor': createdBy,
  };
}

class PersonnelRequisitionHistoryEntry {
  final PersonnelRequisitionStage stage;
  final String advanceType;
  final String result;
  final String note;
  final String userId;
  final DateTime? date;

  const PersonnelRequisitionHistoryEntry({
    required this.stage,
    this.advanceType = '',
    this.result = '',
    this.note = '',
    this.userId = '',
    this.date,
  });

  factory PersonnelRequisitionHistoryEntry.fromMap(Map<String, dynamic> data) =>
      PersonnelRequisitionHistoryEntry(
        stage: PersonnelRequisitionStageX.parse(data['etapa']),
        advanceType: _text(data['tipoAvance']),
        result: _text(data['resultado']),
        note: _text(data['nota']),
        userId: _text(data['usuario']),
        date: _date(data['fecha']),
      );
}

class PersonnelRequisition {
  final String id;
  final String empresaId;
  final String groupId;
  final String group;
  final String costCenterId;
  final String establishment;
  final bool annex;
  final String position;
  final int quantity;
  final num? salary;
  final DateTime requestDate;
  final PersonnelRequisitionStage stage;
  final String observations;
  final String processNote;
  final List<PersonnelHire> hires;
  final List<PersonnelRequisitionHistoryEntry> history;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  const PersonnelRequisition({
    required this.id,
    required this.empresaId,
    required this.establishment,
    required this.position,
    required this.quantity,
    required this.requestDate,
    this.groupId = '',
    this.group = '',
    this.costCenterId = '',
    this.annex = false,
    this.salary,
    this.stage = PersonnelRequisitionStage.requested,
    this.observations = '',
    this.processNote = '',
    this.hires = const [],
    this.history = const [],
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
    this.closedAt,
  });

  bool get isClosed => stage.isClosed;
  int get hiredCount => hires.length;
  int get pendingCount => (quantity - hiredCount).clamp(0, quantity);

  int daysAt(DateTime now) => businessDaysElapsed(
    requestDate,
    closedAt != null && closedAt!.isBefore(now) ? closedAt! : now,
  );

  PersonnelRequisitionTraffic trafficAt(DateTime now) =>
      requisitionTraffic(businessDays: daysAt(now), closed: isClosed);

  factory PersonnelRequisition.fromMap(String id, Map<String, dynamic> data) {
    final rawHires = data['contratados'];
    final rawHistory = data['historial'];
    return PersonnelRequisition(
      id: id,
      empresaId: _text(data['empresaId']),
      groupId: _text(data['grupoId']),
      group: _text(data['grupo']),
      costCenterId: _text(data['centroId']),
      establishment: _text(data['establecimiento'] ?? data['centroCostos']),
      annex: _bool(data['anexo']),
      position: _text(data['cargo']),
      quantity: _integer(data['cantidad'], fallback: 1).clamp(1, 999),
      salary: _number(data['salario']),
      requestDate: _date(data['fechaSolicitud']) ?? DateTime.now(),
      stage: PersonnelRequisitionStageX.parse(
        data['etapa'] ?? data['proceso'] ?? data['estado'],
      ),
      observations: _text(data['observaciones']),
      processNote: _text(data['notaProceso'] ?? data['comentarios']),
      hires: rawHires is Iterable
          ? rawHires
                .whereType<Map>()
                .map(
                  (item) => PersonnelHire.fromMap(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList()
          : const [],
      history: rawHistory is Iterable
          ? (rawHistory
                .whereType<Map>()
                .map(
                  (item) => PersonnelRequisitionHistoryEntry.fromMap(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList()
              ..sort((a, b) {
                if (a.date == null && b.date == null) return 0;
                if (a.date == null) return 1;
                if (b.date == null) return -1;
                return b.date!.compareTo(a.date!);
              }))
          : const [],
      createdBy: _text(data['creadoPor']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      closedAt: _date(data['fechaCierre']),
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'grupoId': groupId,
    'grupo': group,
    'centroId': costCenterId,
    'centroCostos': establishment,
    'establecimiento': establishment,
    'anexo': annex,
    'cargo': position,
    'cantidad': quantity,
    'salario': salary,
    'fechaSolicitud': requestDate,
    'etapa': stage.value,
    'estado': isClosed ? stage.value : 'abierto',
    'observaciones': observations,
    'notaProceso': processNote,
    'contratados': hires.map((hire) => hire.toMap()).toList(),
    'cantidadContratada': hiredCount,
    'creadoPor': createdBy,
  };
}

enum PersonnelRequisitionRole { manager, recruiter, requester, viewer }

class PersonnelRequisitionAccess {
  final PersonnelRequisitionRole role;

  const PersonnelRequisitionAccess(this.role);

  bool get canCreate => role != PersonnelRequisitionRole.viewer;
  bool get canUpdateStage =>
      role == PersonnelRequisitionRole.manager ||
      role == PersonnelRequisitionRole.recruiter;
  bool get canRegisterHire => canUpdateStage;
  bool get canCancel => role == PersonnelRequisitionRole.manager;
  bool get canExport => true;

  static PersonnelRequisitionAccess fromUserData(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final rawDetails = data['empresasDetalle'];
    final rawScoped = rawDetails is Map ? rawDetails[empresaId] : null;
    final scoped = rawScoped is Map
        ? rawScoped.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final rawRole = _text(
      scoped['rolTalentoHumano'] ??
          scoped['talentoHumanoRol'] ??
          scoped['roleKey'] ??
          data['rolTalentoHumano'] ??
          data['roleKey'] ??
          data['role'] ??
          data['rol'],
    ).toLowerCase();

    if (rawRole.contains('consulta') ||
        rawRole.contains('visor') ||
        rawRole.contains('viewer')) {
      return const PersonnelRequisitionAccess(PersonnelRequisitionRole.viewer);
    }
    if (rawRole.contains('solicit')) {
      return const PersonnelRequisitionAccess(
        PersonnelRequisitionRole.requester,
      );
    }
    if (rawRole.contains('reclut')) {
      return const PersonnelRequisitionAccess(
        PersonnelRequisitionRole.recruiter,
      );
    }
    return const PersonnelRequisitionAccess(PersonnelRequisitionRole.manager);
  }
}

String _text(Object? value) => (value ?? '').toString().trim();

bool _bool(Object? value) {
  if (value is bool) return value;
  final normalized = _text(value).toLowerCase();
  return const {'1', 'si', 'sí', 's', 'true', 'x'}.contains(normalized);
}

int _integer(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value).replaceAll(RegExp(r'[^0-9-]'), '')) ??
      fallback;
}

num? _number(Object? value) {
  if (value is num) return value;
  final normalized = _text(value).replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (normalized.isEmpty) return null;
  return num.tryParse(normalized.replaceAll(',', ''));
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    final dynamic raw = value;
    final converted = raw.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {}
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.tryParse(_text(value));
}
