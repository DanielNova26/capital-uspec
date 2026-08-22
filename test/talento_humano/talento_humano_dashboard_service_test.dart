import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/resume_management_report.dart';
import 'package:todo/talento_humano/talento_humano_dashboard_service.dart';

void main() {
  group('TalentoHumanoDashboardData', () {
    test('consolida personal, hojas de vida y cobertura organizacional', () {
      final data = TalentoHumanoDashboardData.fromMaps(
        people: const [
          {
            'estado': 'activo',
            'estadoHojaDeVida': 'aprobado',
            'centroCostos': 'Administración',
            'area': 'Tesorería',
          },
          {
            'estado': 'inactivo',
            'estadoHojaDeVida': 'requiere_cambios',
            'centroCostos': '',
            'area': '',
          },
          {
            'estado': 'activo',
            'estadoHojaDeVida': 'en_revision',
            'centroCostos': '',
            'area': 'Talento Humano',
          },
        ],
        costCenters: const [
          {'enabled': true},
          {'enabled': false},
        ],
        areas: const [
          {'enabled': true},
          {'enabled': true},
        ],
        disciplinaryRecords: const [],
      );

      expect(data.totalPeople, 3);
      expect(data.activePeople, 2);
      expect(data.inactivePeople, 1);
      expect(data.approvedResumes, 1);
      expect(data.pendingResumes, 1);
      expect(data.peopleWithoutCostCenter, 1);
      expect(data.peopleWithoutArea, 0);
      expect(data.activeCostCenters, 1);
      expect(data.activeAreas, 2);
      expect(data.costCenterDistribution.first.label, 'Administración');
      expect(data.costCenterDistribution.first.value, 1);
      expect(data.pendingResumePeople, hasLength(1));
      expect(data.pendingResumePeople.single.status, 'en_revision');
    });

    test('solo cuenta como abiertos los procesos disciplinarios vigentes', () {
      final data = TalentoHumanoDashboardData.fromMaps(
        people: const [],
        costCenters: const [],
        areas: const [],
        disciplinaryRecords: const [
          {'estado': 'pendiente_respuesta', 'gravedad': 'alta'},
          {'estado': 'en_seguimiento', 'gravedad': 'media'},
          {'estado': 'cerrado', 'gravedad': 'alta'},
          {'estado': 'anulado', 'gravedad': 'alta'},
        ],
      );

      expect(data.openDisciplinaryCases, 2);
      expect(data.highSeverityCases, 1);
    });

    test('evita divisiones inválidas cuando no hay personal', () {
      final data = TalentoHumanoDashboardData.fromMaps(
        people: const [],
        costCenters: const [],
        areas: const [],
        disciplinaryRecords: const [],
      );

      expect(data.resumeCompletion, 0);
      expect(data.costCenterCoverage, 0);
    });
  });

  group('Informe de gestión de hojas de vida', () {
    test('incluye contacto, corrección y resumen de los pendientes', () {
      final bytes = buildResumeManagementReport(
        empresaId: 'EMPRESA_001',
        empresaNombre: 'Capital USPEC',
        generatedAt: DateTime(2026, 8, 20),
        rows: [
          ResumeManagementRow(
            document: '123456',
            fullName: 'Ana Pérez',
            status: 'requiere_cambios',
            action: 'Solicitar correcciones',
            correctionNote: 'Adjuntar certificado laboral',
            phone: '3001234567',
            email: 'ana@example.com',
            position: 'Auxiliar administrativa',
            area: 'Talento Humano',
            costCenter: 'Administración',
            requestedAt: DateTime(2026, 8, 18),
          ),
        ],
      );

      final workbook = xl.Excel.decodeBytes(bytes);
      final pending = workbook['Pendientes HV'];
      final summary = workbook['Resumen'];

      expect(pending.rows[0][0]?.value.toString(), contains('GESTIÓN'));
      expect(pending.rows[4][0]?.value.toString(), contains('Correcciones'));
      expect(pending.rows[4][3]?.value.toString(), 'Ana Pérez');
      expect(
        pending.rows[4][9]?.value.toString(),
        'Adjuntar certificado laboral',
      );
      expect(summary.rows[3][0]?.value.toString(), 'Sin enviar');
      expect(summary.rows[5][1]?.value.toString(), '1');
    });
  });
}
