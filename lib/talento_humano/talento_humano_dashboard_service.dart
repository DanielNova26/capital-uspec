import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'disciplinary_service.dart';
import 'personnel_requisition_models.dart';
import 'personnel_requisition_service.dart';
import 'personnel_status_service.dart';
import 'resume_management_report.dart';

class TalentoHumanoDistributionItem {
  final String label;
  final int value;

  const TalentoHumanoDistributionItem({
    required this.label,
    required this.value,
  });
}

class TalentoHumanoDashboardData {
  final int totalPeople;
  final int activePeople;
  final int inactivePeople;
  final int approvedResumes;
  final int resumesInReview;
  final int resumesWithChanges;
  final int resumesNotSent;
  final int activeCostCenters;
  final int activeAreas;
  final int peopleWithoutCostCenter;
  final int peopleWithoutArea;
  final int openDisciplinaryCases;
  final int highSeverityCases;
  final int openPersonnelRequests;
  final int priorityPersonnelRequests;
  final int pendingPersonnelVacancies;
  final List<ResumeManagementRow> pendingResumePeople;
  final List<TalentoHumanoDistributionItem> costCenterDistribution;
  final List<String> unavailableSources;
  final DateTime generatedAt;

  const TalentoHumanoDashboardData({
    required this.totalPeople,
    required this.activePeople,
    required this.inactivePeople,
    required this.approvedResumes,
    required this.resumesInReview,
    required this.resumesWithChanges,
    required this.resumesNotSent,
    required this.activeCostCenters,
    required this.activeAreas,
    required this.peopleWithoutCostCenter,
    required this.peopleWithoutArea,
    required this.openDisciplinaryCases,
    required this.highSeverityCases,
    required this.costCenterDistribution,
    required this.generatedAt,
    this.unavailableSources = const [],
    this.openPersonnelRequests = 0,
    this.priorityPersonnelRequests = 0,
    this.pendingPersonnelVacancies = 0,
    this.pendingResumePeople = const [],
  });

  int get pendingResumes =>
      resumesInReview + resumesWithChanges + resumesNotSent;

  double get resumeCompletion => activePeople == 0
      ? 0
      : (approvedResumes / activePeople).clamp(0, 1).toDouble();

  double get costCenterCoverage => activePeople == 0
      ? 0
      : ((activePeople - peopleWithoutCostCenter) / activePeople)
            .clamp(0, 1)
            .toDouble();

  bool get isPartial => unavailableSources.isNotEmpty;

