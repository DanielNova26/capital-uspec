import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/birthday_logic.dart';

void main() {
  test('lee fechas civiles sin mover el día por la zona horaria', () {
    expect(parseFechaNacimiento('31/12/1990'), DateTime(1990, 12, 31));
    expect(
      parseFechaNacimiento('1990-12-31T00:00:00.000Z'),
      DateTime(1990, 12, 31),
    );
    expect(
      parseFechaNacimiento('1990-12-31T23:30:00-05:00'),
      DateTime(1990, 12, 31),
    );
    expect(
      parseFechaNacimiento(Timestamp.fromDate(DateTime.utc(1990, 12, 31))),
      DateTime(1990, 12, 31),
    );
  });

  test('rechaza fechas civiles inválidas', () {
    expect(parseFechaNacimiento('31/02/1990'), isNull);
    expect(parseFechaNacimiento('sin fecha'), isNull);
  });

  test('hoy y mañana no se corren por las horas del reloj', () {
    final birth = DateTime(1990, 9, 3);
    final today = DateTime(2026, 9, 2, 23, 59);

    expect(diasParaCumpleanos(birth, desde: today), 1);
    expect(diasParaCumpleanos(birth, desde: DateTime(2026, 9, 3, 8)), 0);
  });

  test('calcula la edad que cumple incluso el día del cumpleaños', () {
    final birth = DateTime(1990, 9, 2);
    final today = DateTime(2026, 9, 2, 18);

    expect(edadEnFecha(birth, fecha: today), 36);
    expect(edadAlProximoCumpleanos(birth, desde: today), 36);
    expect(edadAlProximoCumpleanos(birth, desde: DateTime(2026, 9, 3)), 37);
  });
}
