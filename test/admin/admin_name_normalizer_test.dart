import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_name_normalizer.dart';

void main() {
  test('normaliza mayúsculas y partículas de un nombre', () {
    expect(
      normalizePersonName('  MARÍA   DE LA CRUZ PÉREZ  '),
      'María de la Cruz Pérez',
    );
  });

  test('conserva apellidos compuestos con guion y apóstrofo', () {
    expect(normalizePersonName("ANA-MARÍA O'CONNOR"), "Ana-María O'Connor");
  });

  test('elimina espacios de un valor ya normalizado', () {
    expect(normalizePersonName('Juan   Carlos'), 'Juan Carlos');
  });

  test('normaliza un nombre completo sin separar nombres y apellidos', () {
    expect(normalizePersonName('LUIS DEL RÍO'), 'Luis del Río');
  });
}