  factory TalentoHumanoDashboardData.fromMaps({
    required Iterable<Map<String, dynamic>> people,
    required Iterable<Map<String, dynamic>> costCenters,
    required Iterable<Map<String, dynamic>> areas,
    required Iterable<Map<String, dynamic>> disciplinaryRecords,
    Iterable<Map<String, dynamic>> personnelRequests = const [],
    DateTime? generatedAt,
    List<String> unavailableSources = const [],
  }) {
    final peopleList = people.toList();
    final now = generatedAt ?? DateTime.now();
    var active = 0;
    var inactive = 0;
    var approved = 0;
    var inReview = 0;
    var withChanges = 0;
    var notSent = 0;
    var withoutCostCenter = 0;
    var withoutArea = 0;
    final distribution = <String, int>{};
    final pendingResumePeople = <ResumeManagementRow>[];

    String text(dynamic value) => (value ?? '').toString().trim();
    String firstText(Map<String, dynamic> data, List<String> keys) {
      for (final key in keys) {
        final value = text(data[key]);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    DateTime? date(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    for (final person in peopleList) {
      final employmentStatus = PersonnelStatusService.normalizeStatus(
        person['estadoLaboral'] ?? person['estado'],
      );
      if (employmentStatus == PersonnelStatusService.inactive) {
        inactive++;
        continue;
      }
      active++;

      final resumeStatus = text(
        person['estadoHojaDeVida'] ?? person['estadoRevisionHojaDeVida'],
      ).toLowerCase();
      switch (resumeStatus) {
        case 'aprobado':
          approved++;
          break;
        case 'en_revision':
          inReview++;
          break;
        case 'requiere_cambios':
          withChanges++;
          break;
        default:
          notSent++;
      }
      if (resumeStatus != 'aprobado') {
        final normalizedStatus = switch (resumeStatus) {
          'en_revision' => 'en_revision',
          'requiere_cambios' => 'requiere_cambios',
          _ => 'sin_enviar',
        };
        final composedName = [
          text(person['primerNombre']),
          text(person['segundoNombre']),
          text(person['primerApellido']),
          text(person['segundoApellido']),
        ].where((part) => part.isNotEmpty).join(' ');
        final document = firstText(person, const [
          'cedula',
          'documento',
          'usuario',
          '_documentId',
        ]);
        pendingResumePeople.add(
          ResumeManagementRow(
            document: document,
            fullName:
                firstText(person, const [
                  'nombreCompleto',
                  'nombre',
                  'displayName',
                ]).isNotEmpty
                ? firstText(person, const [
                    'nombreCompleto',
                    'nombre',
                    'displayName',
                  ])
                : composedName.isNotEmpty
                ? composedName
                : document,
            status: normalizedStatus,
            action: switch (normalizedStatus) {
              'requiere_cambios' =>
                'Contactar y solicitar las correcciones indicadas',
              'en_revision' => 'Revisar y aprobar o devolver la hoja de vida',
              _ => 'Solicitar el diligenciamiento y envío de la hoja de vida',
            },
            correctionNote: firstText(person, const [
              'correctionNote',
              'revisionNote',
              'revisionNota',
            ]),
            phone: firstText(person, const ['telefono', 'celular', 'phone']),
            email: firstText(person, const ['correo', 'email']),
            position: firstText(person, const [
              'cargoNombre',
              'cargo',
              'cargo_desc',
            ]),
            area: firstText(person, const ['areaNombre', 'area']),
            costCenter: firstText(person, const [
              'centroCostos',
              'centro_nombre',
              'centroNombre',
            ]),
            requestedAt: date(person['correctionRequestedAt']),
            updatedAt: date(switch (normalizedStatus) {
              'requiere_cambios' =>
                person['correctionUpdatedAt'] ??
                    person['correctionRequestedAt'],
              'en_revision' => person['fechaEnvio'] ?? person['updatedAt'],
              _ => person['createdAt'] ?? person['updatedAt'],
            }),
          ),
        );
      }

      final costCenter = text(
        person['centroCostos'] ??
            person['centro_nombre'] ??
            person['centroNombre'],
      );
      if (costCenter.isEmpty) {
        withoutCostCenter++;
      } else {
        distribution[costCenter] = (distribution[costCenter] ?? 0) + 1;
      }

      final area = text(person['areaNombre'] ?? person['area']);
      if (area.isEmpty) withoutArea++;
    }

    var openCases = 0;
    var highSeverity = 0;
    for (final record in disciplinaryRecords) {
      final status = DisciplinaryStatus.normalize(record['estado']);
      if (DisciplinaryStatus.active.contains(status)) openCases++;
      if (text(record['gravedad']).toLowerCase() == 'alta' &&
          status != DisciplinaryStatus.closed &&
          status != DisciplinaryStatus.cancelled) {
        highSeverity++;
      }
    }

    var openPersonnelRequests = 0;
    var priorityPersonnelRequests = 0;
    var pendingPersonnelVacancies = 0;
    for (final data in personnelRequests) {
      final request = PersonnelRequisition.fromMap('', data);
      if (request.isClosed) continue;
      openPersonnelRequests++;
      pendingPersonnelVacancies += request.pendingCount;
      if (request.trafficAt(now) == PersonnelRequisitionTraffic.red) {
        priorityPersonnelRequests++;
      }
    }

    final costCenterItems =
        distribution.entries
            .map(
              (entry) => TalentoHumanoDistributionItem(
                label: entry.key,
                value: entry.value,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byValue = b.value.compareTo(a.value);
            return byValue != 0 ? byValue : a.label.compareTo(b.label);
          });

    return TalentoHumanoDashboardData(
      totalPeople: peopleList.length,
      activePeople: active,
      inactivePeople: inactive,
      approvedResumes: approved,
      resumesInReview: inReview,
      resumesWithChanges: withChanges,
      resumesNotSent: notSent,
      activeCostCenters: costCenters
          .where((item) => item['enabled'] != false)
          .length,
      activeAreas: areas.where((item) => item['enabled'] != false).length,
      peopleWithoutCostCenter: withoutCostCenter,
      peopleWithoutArea: withoutArea,
      openDisciplinaryCases: openCases,
      highSeverityCases: highSeverity,
      openPersonnelRequests: openPersonnelRequests,
      priorityPersonnelRequests: priorityPersonnelRequests,
      pendingPersonnelVacancies: pendingPersonnelVacancies,
      pendingResumePeople: pendingResumePeople,
      costCenterDistribution: costCenterItems.take(6).toList(),
      unavailableSources: unavailableSources,
      generatedAt: now,
    );
  }
}

class TalentoHumanoDashboardService {
  final FirebaseFirestore _db;

  TalentoHumanoDashboardService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<TalentoHumanoDashboardData> load(String empresaId) async {
    final unavailable = <String>[];
    final peopleDocuments = <String, Map<String, dynamic>>{};

    Future<void> loadPeopleQuery(
      Query<Map<String, dynamic>> query,
      String source,
    ) async {
      try {
        final snapshot = await query.get();
        for (final document in snapshot.docs) {
          peopleDocuments[document.id] = {
            ...document.data(),
            '_documentId': document.id,
          };
        }
      } catch (_) {
        if (!unavailable.contains(source)) unavailable.add(source);
      }
    }

    await Future.wait([
      loadPeopleQuery(
        _db
            .collection('TBL_USUARIOS')
            .where('empresas', arrayContains: empresaId),
        'personal',
      ),
      loadPeopleQuery(
        _db.collection('TBL_USUARIOS').where('empresaId', isEqualTo: empresaId),
        'personal',
      ),
    ]);

    Future<List<Map<String, dynamic>>> safeCompanyCollection(
      String collection,
      String source,
    ) async {
      try {
        final snapshot = await _db
            .collection(collection)
            .where('empresaId', isEqualTo: empresaId)
            .get();
        return snapshot.docs.map((document) => document.data()).toList();
      } catch (_) {
        if (!unavailable.contains(source)) unavailable.add(source);
        return const [];
      }
    }

    final supportingData = await Future.wait([
      safeCompanyCollection('TBL_CENTROS_COSTOS', 'centros de costo'),
      safeCompanyCollection('TBL_AREAS', 'áreas'),
      safeCompanyCollection(
        DisciplinaryService.recordsCollection,
        'procesos disciplinarios',
      ),
      safeCompanyCollection(
        PersonnelRequisitionService.collection,
        'requerimientos de personal',
      ),
    ]);

    final scopedPeople = peopleDocuments.values
        .map((person) => mergeCompanyScopedData(person, empresaId))
        .where((person) {
          final companies = extractUserEmpresaIds(person);
          return companies.contains(empresaId) ||
              (person['empresaId'] ?? '').toString().trim() == empresaId;
        })
        .toList();

    return TalentoHumanoDashboardData.fromMaps(
      people: scopedPeople,
      costCenters: supportingData[0],
      areas: supportingData[1],
      disciplinaryRecords: supportingData[2],
      personnelRequests: supportingData[3],
      unavailableSources: unavailable,
    );
  }
}
