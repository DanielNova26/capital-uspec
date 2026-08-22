import 'dart:typed_data';

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
      expect(sheet.rows[4][6]?.value.toString(), contains('Nutricionista'));
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
