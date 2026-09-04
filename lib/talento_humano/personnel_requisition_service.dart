import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;

import '../utils/text_input_formatters.dart';
import '../utils/user_company.dart';
import 'personnel_requisition_models.dart';

const personnelTemporaryPassword = '123456';

/// ¿Hay que darle contraseña temporal a esta persona?
///
/// No la necesita quien ya ingresó al menos una vez: en el primer ingreso el
/// backend migra la clave a `TBL_AUTH_CREDENTIALS` (cifrada), **borra** el
/// campo `password` del usuario y marca `authVersion: 2`. Sin mirar ese
/// marcador, "sin password" parecería una cuenta sin acceso y le pediríamos
/// cambiar una clave que ya tiene.
bool personnelNeedsTemporaryPassword(Map<String, dynamic> existing) {
  final migrado = (existing['authVersion'] as num?)?.toInt() == 2;
  if (migrado) return false;
  return (existing['password'] ?? '').toString().trim().isEmpty;
}

/// Credenciales de acceso al crear o vincular a una persona.
///
/// Nunca pisa una contraseña existente: solo asigna la temporal cuando la
/// cuenta todavía no tiene forma de entrar.
Map<String, dynamic> personnelAccessCredentials(Map<String, dynamic> existing) {
  if (!personnelNeedsTemporaryPassword(existing)) {
    final currentPassword = (existing['password'] ?? '').toString().trim();
    return {
      if (currentPassword.isNotEmpty) 'password': existing['password'],
      'needsPasswordChange': existing['needsPasswordChange'] == true,
    };
  }
  return const {
    'password': personnelTemporaryPassword,
    'needsPasswordChange': true,
  };
}

class RequisitionImportSection {
  final String name;
  final List<PersonnelRequisition> rows;

  const RequisitionImportSection({required this.name, required this.rows});
}

class PersonnelRequisitionCatalogItem {
  final String id;
  final String name;
  final String code;

  const PersonnelRequisitionCatalogItem({
    required this.id,
    required this.name,
    this.code = '',
  });

  String get label => code.isEmpty ? name : '$code · $name';
}

class PersonnelRequisitionCatalogs {
  final List<PersonnelRequisitionCatalogItem> costCenters;
  final List<PersonnelRequisitionCatalogItem> groups;

  /// Cargos del maestro (`TBL_CARGOS`). Se usan para que "Cargo requerido"
  /// deje de ser texto libre: dos formas de escribir el mismo cargo partían
  /// el informe en dos filas que nadie podía consolidar.
  final List<PersonnelRequisitionCatalogItem> positions;

  const PersonnelRequisitionCatalogs({
    required this.costCenters,
    required this.groups,
    this.positions = const [],
  });
}

class PersonnelRequisitionService {
  static const collection = 'TBL_TH_REQUERIMIENTOS_PERSONAL';

  final FirebaseFirestore _db;

