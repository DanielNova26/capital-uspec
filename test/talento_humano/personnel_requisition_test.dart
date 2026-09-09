import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/personnel_requisition_models.dart';
import 'package:todo/talento_humano/personnel_requisition_service.dart';

void main() {
  group('acceso del usuario contratado', () {
    test('asigna la contraseña temporal al crear el usuario', () {
      expect(personnelAccessCredentials(const <String, dynamic>{}), const {
        'password': personnelTemporaryPassword,
        'needsPasswordChange': true,
      });
    });

    test('conserva la contraseña de un usuario existente', () {
      expect(
        personnelAccessCredentials(const {
          'password': 'ClaveActual2026',
          'needsPasswordChange': false,
        }),
        const {'password': 'ClaveActual2026', 'needsPasswordChange': false},
      );
    });
  });

  group('semaforo de requerimientos', () {
    test('cuenta dias habiles de Colombia y excluye festivos', () {
      expect(
        businessDaysElapsed(DateTime(2026, 8, 3), DateTime(2026, 8, 20)),
        11,
      );
    });

    test('cambia a amarillo en 8 y a rojo en 15', () {
      expect(
        requisitionTraffic(businessDays: 7, closed: false),
        PersonnelRequisitionTraffic.green,
      );
      expect(
        requisitionTraffic(businessDays: 8, closed: false),
        PersonnelRequisitionTraffic.yellow,
      );
      expect(
        requisitionTraffic(businessDays: 15, closed: false),
        PersonnelRequisitionTraffic.red,
      );
      expect(
        requisitionTraffic(businessDays: 20, closed: true),
        PersonnelRequisitionTraffic.closed,
      );
    });

    test('normaliza los procesos libres del Excel', () {
      expect(
        PersonnelRequisitionStageX.parse('EXAMENES 20/agosto/2026'),
        PersonnelRequisitionStage.exams,
      );
      expect(
        PersonnelRequisitionStageX.parse('EN ESTUDIO Y EXAMENES'),
        PersonnelRequisitionStage.exams,
      );
      expect(
        PersonnelRequisitionStageX.parse('RECLUTAMIENTO'),
        PersonnelRequisitionStage.recruitment,
      );
    });

    test('conserva y ordena el historial de avances y observaciones', () {
      final row = PersonnelRequisition.fromMap('REQ-1', {
        'empresaId': 'EMPRESA_001',
        'establecimiento': 'Picota',
        'cargo': 'Nutricionista',
        'cantidad': 1,
        'fechaSolicitud': DateTime(2026, 8, 1),
        'historial': [
          {
            'etapa': 'reclutamiento',
            'tipoAvance': 'Contacto inicial',
            'resultado': 'continua',
            'nota': 'Aceptó participar',
            'fecha': DateTime(2026, 8, 10),
          },
          {
            'etapa': 'entrevista',
            'tipoAvance': 'Entrevista realizada',
            'resultado': 'no_continua',
            'nota': 'No cumple la experiencia requerida',
            'fecha': DateTime(2026, 8, 12),
          },
        ],
      });

      expect(row.history, hasLength(2));
      expect(row.history.first.advanceType, 'Entrevista realizada');
      expect(row.history.first.result, 'no_continua');
      expect(row.history.first.note, 'No cumple la experiencia requerida');
    });
  });

  group('identidad del aspirante sin cédula', () {
    PersonnelCandidate aspirante({
      String candidateId = '',
      String document = '',
      String names = 'Juan',
      String surnames = 'Pérez',
    }) => PersonnelCandidate(
      candidateId: candidateId,
      document: document,
      names: names,
      surnames: surnames,
    );

    test('la llave es el id propio, no la cédula', () {
      final conId = aspirante(candidateId: 'abc123', document: '1010');
      expect(conId.key, 'abc123');
      expect(conId.matches('abc123'), isTrue);
      // La cédula deja de servir como llave en cuanto hay id propio: si
      // respondiera a las dos, un registro viejo podría chocar con uno nuevo.
      expect(conId.matches('1010'), isFalse);
    });

    test('los registros viejos siguen respondiendo por su documento', () {
      final legacy = aspirante(document: '1010');
      expect(legacy.key, '1010');
      expect(legacy.matches('1010'), isTrue);
    });

    test('sin id ni documento no responde a nada', () {
      final huerfano = aspirante();
      expect(huerfano.key, isEmpty);
      expect(huerfano.matches(''), isFalse);
      expect(huerfano.matches('1010'), isFalse);
    });

    test('dos aspirantes sin cédula son personas distintas', () {
      final ana = aspirante(candidateId: 'id-1', names: 'Ana');
      final luis = aspirante(candidateId: 'id-2', names: 'Luis');
      // Antes ambos tenían documento vacío y se pisaban entre sí: mover a uno
      // de etapa movía al otro.
      expect(ana.matches(luis.key), isFalse);
      expect(luis.matches(ana.key), isFalse);
    });

    test('el documento vacío se muestra, no se deja colgando', () {
      expect(aspirante().documentLabel, 'Sin cédula registrada');
      expect(aspirante(document: '1010').documentLabel, 'CC 1010');
    });

    test('copyWith puede llenar la cédula que faltaba', () {
      final registrado = aspirante(candidateId: 'id-1');
      final contratado = registrado.copyWith(
        document: '1020304050',
        stage: PersonnelCandidateStage.hired,
      );
      expect(contratado.document, '1020304050');
      expect(contratado.candidateId, 'id-1');
      expect(contratado.stage, PersonnelCandidateStage.hired);
    });

    test('el mapa guarda la llave para que sobreviva a la recarga', () {
      final ida = aspirante(candidateId: 'id-1', document: '1010');
      final vuelta = PersonnelCandidate.fromMap(ida.toMap());
      expect(vuelta.candidateId, 'id-1');
      expect(vuelta.key, 'id-1');

      // Un registro viejo no tiene candidatoId: al releerlo debe quedar con su
      // documento como llave, no con la llave vacía.
      final antiguo = PersonnelCandidate.fromMap(const {
        'documento': '2020',
        'nombres': 'Ana',
      });
      expect(antiguo.candidateId, isEmpty);
      expect(antiguo.key, '2020');
    });
  });

  group('borrar novedades del historial', () {
    Map<String, dynamic> crudo({
      String? id,
      required String nota,
      String usuario = '1010',
      required DateTime fecha,
    }) => {
      if (id != null) 'id': id,
      'etapa': 'reclutamiento',
      'nota': nota,
      'usuario': usuario,
      'fecha': Timestamp.fromDate(fecha),
    };

    test('la novedad nueva responde por su id', () {
      final entrada = PersonnelRequisitionHistoryEntry.fromMap(
        crudo(id: 'nov-1', nota: 'Avance', fecha: DateTime(2026, 9, 8)),
      );
      expect(entrada.key, 'nov-1');
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(
          crudo(id: 'nov-1', nota: 'Avance', fecha: DateTime(2026, 9, 8)),
          'nov-1',
        ),
        isTrue,
      );
    });

    test('las novedades viejas responden por su huella', () {
      // Las que ya estaban guardadas no tienen id: se reconocen por fecha,
      // autor y texto, que juntos no se repiten.
      final fecha = DateTime(2026, 9, 8, 10, 30);
      final vieja = PersonnelRequisitionHistoryEntry.fromMap(
        crudo(nota: 'Solicitud creada', fecha: fecha),
      );
      expect(vieja.key, isNot(isEmpty));
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(
          crudo(nota: 'Solicitud creada', fecha: fecha),
          vieja.key,
        ),
        isTrue,
      );
      // Otra novedad del mismo autor, mismo texto, distinto instante: no es
      // la misma y no puede borrarse por error.
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(
          crudo(nota: 'Solicitud creada', fecha: fecha.add(
            const Duration(seconds: 1),
          )),
          vieja.key,
        ),
        isFalse,
      );
    });

    test('el id manda sobre la huella', () {
      // Si la novedad tiene id, una huella que coincida no debe alcanzar:
      // así una novedad vieja no puede hacerse pasar por una nueva.
      final fecha = DateTime(2026, 9, 8, 10, 30);
      final conId = crudo(id: 'nov-9', nota: 'Avance', fecha: fecha);
      final huella = PersonnelRequisitionHistoryEntry.huella(
        fecha: fecha,
        usuario: '1010',
        nota: 'Avance',
      );
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(conId, huella),
        isFalse,
      );
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(conId, 'nov-9'),
        isTrue,
      );
    });

    test('una llave vacía no borra nada', () {
      // Sin esto, una novedad sin fecha ni autor podría arrastrar a otra.
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(
          crudo(nota: 'Avance', fecha: DateTime(2026, 9, 8)),
          '',
        ),
        isFalse,
      );
      expect(
        PersonnelRequisitionHistoryEntry.mapMatches(
          crudo(id: 'nov-1', nota: 'Avance', fecha: DateTime(2026, 9, 8)),
          '   ',
        ),
        isFalse,
      );
    });

    test('se borra la novedad pedida aunque llegue otra en el intervalo', () {
      // Este es el caso que obliga a filtrar por llave y no por posición: si
      // alguien registra un avance entre leer y escribir, el índice 1 ya no
      // apunta a lo mismo que el usuario vio.
      final historial = [
        crudo(id: 'a', nota: 'Solicitud creada', fecha: DateTime(2026, 9, 1)),
        crudo(id: 'nueva', nota: 'Avance de otro', fecha: DateTime(2026, 9, 7)),
        crudo(id: 'b', nota: 'Avance equivocado', fecha: DateTime(2026, 9, 8)),
      ];
      final restantes = historial
          .where((item) =>
              !PersonnelRequisitionHistoryEntry.mapMatches(item, 'b'))
          .toList();

      expect(restantes, hasLength(2));
      expect(restantes.map((e) => e['id']), ['a', 'nueva']);
    });

    test('borrar conserva los campos que el modelo no conoce', () {
      // El arreglo se reescribe completo, así que si el filtro trabajara sobre
      // objetos tipados se perderían campos guardados por otras versiones.
      final historial = [
        {...crudo(id: 'a', nota: 'Creada', fecha: DateTime(2026, 9, 1)),
          'campoFuturo': 'no se puede perder'},
        crudo(id: 'b', nota: 'Equivocado', fecha: DateTime(2026, 9, 8)),
      ];
      final restantes = historial
          .where((item) =>
              !PersonnelRequisitionHistoryEntry.mapMatches(item, 'b'))
          .toList();

      expect(restantes, hasLength(1));
      expect(restantes.single['campoFuturo'], 'no se puede perder');
    });
  });

  group('permisos por empresa', () {
    test('el visor solo puede consultar y exportar', () {
      final access = PersonnelRequisitionAccess.fromUserData({
        'empresasDetalle': {
          'EMPRESA_001': {'rolTalentoHumano': 'consulta'},
        },
      }, 'EMPRESA_001');

      expect(access.canCreate, isFalse);
      expect(access.canUpdateStage, isFalse);
      expect(access.canRegisterHire, isFalse);
      expect(access.canDelete, isFalse);
      expect(access.canExport, isTrue);
    });

    test('el reclutador actualiza procesos y registra contrataciones', () {
      final access = PersonnelRequisitionAccess.fromUserData({
        'empresasDetalle': {
          'EMPRESA_002': {'rolTalentoHumano': 'reclutador'},
        },
      }, 'EMPRESA_002');

      expect(access.canUpdateStage, isTrue);
      expect(access.canRegisterHire, isTrue);
      expect(access.canCancel, isFalse);
      expect(access.canDelete, isFalse);
    });

    test('solo el gestor puede eliminar requerimientos', () {
      final access = PersonnelRequisitionAccess.fromUserData({
        'empresasDetalle': {
          'EMPRESA_003': {'rolTalentoHumano': 'gestor'},
        },
      }, 'EMPRESA_003');

      expect(access.canDelete, isTrue);
    });
  });

  group('Excel de requerimientos', () {
    test('separa bloques de empresa e interpreta fecha y campos', () {
      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Hoja1');
      final sheet = excel['Hoja1'];
      _write(sheet, 0, const ['SOLICITUD DE PERSONAL CAPITAL USPEC 2025']);
      _write(sheet, 1, const [
        'GRUPO',
        'ESTABLECIMIENTO',
        'CARGO',
        'ANEXO',
        'CANTIDAD',
        'SALARIO',
        'COMENTARIOS',
        'FECHA DE SOLICITUD',
        'OBSERVACIONES',
      ]);
      _write(sheet, 2, const [
        '6',
        'PICOTA',
        'NUTRICIONISTA',
        'SI',
        '1',
        '3051000',
        'RECLUTAMIENTO',
        '03/agosto/2026',
        '',
      ]);
      _write(sheet, 4, const ['SOLICITUD DE PERSONAL FYC']);
      _write(sheet, 5, const [
        'GRUPO',
        'ESTABLECIMIENTO',
        'CARGO',
        'ANEXO',
        'CANTIDAD',
        'SALARIO',
        'COMENTARIOS',
        'FECHA DE SOLICITUD',
        'OBSERVACIONES',
      ]);
      _write(sheet, 6, const [
        '',
        'FYC',
        'INGENIERO',
        'SI',
        '1',
        '2680000',
        '',
        '19/agosto//2026',
        '',
      ]);

      final sections = parsePersonnelRequisitionWorkbook(
        Uint8List.fromList(excel.encode()!),
      );

      expect(sections, hasLength(2));
      expect(sections.first.rows.single.establishment, 'PICOTA');
      expect(
        sections.first.rows.single.stage,
        PersonnelRequisitionStage.recruitment,
      );
      expect(sections.last.rows.single.requestDate, DateTime(2026, 8, 19));
    });

    test('genera un informe Excel legible con nivel de atención y avance', () {
      final bytes = buildPersonnelRequisitionReport(
        empresaId: 'EMPRESA_001',
        empresaNombre: 'Capital USPEC',
        generatedAt: DateTime(2026, 8, 20),
        rows: [
          PersonnelRequisition(
            id: 'REQ-1',
            empresaId: 'EMPRESA_001',
            establishment: 'Picota',
            position: 'Nutricionista',
            quantity: 1,
            requestDate: DateTime(2026, 8, 3),
            stage: PersonnelRequisitionStage.recruitment,
          ),
        ],
      );
      final decoded = xl.Excel.decodeBytes(bytes);
      final sheet = decoded['Requerimientos'];

      expect(sheet.rows[0][0]?.value.toString(), contains('INFORME'));
      expect(sheet.rows[4][0]?.value.toString(), contains('Próxima a vencer'));
      // El cargo va en la tercera columna, antes de la fecha: se pidió en la
      // reunión del 8 sep 2026 porque es por lo que se busca en el informe.
      expect(sheet.rows[3][2]?.value.toString(), contains('Cargo'));
      expect(sheet.rows[4][2]?.value.toString(), contains('Nutricionista'));
    });
  });
}

void _write(xl.Sheet sheet, int rowIndex, List<String> values) {
  for (var column = 0; column < values.length; column++) {
    sheet
        .cell(
          xl.CellIndex.indexByColumnRow(
            columnIndex: column,
            rowIndex: rowIndex,
          ),
        )
        .value = xl.TextCellValue(
      values[column],
    );
  }
}
