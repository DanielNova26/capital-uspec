import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/company_transition_service.dart';

void main() {
  group('idRolEnEmpresa', () {
    test('usa {empresa}_{usuario}, donde las reglas buscan el rol', () {
      expect(
        idRolEnEmpresa(
          targetEmpresaId: 'EMP_B',
          sourceEmpresaId: 'EMP_A',
          docId: 'EMP_A_123',
          data: {'userId': '123', 'rol': 'admin'},
        ),
        'EMP_B_123',
      );
    });

    test('Correo guarda la persona en usuarioId', () {
      expect(
        idRolEnEmpresa(
          targetEmpresaId: 'EMP_B',
          sourceEmpresaId: 'EMP_A',
          docId: 'EMP_A_456',
          data: {'usuarioId': '456'},
        ),
        'EMP_B_456',
      );
    });

    test('sin usuario escrito, lo saca del id viejo sin la empresa', () {
      expect(
        idRolEnEmpresa(
          targetEmpresaId: 'EMP_B',
          sourceEmpresaId: 'EMP_A',
          docId: 'EMP_A_789',
          data: const {},
        ),
        'EMP_B_789',
      );
      expect(
        idRolEnEmpresa(
          targetEmpresaId: 'EMP_B',
          sourceEmpresaId: 'EMP_A',
          docId: 'suelto',
          data: const {},
        ),
        'EMP_B_suelto',
      );
    });
  });
}