  PersonnelRequisitionService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Stream<List<PersonnelRequisition>> streamForCompany(String empresaId) {
    return _db
        .collection(collection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .map((snapshot) {
          final rows = snapshot.docs
              .map((doc) => PersonnelRequisition.fromMap(doc.id, doc.data()))
              .toList();
          rows.sort(comparePersonnelRequisitions);
          return rows;
        });
  }

  /// Orden estándar del módulo: **por establecimiento** y, dentro de cada uno,
  /// lo más reciente primero.
  ///
  /// Es un requisito de presentación, no un capricho de la pantalla: el
  /// informe que recibe la interventoría se lee sede por sede, y el orden
  /// puramente cronológico obligaba a rastrear un mismo establecimiento por
  /// toda la hoja. La tabla, el Excel y el PDF comparten este comparador para
  /// que las tres salidas se lean igual.
  static int comparePersonnelRequisitions(
    PersonnelRequisition a,
    PersonnelRequisition b,
  ) {
    final byEstablishment = a.establishment.toLowerCase().compareTo(
      b.establishment.toLowerCase(),
    );
    if (byEstablishment != 0) return byEstablishment;
    final byDate = b.requestDate.compareTo(a.requestDate);
    if (byDate != 0) return byDate;
    return a.position.toLowerCase().compareTo(b.position.toLowerCase());
  }

  Future<PersonnelRequisitionAccess> loadAccess({
    required String userId,
    required String empresaId,
  }) async {
    final users = _db.collection('TBL_USUARIOS');
    DocumentSnapshot<Map<String, dynamic>>? doc;
    final direct = await users.doc(userId).get();
    if (direct.exists) doc = direct;
    if (doc == null) {
      final byCedula = await users
          .where('cedula', isEqualTo: userId)
          .limit(1)
          .get();
      if (byCedula.docs.isNotEmpty) doc = byCedula.docs.first;
    }
    if (doc == null) {
      final byUid = await users.where('uid', isEqualTo: userId).limit(1).get();
      if (byUid.docs.isNotEmpty) doc = byUid.docs.first;
    }
    return PersonnelRequisitionAccess.fromUserData(
      doc?.data() ?? const <String, dynamic>{},
      empresaId,
    );
  }

  Future<String> create({
    required PersonnelRequisition requisition,
    required String userId,
  }) async {
    if (requisition.empresaId.trim().isEmpty ||
        requisition.establishment.trim().isEmpty ||
        requisition.position.trim().isEmpty) {
      throw ArgumentError('Empresa, establecimiento y cargo son obligatorios.');
    }
    final ref = _db.collection(collection).doc();
    await ref.set({
      ...requisition.toMap(),
      'creadoPor': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoPor': userId,
      'historial': [
        {
          'etapa': requisition.stage.value,
          'nota': 'Solicitud creada',
          'usuario': userId,
          'fecha': Timestamp.now(),
        },
      ],
    });
    return ref.id;
  }

  Future<void> update({
    required PersonnelRequisition requisition,
    required String userId,
  }) async {
    if (requisition.id.trim().isEmpty ||
        requisition.establishment.trim().isEmpty ||
        requisition.position.trim().isEmpty) {
      throw ArgumentError('Establecimiento y cargo son obligatorios.');
    }
    await _db.collection(collection).doc(requisition.id).update({
      ...requisition.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoPor': userId,
      'historial': FieldValue.arrayUnion([
        {
          'etapa': requisition.stage.value,
          'nota': 'Datos de la solicitud editados',
          'usuario': userId,
          'fecha': Timestamp.now(),
        },
      ]),
    });
  }

  Future<void> delete({required String requisitionId}) async {
    final id = requisitionId.trim();
    if (id.isEmpty) {
      throw ArgumentError(
        'El requerimiento que se va a eliminar no es válido.',
      );
    }
    await _db.collection(collection).doc(id).delete();
  }

  Future<PersonnelRequisitionCatalogs> loadCatalogs(String empresaId) async {
    final snapshots = await Future.wait([
      _db
          .collection('TBL_CENTROS_COSTOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection('TBL_COMPRAS_GRUPOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
      _db
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    final costCenters =
        snapshots[0].docs
            .where((doc) => doc.data()['enabled'] != false)
            .map(
              (doc) => PersonnelRequisitionCatalogItem(
                id: _text(doc.data()['centroId']).isEmpty
                    ? doc.id
                    : _text(doc.data()['centroId']),
                name: _text(doc.data()['nombre']).isEmpty
                    ? _text(doc.data()['codigo'])
                    : _text(doc.data()['nombre']),
                code: _text(doc.data()['codigo']),
              ),
            )
            .where((item) => item.name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    final groups =
        snapshots[1].docs
            .where((doc) => doc.data()['activo'] != false)
            .map(
              (doc) => PersonnelRequisitionCatalogItem(
                id: doc.id,
                name: _text(doc.data()['nombre']),
                code: _text(doc.data()['codigo']),
              ),
            )
            .where((item) => item.name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    // El nombre es la clave, no el doc id: la vacante guarda `cargo` como
    // texto y así lo consumen el Excel y el resto del módulo. El id se
    // conserva solo para poder preseleccionar el desplegable.
    final positions =
        snapshots[2].docs
            .where((doc) => doc.data()['enabled'] != false)
            .map(
              (doc) => PersonnelRequisitionCatalogItem(
                id: doc.id,
                name: _text(doc.data()['nombre']),
              ),
            )
            .where((item) => item.name.isNotEmpty)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return PersonnelRequisitionCatalogs(
      costCenters: costCenters,
      groups: groups,
      positions: positions,
    );
  }

  Future<int> importRows({
    required String empresaId,
    required String userId,
    required Iterable<PersonnelRequisition> rows,
  }) async {
    final valid = rows
        .where(
          (row) =>
              row.establishment.trim().isNotEmpty &&
              row.position.trim().isNotEmpty,
        )
        .toList();
    for (var offset = 0; offset < valid.length; offset += 400) {
      final batch = _db.batch();
      final end = (offset + 400).clamp(0, valid.length);
      for (final row in valid.sublist(offset, end)) {
        final ref = _db.collection(collection).doc();
        batch.set(ref, {
          ...row.toMap(),
          'empresaId': empresaId,
          'creadoPor': userId,
          'origen': 'excel',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoPor': userId,
          'historial': [
            {
              'etapa': row.stage.value,
              'nota': 'Importado desde Excel',
              'usuario': userId,
              'fecha': Timestamp.now(),
            },
          ],
        });
      }
      await batch.commit();
    }
    return valid.length;
  }

  Future<void> updateStage({
    required PersonnelRequisition requisition,
    required PersonnelRequisitionStage stage,
    required String note,
    required String userId,
    String advanceType = '',
    String result = '',
  }) async {
    if (requisition.isClosed) {
      throw StateError('Una solicitud cerrada no puede cambiar de etapa.');
    }
    final closed = stage.isClosed;
    await _db.collection(collection).doc(requisition.id).update({
      'etapa': stage.value,
      'estado': closed ? stage.value : 'abierto',
      'notaProceso': note.trim(),
      'tipoUltimoAvance': advanceType.trim(),
      'resultadoUltimoAvance': result.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoPor': userId,
      if (closed) 'fechaCierre': FieldValue.serverTimestamp(),
      'historial': FieldValue.arrayUnion([
        {
          'etapa': stage.value,
          'tipoAvance': advanceType.trim(),
          'resultado': result.trim(),
          'nota': note.trim(),
          'usuario': userId,
          'fecha': Timestamp.now(),
        },
      ]),
    });
  }

  // ── Aspirantes: el avance se registra por persona ─────────────────────────
  //
  // El estado global de la vacante dejó de ser lo que se mueve a mano: se
  // deriva del aspirante que va más adelante. Así el informe puede decir
  // "dos en entrevistas, uno en exámenes" en vez de un único "entrevistas"
  // que no distingue a nadie.

  Future<void> addCandidate({
    required PersonnelRequisition requisition,
    required PersonnelCandidate candidate,
    required String userId,
  }) async {
    final document = _cleanDocument(candidate.document);
    if (document.isEmpty || candidate.names.trim().isEmpty) {
      throw ArgumentError(
        'Documento y nombres del aspirante son obligatorios.',
      );
    }
    final ref = _db.collection(collection).doc(requisition.id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('La solicitud ya no existe.');
      final current = PersonnelRequisition.fromMap(
        snapshot.id,
        snapshot.data() ?? const <String, dynamic>{},
      );
      if (current.stage == PersonnelRequisitionStage.cancelled) {
        throw StateError('La solicitud está cancelada.');
      }
      if (current.candidates.any((item) => item.document == document)) {
        throw StateError('Ese aspirante ya está en la solicitud.');
      }
      final now = Timestamp.now();
      final added = PersonnelCandidate(
        document: document,
        documentType: candidate.documentType,
        names: capitalizarPalabras(candidate.names.trim()),
        surnames: capitalizarPalabras(candidate.surnames.trim()),
        email: candidate.email.trim(),
        phone: candidate.phone.trim(),
        stage: candidate.stage,
        note: candidate.note.trim(),
        createdBy: userId,
        updatedBy: userId,
      );
      final next = [...current.candidates, added];
      transaction.update(ref, {
        'candidatos': next.map((item) => item.toMap(timestamp: now)).toList(),
        'candidatosActivos': next.where((item) => item.isActive).length,
        ..._derivedStagePatch(current, next),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoPor': userId,
        'historial': FieldValue.arrayUnion([
          {
            'etapa': added.stage.requisitionStage.value,
            'tipoAvance': 'Aspirante agregado',
            'resultado': 'continua',
            'nota': '${added.fullName} ($document) · ${added.stage.label}',
            'usuario': userId,
            'fecha': now,
          },
        ]),
      });
    });
  }

  Future<void> updateCandidateStage({
    required PersonnelRequisition requisition,
    required String document,
    required PersonnelCandidateStage stage,
    required String note,
    required String userId,
  }) async {
    final target = _cleanDocument(document);
    final ref = _db.collection(collection).doc(requisition.id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('La solicitud ya no existe.');
      final current = PersonnelRequisition.fromMap(
        snapshot.id,
        snapshot.data() ?? const <String, dynamic>{},
      );
      final index = current.candidates.indexWhere(
        (item) => item.document == target,
      );
      if (index < 0) throw StateError('Ese aspirante ya no está en la lista.');
      // Contratar no se hace desde aquí: crea usuario en TBL_USUARIOS y cierra
      // la vacante, así que pasa por registerHireAndCreateUser.
      if (stage == PersonnelCandidateStage.hired) {
        throw StateError(
          'Para contratar usa "Registrar contratación": ahí se crea el usuario.',
        );
      }
      final now = Timestamp.now();
      final previous = current.candidates[index];
      final next = [...current.candidates];
      next[index] = previous.copyWith(
        stage: stage,
        note: note.trim(),
        updatedAt: now.toDate(),
        updatedBy: userId,
      );
      transaction.update(ref, {
        'candidatos': next.map((item) => item.toMap(timestamp: now)).toList(),
        'candidatosActivos': next.where((item) => item.isActive).length,
        ..._derivedStagePatch(current, next),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoPor': userId,
        'historial': FieldValue.arrayUnion([
          {
            'etapa': stage.requisitionStage.value,
            'tipoAvance': '${previous.fullName} · ${stage.label}',
            'resultado': stage == PersonnelCandidateStage.discarded
                ? 'no_continua'
                : 'continua',
            'nota': note.trim(),
            'usuario': userId,
            'fecha': now,
          },
        ]),
      });
    });
  }

  /// Etapa de la vacante derivada de sus aspirantes.
  ///
  /// Solo avanza: si alguien ya estaba en documentación y el único candidato
  /// vivo retrocede a entrevistas, la vacante no vuelve atrás — el tiempo
  /// transcurrido y el semáforo se calculan sobre lo que ya ocurrió. Tampoco
  /// toca las etapas de cierre: `contratado` lo escribe la contratación y
  /// `cancelado` la cancelación.
  Map<String, dynamic> _derivedStagePatch(
    PersonnelRequisition current,
    List<PersonnelCandidate> candidates,
  ) {
    if (current.isClosed) return const {};
    final furthest = candidates
        .where((item) => item.stage != PersonnelCandidateStage.discarded)
        .fold<PersonnelCandidateStage?>(
          null,
          (best, item) =>
              best == null || item.stage.order > best.order ? item.stage : best,
        );
    if (furthest == null) return const {};
    final derived = furthest.requisitionStage;
    if (derived.isClosed) return const {};
    if (_stageOrder(derived) <= _stageOrder(current.stage)) return const {};
    return {'etapa': derived.value, 'estado': 'abierto'};
  }

  static int _stageOrder(PersonnelRequisitionStage stage) => switch (stage) {
    PersonnelRequisitionStage.requested => 0,
    PersonnelRequisitionStage.recruitment => 1,
    PersonnelRequisitionStage.preselection => 2,
    PersonnelRequisitionStage.interview => 3,
    PersonnelRequisitionStage.exams => 4,
    PersonnelRequisitionStage.documents => 5,
    PersonnelRequisitionStage.hired => 6,
    PersonnelRequisitionStage.cancelled => 6,
  };

  static String _cleanDocument(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');

  Future<bool> registerHireAndCreateUser({
    required PersonnelRequisition requisition,
    required PersonnelHire hire,
    required String userId,
  }) async {
    final document = hire.document.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (document.isEmpty || hire.names.trim().isEmpty) {
      throw ArgumentError(
        'Documento y nombres de la persona son obligatorios.',
      );
    }
    final reqRef = _db.collection(collection).doc(requisition.id);
    final userRef = _db.collection('TBL_USUARIOS').doc(document);

    return _db.runTransaction<bool>((transaction) async {
      final reqSnapshot = await transaction.get(reqRef);
      if (!reqSnapshot.exists) throw StateError('La solicitud ya no existe.');
      final current = PersonnelRequisition.fromMap(
        reqSnapshot.id,
        reqSnapshot.data() ?? const <String, dynamic>{},
      );
      if (current.stage == PersonnelRequisitionStage.cancelled) {
        throw StateError(
          'No se puede contratar sobre una solicitud cancelada.',
        );
      }
      if (current.hires.any((item) => item.document == document)) {
        throw StateError('Esta persona ya fue registrada en la solicitud.');
      }
      if (current.hiredCount >= current.quantity) {
        throw StateError('La cantidad solicitada ya fue completada.');
      }

      final userSnapshot = await transaction.get(userRef);
      final existing = userSnapshot.data() ?? const <String, dynamic>{};
      final temporaryPasswordAssigned = _text(existing['password']).isEmpty;
      final companies = <String>{
        ..._stringList(existing['empresas']),
        current.empresaId,
      }.toList();
      final rawDetails = existing['empresasDetalle'];
      final details = rawDetails is Map
          ? rawDetails.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      final rawCompany = details[current.empresaId];
      final company = rawCompany is Map
          ? rawCompany.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      company.addAll({
        'cargo': current.position,
        'cargoNombre': current.position,
        'centroCostos': current.establishment,
        'estado': 'activo',
        'estadoLaboral': 'activo',
        'fechaIngreso': Timestamp.now(),
      });

      // Accesos a módulos elegidos por Talento Humano al contratar.
      // Contratar solo SUMA: si la persona ya existía con módulos en esta
      // empresa, los conserva. Quitar accesos se hace en Accesos del personal.
      final nextApps = normalizeAppIdList([
        ...extractUserApps(existing, empresaId: current.empresaId),
        ...hire.apps,
      ]).ids..sort();
      company['apps'] = nextApps;

      // Antes de pisar la lista global se congela lo que cada otra empresa
      // heredaba de ella, para no quitarle módulos a la persona allá.
      for (final otra in details.keys.toList()) {
        if (otra == current.empresaId) continue;
        final raw = details[otra];
        final bloque = raw is Map
            ? raw.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};
        if (bloque['apps'] is List) continue;
        bloque['apps'] = normalizeAppIdList(
          extractUserApps(existing, empresaId: otra),
        ).ids..sort();
        details[otra] = bloque;
      }

      details[current.empresaId] = company;

      transaction.set(userRef, {
        ...existing,
        'usuario': document,
        'cedula': document,
        'tipoDocumento': hire.documentType,
        'nombres': capitalizarPalabras(hire.names.trim()),
        'apellidos': capitalizarPalabras(hire.surnames.trim()),
        'nombreCompleto': capitalizarPalabras(hire.fullName),
        if (hire.email.trim().isNotEmpty) 'correo': hire.email.trim(),
        if (hire.phone.trim().isNotEmpty) 'telefono': hire.phone.trim(),
        'empresaId': current.empresaId,
        'empresas': companies,
        'empresasDetalle': details,
        'apps': nextApps,
        'estado': 'activo',
        'estadoLaboral': 'activo',
        'role': existing['role'] ?? 'usuario',
        ...personnelAccessCredentials(existing),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!userSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      });

      final hired = PersonnelHire(
        document: document,
        documentType: hire.documentType,
        names: capitalizarPalabras(hire.names.trim()),
        surnames: capitalizarPalabras(hire.surnames.trim()),
        email: hire.email.trim(),
        phone: hire.phone.trim(),
        hiredAt: DateTime.now(),
        createdBy: userId,
      );
      final nextHires = [...current.hires, hired];
      final complete = nextHires.length >= current.quantity;

      // El aspirante pasa a "Contratado" en su propia ficha. Si la persona
      // nunca se registró como candidato (contratación directa) se agrega
      // ahora, para que el informe por persona no tenga huecos.
      final stamp = Timestamp.now();
      final nextCandidates = [...current.candidates];
      final candidateIndex = nextCandidates.indexWhere(
        (item) => item.document == document,
      );
      if (candidateIndex >= 0) {
        nextCandidates[candidateIndex] = nextCandidates[candidateIndex]
            .copyWith(
              stage: PersonnelCandidateStage.hired,
              updatedAt: stamp.toDate(),
              updatedBy: userId,
            );
      } else {
        nextCandidates.add(
          PersonnelCandidate(
            document: document,
            documentType: hired.documentType,
            names: hired.names,
            surnames: hired.surnames,
            email: hired.email,
            phone: hired.phone,
            stage: PersonnelCandidateStage.hired,
            note: 'Contratación registrada directamente',
            createdBy: userId,
            updatedBy: userId,
          ),
        );
      }

      transaction.update(reqRef, {
        'contratados': nextHires
            .map((item) => item.toMap(hiredAtValue: Timestamp.now()))
            .toList(),
        'cantidadContratada': nextHires.length,
        'candidatos': nextCandidates
            .map((item) => item.toMap(timestamp: stamp))
            .toList(),
        'candidatosActivos': nextCandidates
            .where((item) => item.isActive)
            .length,
        'etapa': complete
            ? PersonnelRequisitionStage.hired.value
            : PersonnelRequisitionStage.documents.value,
        'estado': complete ? 'contratado' : 'abierto',
        if (complete) 'fechaCierre': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoPor': userId,
        'historial': FieldValue.arrayUnion([
          {
            'etapa': complete ? 'contratado' : 'documentos',
            'nota': 'Usuario creado para ${hired.fullName} ($document)',
            'usuario': userId,
            'fecha': Timestamp.now(),
          },
        ]),
      });
      return temporaryPasswordAssigned;
    });
  }
}

List<RequisitionImportSection> initialPersonnelRequisitionSections() => [
  RequisitionImportSection(
    name: 'Capital USPEC',
    rows: [
      _initialRow(
        group: '6',
        establishment: 'PICOTA',
        position: 'NUTRICIONISTA',
        annex: true,
        salary: 3051000,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 3),
      ),
      _initialRow(
        group: '6',
        establishment: 'PICOTA',
        position: 'INGENIERO DE ALIMENTOS',
        annex: true,
        salary: 3051000,
        process: 'EXAMENES 20/agosto/2026',
        observations: 'Reemplazo Embarazo',
        date: DateTime(2026, 8, 3),
      ),
      _initialRow(
        group: '6',
        establishment: 'PICOTA',
        position: 'JEFE DE COCINA',
        annex: true,
        salary: 2630000,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 13),
      ),
      _initialRow(
        group: '7',
        establishment: 'MODELO',
        position: 'NUTRICIONISTA',
        annex: true,
        salary: 3051000,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 3),
      ),
      _initialRow(
        group: '7',
        establishment: 'RIO NEGRO',
        position: 'MANIPULADOR DE ALIMENTOS',
        annex: true,
        salary: 3051000,
        process: 'EXAMENES 21/agosto/2026',
        date: DateTime(2026, 8, 3),
      ),
      _initialRow(
        group: '7',
        establishment: 'COTA',
        position: 'ABOGADO',
        annex: true,
        salary: 3000000,
        process: 'ENTREVISTA 20/agosto/2026',
        date: DateTime(2026, 8, 19),
      ),
    ],
  ),
  RequisitionImportSection(
    name: 'Servir',
    rows: [
      _initialRow(
        group: '9',
        establishment: 'COMBITA',
        position: 'TECNICO LOCATIVO',
        annex: true,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 1),
      ),
      _initialRow(
        group: '9',
        establishment: 'SANTA ROSA',
        position: 'AUX ADMINISTRATIVA',
        annex: false,
        process: 'EN ESTUDIO Y EXAMENES',
        date: DateTime(2026, 8, 1),
      ),
      _initialRow(
        group: '9',
        establishment: 'BUEN PASTOR',
        position: 'AUXILIAR DE PROCESOS',
        annex: false,
        quantity: 2,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 1),
      ),
      _initialRow(
        group: '9',
        establishment: 'SOGAMOSO',
        position: 'INGENIERO DE ALIMENTOS',
        annex: true,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 19),
      ),
      _initialRow(
        group: '1',
        establishment: 'PASTO',
        position: 'INGENIERO DE CALIDAD',
        annex: false,
        process: 'EXAMENES Y ESTUDIO',
        date: DateTime(2026, 8, 15),
      ),
    ],
  ),
  RequisitionImportSection(
    name: 'FYC',
    rows: [
      _initialRow(
        establishment: 'FYC',
        position: 'MANIPULADOR DE ALIMENTOS',
        annex: true,
        salary: 1750905,
        process: 'EXAMENES 20/agosto/2026',
        date: DateTime(2026, 7, 30),
      ),
      _initialRow(
        establishment: 'FYC',
        position: 'AYUDANTE DE DISTRIBUCION',
        annex: true,
        salary: 1750905,
        process: 'RECLUTAMIENTO',
        date: DateTime(2026, 8, 10),
      ),
      _initialRow(
        establishment: 'FYC',
        position: 'ADMINISTRADOR',
        annex: true,
        salary: 3500000,
        date: DateTime(2026, 8, 19),
      ),
      _initialRow(
        establishment: 'FYC',
        position: 'INGENIERO',
        annex: true,
        salary: 2680000,
        date: DateTime(2026, 8, 19),
      ),
    ],
  ),
];

