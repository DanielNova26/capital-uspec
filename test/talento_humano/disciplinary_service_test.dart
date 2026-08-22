import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/disciplinary_service.dart';

void main() {
  DisciplinaryRecord record(String status, {String severity = 'leve'}) {
    return DisciplinaryRecord(
      id: '$status-$severity',
      empresaId: 'EMPRESA_001',
      cedula: '10101010',
      personName: 'Persona de prueba',
      subject: 'Prueba',
      description: 'Descripción',
      type: 'escrito',
      severity: severity,
      status: status,
      incidentDate: DateTime(2026, 8, 4),
    );
  }

  test('normaliza estados desconocidos como pendientes de respuesta', () {
    expect(
      DisciplinaryStatus.normalize('estado_legacy'),
      DisciplinaryStatus.pendingResponse,
    );
    expect(
      DisciplinaryStatus.label(DisciplinaryStatus.followUp),
      'En seguimiento',
    );
  });

  test('calcula las métricas de la carpeta disciplinaria', () {
    final metrics = DisciplinaryMetrics.fromRecords([
      record(DisciplinaryStatus.pendingResponse, severity: 'alta'),
      record(DisciplinaryStatus.followUp),
      record(DisciplinaryStatus.inReview),
      record(DisciplinaryStatus.closed),
    ]);

    expect(metrics.total, 4);
    expect(metrics.pendingResponse, 1);
    expect(metrics.followUp, 2);
    expect(metrics.closed, 1);
    expect(metrics.highSeverity, 1);
  });

  test('solo los procesos sin cierre se consideran activos', () {
    expect(record(DisciplinaryStatus.pendingResponse).isOpen, isTrue);
    expect(record(DisciplinaryStatus.inReview).isOpen, isTrue);
    expect(record(DisciplinaryStatus.followUp).isOpen, isTrue);
    expect(record(DisciplinaryStatus.closed).isOpen, isFalse);
  });
}
