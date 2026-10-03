import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/task_status.dart';

void main() {
  final hoy = DateTime.now();
  DateTime dia(int delta) =>
      DateTime(hoy.year, hoy.month, hoy.day + delta, 15, 30);

  test('días de calendario hasta la fecha límite', () {
    expect(taskDaysLeft(dia(0)), 0);
    expect(taskDaysLeft(dia(1)), 1);
    expect(taskDaysLeft(dia(-1)), -1);
    expect(taskDaysLeft(dia(-10)), -10);
    expect(taskDaysLeft(null), isNull);
  });

  test('la tarea que venció ayer ya está retrasada', () {
    expect(
      resolveTaskStatus({'estado': 'en_progreso', 'fecha_limite': dia(-1)}),
      'retrasada',
    );
    expect(
      resolveTaskStatus({'estado': 'en_progreso', 'fecha_limite': dia(0)}),
      'en_progreso',
    );
  });
}