PersonnelRequisition _initialRow({
  String group = '',
  required String establishment,
  required String position,
  required bool annex,
  int quantity = 1,
  num? salary,
  String process = '',
  String observations = '',
  required DateTime date,
}) => PersonnelRequisition(
  id: '',
  empresaId: '',
  group: group,
  establishment: establishment,
  position: position,
  annex: annex,
  quantity: quantity,
  salary: salary,
  requestDate: date,
  stage: PersonnelRequisitionStageX.parse(process),
  processNote: process,
  observations: observations,
);

List<RequisitionImportSection> parsePersonnelRequisitionWorkbook(
  Uint8List bytes,
) {
  final workbook = xl.Excel.decodeBytes(bytes);
  final result = <RequisitionImportSection>[];
  for (final sheetName in workbook.tables.keys) {
    final sheet = workbook.tables[sheetName];
    if (sheet == null) continue;
    String sectionName = sheetName;
    Map<String, int>? columns;
    var sectionRows = <PersonnelRequisition>[];

    void flush() {
      if (sectionRows.isEmpty) return;
      result.add(
        RequisitionImportSection(
          name: sectionName.trim().isEmpty ? sheetName : sectionName.trim(),
          rows: List.unmodifiable(sectionRows),
        ),
      );
      sectionRows = <PersonnelRequisition>[];
    }

    for (final row in sheet.rows) {
      final values = row.map((cell) => _cellText(cell?.value)).toList();
      final joined = values.where((value) => value.isNotEmpty).join(' ');
      if (_normalize(joined).contains('solicitud_de_personal')) {
        flush();
        sectionName = joined;
        columns = null;
        continue;
      }
      final normalized = values.map(_normalize).toList();
      if (normalized.contains('cargo') &&
          normalized.any((value) => value.contains('fecha_de_solicitud'))) {
        columns = {
          for (var i = 0; i < normalized.length; i++) normalized[i]: i,
        };
        continue;
      }
      if (columns == null) continue;
      String pick(List<String> names) {
        for (final name in names) {
          final index = columns![name];
          if (index != null && index < values.length) return values[index];
        }
        return '';
      }

      final establishment = pick(const ['establecimiento', 'sede']);
      final position = pick(const ['cargo', 'vacante']);
      if (establishment.isEmpty || position.isEmpty) continue;
      final process = pick(const ['proceso', 'comentarios', 'estado']);
      final requestDate = _parseExcelDate(
        pick(const ['fecha_de_solicitud', 'fecha_solicitud', 'fecha']),
      );
      sectionRows.add(
        PersonnelRequisition(
          id: '',
          empresaId: '',
          group: pick(const ['grupo']),
          establishment: establishment,
          annex: _yes(pick(const ['anexo'])),
          position: position,
          quantity: _int(pick(const ['cantidad']), fallback: 1).clamp(1, 999),
          salary: _num(pick(const ['salario'])),
          requestDate: requestDate ?? DateTime.now(),
          stage: PersonnelRequisitionStageX.parse(process),
          processNote: process,
          observations: pick(const ['observaciones']),
        ),
      );
    }
    flush();
  }
  return result;
}

