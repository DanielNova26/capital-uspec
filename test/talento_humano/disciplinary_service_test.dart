import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/festivos_colombia.dart';
import 'package:todo/talento_humano/disciplinary_service.dart';

void main() {
  DisciplinaryRecord record(
    String stage, {
    DateTime? hearingDate,
    DateTime? resultDeadline,
    String sanction = '',
    String severity = '',
  }) {
    return DisciplinaryRecord(
      id: '$stage-${hearingDate ?? resultDeadline}',
      empresaId: 'EMPRESA_001',
      cedula: '10101010',
      personName: 'Persona de prueba',
      stage: stage,
      receivedAt: DateTime(2026, 8, 4),
      hearingDate: hearingDate,
      resultDeadline: resultDeadline,
      sanction: sanction,
      severity: severity,
    );
  }

  test('normaliza etapas desconocidas como solicitud recibida', () {
    expect(
      DisciplinaryStage.normalize('estado_legacy'),
      DisciplinaryStage.solicitud,
    );
    expect(DisciplinaryStage.normalize(null), DisciplinaryStage.solicitud);
    expect(
      DisciplinaryStage.label(DisciplinaryStage.citacion),
      'Citado a descargos',
    );
  });

  test('solo las cuatro sanciones definidas cierran el proceso', () {
    expect(DisciplinarySanction.values, hasLength(4));
    for (final value in DisciplinarySanction.values) {
      expect(DisciplinarySanction.isValid(value), isTrue);
      expect(DisciplinarySanction.label(value), isNot('—'));
    }
    expect(DisciplinarySanction.isValid('llamado_verbal'), isFalse);
    expect(DisciplinarySanction.isValid(''), isFalse);
    expect(
      DisciplinarySanction.label(DisciplinarySanction.terminacion),
      'Terminación de contrato por justa causa',
    );
  });

  test('"no corresponde" no es una sanción del cierre por resultado', () {
    // Tiene etiqueta, pero no puede aparecer en el desplegable del paso 4:
    // ahí solo van las cuatro con las que se cierra tras la diligencia.
    expect(
      DisciplinarySanction.values,
      isNot(contains(DisciplinarySanction.noCorresponde)),
    );
    expect(
      DisciplinarySanction.isValid(DisciplinarySanction.noCorresponde),
      isFalse,
    );
    expect(
      DisciplinarySanction.label(DisciplinarySanction.noCorresponde),
      'No corresponde a proceso disciplinario',
    );
  });

  test('la gravedad es leve, grave o gravísima, y nada más', () {
    expect(DisciplinarySeverity.values, [
      DisciplinarySeverity.leve,
      DisciplinarySeverity.grave,
      DisciplinarySeverity.gravisima,
    ]);
    for (final value in DisciplinarySeverity.values) {
      expect(DisciplinarySeverity.isValid(value), isTrue);
      expect(DisciplinarySeverity.label(value), isNot('—'));
    }
    // La escala vieja (leve/media/alta) ya no vale.
    expect(DisciplinarySeverity.isValid('media'), isFalse);
    expect(DisciplinarySeverity.isValid('alta'), isFalse);
    expect(DisciplinarySeverity.isValid(''), isFalse);
  });

  test('un caso descartado no finge haber recorrido las etapas', () {
    final descartado = record(
      DisciplinaryStage.cerrado,
      sanction: DisciplinarySanction.noCorresponde,
    );
    expect(descartado.isClosed, isTrue);
    expect(descartado.closedWithoutProcess, isTrue);
    expect(descartado.statusLabel, 'Cerrado: no corresponde');
    // Sin diligencia no hay gravedad que calificar.
    expect(descartado.severity, isEmpty);

    final sancionado = record(
      DisciplinaryStage.cerrado,
      sanction: DisciplinarySanction.suspension,
      severity: DisciplinarySeverity.grave,
    );
    expect(sancionado.closedWithoutProcess, isFalse);
    expect(sancionado.statusLabel, 'Cerrado');
  });

  test('la diligencia se propone a 5 días hábiles de la citación', () {
    // Lunes 7 de septiembre de 2026: cinco hábiles caen el lunes siguiente.
    final citacion = DateTime(2026, 9, 7);
    expect(citacion.weekday, DateTime.monday);
    final diligencia = DisciplinaryService.fechaDiligenciaSugerida(citacion);

    expect(diligencia.weekday, DateTime.monday);
    expect(diligencia.difference(citacion).inDays, greaterThanOrEqualTo(5));
    expect(esNoHabil(diligencia), isFalse);
  });

  test('el plazo salta los festivos, no solo los fines de semana', () {
    // Viernes 1 de enero de 2027 es festivo, así que cinco hábiles desde el
    // 31 de diciembre no pueden caer antes del viernes 8.
    final diligencia = DisciplinaryService.fechaDiligenciaSugerida(
      DateTime(2026, 12, 31),
    );
    expect(esFestivo(DateTime(2027, 1, 1)), isTrue);
    expect(diligencia.month, 1);
    expect(diligencia.day, 8);
  });

  test('la fecha vigilada es la de la etapa en curso', () {
    final citado = record(
      DisciplinaryStage.citacion,
      hearingDate: DateTime(2026, 9, 20),
      resultDeadline: DateTime(2026, 10, 5),
    );
    expect(citado.currentDeadline, DateTime(2026, 9, 20));

    final enDiligencia = record(
      DisciplinaryStage.diligencia,
      hearingDate: DateTime(2026, 9, 20),
      resultDeadline: DateTime(2026, 10, 5),
    );
    expect(enDiligencia.currentDeadline, DateTime(2026, 10, 5));

    // Ni la solicitud ni el cierre tienen plazo que vigilar.
    expect(record(DisciplinaryStage.solicitud).currentDeadline, isNull);
    expect(
      record(
        DisciplinaryStage.cerrado,
        resultDeadline: DateTime(2026, 10, 5),
      ).currentDeadline,
      isNull,
    );
  });

  test('un plazo pasado marca el proceso como vencido', () {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final hoy = DateTime.now();
    final manana = DateTime.now().add(const Duration(days: 1));

    final vencido = record(DisciplinaryStage.citacion, hearingDate: ayer);
    expect(vencido.isOverdue, isTrue);
    expect(vencido.daysToDeadline, -1);

    final venceHoy = record(DisciplinaryStage.citacion, hearingDate: hoy);
    expect(venceHoy.isDueToday, isTrue);
    expect(venceHoy.isOverdue, isFalse);

    final aTiempo = record(DisciplinaryStage.citacion, hearingDate: manana);
    expect(aTiempo.isOverdue, isFalse);
    expect(aTiempo.daysToDeadline, 1);

    // Sin plazo no hay vencimiento: la solicitud no debe pintarse en rojo.
    expect(record(DisciplinaryStage.solicitud).isOverdue, isFalse);
  });

  test('calcula las métricas de la carpeta disciplinaria', () {
    final metrics = DisciplinaryMetrics.fromRecords([
      record(DisciplinaryStage.solicitud),
      record(
        DisciplinaryStage.citacion,
        hearingDate: DateTime.now().subtract(const Duration(days: 3)),
      ),
      record(
        DisciplinaryStage.diligencia,
        resultDeadline: DateTime.now().add(const Duration(days: 4)),
      ),
      record(
        DisciplinaryStage.cerrado,
        sanction: DisciplinarySanction.exonerado,
      ),
    ]);

    expect(metrics.total, 4);
    expect(metrics.inProgress, 3);
    expect(metrics.overdue, 1);
    expect(metrics.closed, 1);
  });

  test('solo los procesos sin resultado siguen abiertos', () {
    expect(record(DisciplinaryStage.solicitud).isOpen, isTrue);
    expect(record(DisciplinaryStage.citacion).isOpen, isTrue);
    expect(record(DisciplinaryStage.diligencia).isOpen, isTrue);
    expect(record(DisciplinaryStage.cerrado).isOpen, isFalse);
    expect(record(DisciplinaryStage.cerrado).isClosed, isTrue);
  });
}
