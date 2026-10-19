import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_recurrencia.dart';

void main() {
  test('diaria: siempre es el día siguiente', () {
    const r = TaskRecurrencia(frecuencia: TaskFrecuencia.diaria);
    expect(r.siguienteDespuesDe(DateTime(2026, 10, 5)), DateTime(2026, 10, 6));
    expect(r.descripcion, 'Todos los días');
  });

  test('semanal: cada lunes y jueves', () {
    const r = TaskRecurrencia(
      frecuencia: TaskFrecuencia.semanal,
      diasSemana: {DateTime.monday, DateTime.thursday},
    );
    // 5 oct 2026 es lunes.
    expect(r.siguienteDespuesDe(DateTime(2026, 10, 5)), DateTime(2026, 10, 8));
    expect(r.siguienteDespuesDe(DateTime(2026, 10, 8)), DateTime(2026, 10, 12));
    expect(r.descripcion, 'Cada lunes y jueves');
  });

  test('semanal sin día elegido está incompleta y no programa nada', () {
    const r = TaskRecurrencia(frecuencia: TaskFrecuencia.semanal);
    expect(r.incompleta, isTrue);
    expect(r.siguienteDespuesDe(DateTime(2026, 10, 5)), isNull);
  });

  test('mensual: el día 31 cae el último día de los meses cortos', () {
    const r = TaskRecurrencia(frecuencia: TaskFrecuencia.mensual, diaMes: 31);
    expect(
      r.siguienteDespuesDe(DateTime(2026, 10, 31)),
      DateTime(2026, 11, 30),
    );
    expect(r.siguienteDespuesDe(DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
    expect(r.descripcion, 'El día 31 de cada mes');
  });

  test('ninguna no se repite', () {
    expect(TaskRecurrencia.ninguna.repite, isFalse);
    expect(TaskRecurrencia.ninguna.siguienteDespuesDe(DateTime(2026)), isNull);
  });

  test('se guarda y se lee igual', () {
    const r = TaskRecurrencia(
      frecuencia: TaskFrecuencia.semanal,
      diasSemana: {3, 1},
    );
    final leida = TaskRecurrencia.fromMap(r.toMap());
    expect(leida.frecuencia, TaskFrecuencia.semanal);
    expect(leida.diasSemana, {1, 3});
    expect(TaskRecurrencia.fromMap({'frecuencia': 'raro'}).repite, isFalse);
  });
}