/// Posición de la columna "Salario" en el informe. Se nombra para que el
/// formato de moneda no dependa de contar cabeceras a mano.
const int _salaryColumnIndex = 10;

Uint8List buildPersonnelRequisitionReport({
  required List<PersonnelRequisition> rows,
  required String empresaId,
  String empresaNombre = '',
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();
  // El informe se entrega ordenado por establecimiento aunque quien exporta
  // tenga la tabla filtrada de otra forma.
  final ordered = [...rows]
    ..sort(PersonnelRequisitionService.comparePersonnelRequisitions);
  final excel = xl.Excel.createExcel();
  excel.rename('Sheet1', 'Requerimientos');
  final sheet = excel['Requerimientos'];
  const headers = [
    'Nivel de atención',
    'Días hábiles',
    'Fecha solicitud',
    'Grupo',
    'Establecimiento',
    'Anexo',
    'Cargo',
    'Cantidad',
    'Contratados',
    'Pendientes',
    'Salario',
    'Etapa actual',
    'Aspirantes en proceso',
    'Avance por aspirante',
    'Nota del proceso',
    'Observaciones',
    'Historial de avances',
    'Personas contratadas',
    'Documentos',
    'Fecha cierre',
  ];

  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
  );
  final title = sheet.cell(xl.CellIndex.indexByString('A1'));
  title.value = xl.TextCellValue('INFORME DE REQUERIMIENTOS DE PERSONAL');
  title.cellStyle = xl.CellStyle(
    bold: true,
    fontSize: 15,
    fontColorHex: xl.ExcelColor.white,
    backgroundColorHex: xl.ExcelColor.fromHexString('#173B5E'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  sheet.setRowHeight(0, 30);
  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 1),
  );
  final meta = sheet.cell(xl.CellIndex.indexByString('A2'));
  meta.value = xl.TextCellValue(
    'Empresa: ${empresaNombre.trim().isEmpty ? empresaId : empresaNombre.trim()} · '
    'Registros: ${ordered.length} · Generado: ${_dateLabel(now)} · '
    'Ordenado por establecimiento · '
    'Seguimiento: próxima a vencer desde 8 días hábiles; atención prioritaria desde 15.',
  );
  meta.cellStyle = xl.CellStyle(
    italic: true,
    fontColorHex: xl.ExcelColor.fromHexString('#475569'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#EAF4FB'),
  );

  final headerStyle = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.white,
    backgroundColorHex: xl.ExcelColor.fromHexString('#246B9E'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
  );
  for (var column = 0; column < headers.length; column++) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 3),
    );
    cell.value = xl.TextCellValue(headers[column]);
    cell.cellStyle = headerStyle;
  }
  sheet.setRowHeight(3, 34);

  for (var index = 0; index < ordered.length; index++) {
    final row = ordered[index];
    final traffic = row.trafficAt(now);
    final values = <xl.CellValue>[
      xl.TextCellValue(_trafficLabel(traffic)),
      xl.IntCellValue(row.daysAt(now)),
      xl.DateTimeCellValue.fromDateTime(row.requestDate),
      xl.TextCellValue(row.group),
      xl.TextCellValue(row.establishment),
      xl.TextCellValue(row.annex ? 'Sí' : 'No'),
      xl.TextCellValue(row.position),
      xl.IntCellValue(row.quantity),
      xl.IntCellValue(row.hiredCount),
      xl.IntCellValue(row.pendingCount),
      row.salary == null
          ? xl.TextCellValue('')
          : xl.DoubleCellValue(row.salary!.toDouble()),
      xl.TextCellValue(row.stage.label),
      xl.IntCellValue(row.activeCandidates.length),
      // Una línea por persona: es lo que pidió la interventoría en vez del
      // estado único de la vacante.
      xl.TextCellValue(
        row.candidates
            .map(
              (candidate) => [
                candidate.fullName,
                candidate.document,
                candidate.stage.label,
                if (candidate.note.isNotEmpty) candidate.note,
              ].join(' | '),
            )
            .join('\n'),
      ),
      xl.TextCellValue(row.processNote),
      xl.TextCellValue(row.observations),
      xl.TextCellValue(
        row.history
            .map(
              (entry) => [
                if (entry.date != null) _dateLabel(entry.date!),
                entry.advanceType.isEmpty
                    ? entry.stage.label
                    : entry.advanceType,
                if (entry.result.isNotEmpty) _historyResult(entry.result),
                if (entry.note.isNotEmpty) entry.note,
              ].join(' | '),
            )
            .join('\n'),
      ),
      xl.TextCellValue(row.hires.map((hire) => hire.fullName).join(' · ')),
      xl.TextCellValue(row.hires.map((hire) => hire.document).join(' · ')),
      row.closedAt == null
          ? xl.TextCellValue('')
          : xl.DateTimeCellValue.fromDateTime(row.closedAt!),
    ];
    final rowIndex = index + 4;
    for (var column = 0; column < values.length; column++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
      );
      cell.value = values[column];
      final background = column == 0
          ? _trafficColor(traffic)
          : index.isOdd
          ? '#F7F9FB'
          : '#FFFFFF';
      cell.cellStyle = xl.CellStyle(
        verticalAlign: xl.VerticalAlign.Top,
        textWrapping: xl.TextWrapping.WrapText,
        backgroundColorHex: xl.ExcelColor.fromHexString(background),
        // El salario sale como número con separador de miles: como texto
        // plano no se podía sumar ni filtrar en la hoja, y con el formato
        // general "1423500" era ilegible.
        numberFormat: values[column] is xl.DateTimeCellValue
            ? const xl.CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy')
            : column == _salaryColumnIndex
            ? const xl.CustomNumericNumFormat(formatCode: r'$ #,##0')
            : xl.NumFormat.standard_0,
        horizontalAlign: column == _salaryColumnIndex
            ? xl.HorizontalAlign.Right
            : xl.HorizontalAlign.Left,
        bold: column == 0,
      );
    }
  }

  const widths = <double>[
    14, // Nivel de atención
    13, // Días hábiles
    17, // Fecha solicitud
    10, // Grupo
    23, // Establecimiento
    10, // Anexo
    31, // Cargo
    11, // Cantidad
    12, // Contratados
    11, // Pendientes
    17, // Salario
    22, // Etapa actual
    13, // Aspirantes en proceso
    46, // Avance por aspirante
    34, // Nota del proceso
    48, // Observaciones
    34, // Historial de avances
    34, // Personas contratadas
    24, // Documentos
    17, // Fecha cierre
  ];
  for (var column = 0; column < widths.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
  }
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el informe de requerimientos.');
  }
  return Uint8List.fromList(encoded);
}

