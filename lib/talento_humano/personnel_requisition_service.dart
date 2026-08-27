import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;

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

  const PersonnelRequisitionCatalogs({
    required this.costCenters,
    required this.groups,
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
          rows.sort((a, b) => b.requestDate.compareTo(a.requestDate));
          return rows;
        });
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
    return PersonnelRequisitionCatalogs(
      costCenters: costCenters,
      groups: groups,
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
        'nombres': hire.names.trim(),
        'apellidos': hire.surnames.trim(),
        'nombreCompleto': hire.fullName,
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
        names: hire.names.trim(),
        surnames: hire.surnames.trim(),
        email: hire.email.trim(),
        phone: hire.phone.trim(),
        hiredAt: DateTime.now(),
        createdBy: userId,
      );
      final nextHires = [...current.hires, hired];
      final complete = nextHires.length >= current.quantity;
      transaction.update(reqRef, {
        'contratados': nextHires
            .map((item) => item.toMap(hiredAtValue: Timestamp.now()))
            .toList(),
        'cantidadContratada': nextHires.length,
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

Uint8List buildPersonnelRequisitionReport({
  required List<PersonnelRequisition> rows,
  required String empresaId,
  String empresaNombre = '',
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();
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
    'Registros: ${rows.length} · Generado: ${_dateLabel(now)} · '
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

  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
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
        numberFormat: values[column] is xl.DateTimeCellValue
            ? const xl.CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy')
            : xl.NumFormat.standard_0,
        bold: column == 0,
      );
    }
  }

  const widths = <double>[
    14,
    13,
    17,
    10,
    23,
    10,
    31,
    11,
    12,
    11,
    17,
    22,
    34,
    48,
    34,
    34,
    24,
    17,
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
