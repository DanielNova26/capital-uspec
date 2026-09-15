import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/user_directory.dart';

void main() {
  group('UserDirectory arma el nombre desde TBL_USUARIOS', () {
    final dir = UserDirectory.instance;

    test('nombre partido en primerNombre/primerApellido', () {
      final info = dir.fromUsuario('1073241667', {
        'primerNombre': 'Yolamaider',
        'segundoNombre': 'Andrea',
        'primerApellido': 'Rojas',
        'segundoApellido': 'Díaz',
      });
      expect(info.displayName, 'Yolamaider Andrea Rojas Díaz');
    });

    test('un campo vacío no tapa al siguiente', () {
      final info = dir.fromUsuario('1', {
        'nombres': '',
        'primerNombre': 'Ana',
        'apellidos': '',
        'primerApellido': 'Pérez',
      });
      expect(info.displayName, 'Ana Pérez');
    });

    test('nombres/apellidos completos mandan sobre las partes', () {
      final info = dir.fromUsuario('2', {
        'nombres': 'Luis Felipe',
        'apellidos': 'Gómez Ruiz',
        'segundoNombre': 'NO',
      });
      expect(info.displayName, 'Luis Felipe Gómez Ruiz');
    });

    test('sin nombre queda la cédula (último recurso)', () {
      expect(dir.fromUsuario('3', {'nombre': ''}).displayName, '3');
      expect(dir.fromUsuario('4', {'name': 'Solo name'}).displayName, 'Solo name');
    });
  });
}