List<String> _stringList(Object? raw) {
  if (raw is! Iterable) return const [];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _text(Object? value) => (value ?? '').toString().trim();

String _cellText(xl.CellValue? value) {
  if (value == null) return '';
  if (value is xl.TextCellValue) return value.value.toString().trim();
  if (value is xl.IntCellValue) return value.value.toString();
  if (value is xl.DoubleCellValue) return value.value.toString();
  if (value is xl.DateCellValue) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
  if (value is xl.DateTimeCellValue) {
    return value.asDateTimeLocal().toIso8601String();
  }
  if (value is xl.FormulaCellValue) return value.formula;
  return value.toString().trim();
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAllMapped(
      RegExp(r'[áéíóúñ]'),
      (match) => const {
        'á': 'a',
        'é': 'e',
        'í': 'i',
        'ó': 'o',
        'ú': 'u',
        'ñ': 'n',
      }[match.group(0)]!,
    )
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

DateTime? _parseExcelDate(String raw) {
  final clean = raw.trim().replaceAll('//', '/');
  if (clean.isEmpty) return null;
  final direct = DateTime.tryParse(clean);
  if (direct != null) return direct;
  const months = {
    'enero': 1,
    'febrero': 2,
    'marzo': 3,
    'abril': 4,
    'mayo': 5,
    'junio': 6,
    'julio': 7,
    'agosto': 8,
    'septiembre': 9,
    'setiembre': 9,
    'octubre': 10,
    'noviembre': 11,
    'diciembre': 12,
  };
  final match = RegExp(
    r'^(\d{1,2})[\s/\-]+([A-Za-zÁÉÍÓÚáéíóú]+|\d{1,2})[\s/\-]+(\d{4})$',
  ).firstMatch(clean);
  if (match == null) return null;
  final monthRaw = _normalize(match.group(2)!);
  final month = int.tryParse(monthRaw) ?? months[monthRaw];
  final day = int.tryParse(match.group(1)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

bool _yes(String value) => const {
  'si',
  'sí',
  's',
  '1',
  'true',
  'x',
}.contains(value.trim().toLowerCase());

int _int(String value, {int fallback = 0}) =>
    int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), '')) ?? fallback;

num? _num(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (clean.isEmpty) return null;
  return num.tryParse(clean.replaceAll(',', ''));
}

String _trafficLabel(PersonnelRequisitionTraffic traffic) => switch (traffic) {
  PersonnelRequisitionTraffic.green => 'En tiempo',
  PersonnelRequisitionTraffic.yellow => 'Próxima a vencer',
  PersonnelRequisitionTraffic.red => 'Atención prioritaria',
  PersonnelRequisitionTraffic.closed => 'Cerrada',
};

String _historyResult(String result) => switch (result) {
  'continua' => 'Continúa en proceso',
  'no_continua' => 'No continúa',
  'pendiente' => 'Pendiente de respuesta',
  'completado' => 'Actividad completada',
  'reprogramado' => 'Reprogramado',
  _ => result,
};

String _trafficColor(PersonnelRequisitionTraffic traffic) => switch (traffic) {
  PersonnelRequisitionTraffic.green => '#DCFCE7',
  PersonnelRequisitionTraffic.yellow => '#FEF3C7',
  PersonnelRequisitionTraffic.red => '#FEE2E2',
  PersonnelRequisitionTraffic.closed => '#E2E8F0',
};

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
