import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_contract.dart';

void main() {
  group('TaskContract', () {
    test('normaliza campos comunes y conserva trazabilidad modular', () {
      final data = TaskContract.normalizeForCreate({
        'titulo': 'Corregir hallazgo',
        'empresaId': 'EMPRESA_001',
        'asignado_uid': 'director-1',
        'creador_id': 'interventor-1',
        'jefe_uid': 'aprobador-1',
        'estado': 'pendiente_aprobacion',
        'prioridad': 'ALTA',
        'origen': 'interventoria',
        'hallazgoId': 'H-99',
        'sourceEntityCollection': 'TBL_INTERVENTORIA_HALLAZGOS',
      });

      expect(data['schemaVersion'], 2);
      expect(data['estado'], 'por_aprobar');
      expect(data['status'], 'por_aprobar');
      expect(data['prioridad'], 'alta');
      expect(data['sourceModule'], 'interventoria');
      expect(data['aprobador_uid'], 'aprobador-1');
      expect(data['empresas'], contains('EMPRESA_001'));
      expect(data['source'], {
        'moduleId': 'interventoria',
        'type': 'interventoria',
        'entityId': 'H-99',
        'entityCollection': 'TBL_INTERVENTORIA_HALLAZGOS',
      });
    });

    test('normaliza aliases de módulos', () {
      final data = TaskContract.normalizeForCreate({
        'titulo': 'Documento requerido',
        'empresaId': 'EMPRESA_001',
        'asignado_uid': 'u-1',
        'creador_id': 'u-2',
        'destinoModulo': 'facturaciondashboard',
        'origen': 'facturacion_observacion',
      });

      expect(data['sourceModule'], 'facturacion');
      expect(data['sourceType'], 'facturacion_observacion');
      expect(data['aprobador_uid'], 'u-2');
    });

    test('rechaza tareas sin empresa, responsable o creador', () {
      expect(
        () => TaskContract.normalizeForCreate({
          'titulo': 'Sin empresa',
          'asignado_uid': 'u-1',
          'creador_id': 'u-2',
        }),
        throwsStateError,
      );
      expect(
        () => TaskContract.normalizeForCreate({
          'titulo': 'Sin responsable',
          'empresaId': 'EMPRESA_001',
          'creador_id': 'u-2',
        }),
        throwsStateError,
      );
    });

    test('un extra no puede degradar estados ni prioridades', () {
      final data = TaskContract.normalizeForCreate({
        'titulo': 'Validar contrato',
        'empresaId': 'EMPRESA_001',
        'asignado_uid': 'u-1',
        'creador_id': 'u-2',
        'estado': 'estado_inventado',
        'prioridad': 'imposible',
      });

      expect(data['estado'], 'en_progreso');
      expect(data['prioridad'], 'media');
    });
  });
}
