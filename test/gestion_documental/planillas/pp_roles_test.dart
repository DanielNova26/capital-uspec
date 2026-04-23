import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_models.dart';

void main() {
  group('PpRoles eliminar_logo', () {
    test('solo administrador documental puede eliminar logos', () {
      expect(PpRoles.puedeEjecutar('eliminar_logo', PpRoles.adminDoc), isTrue);
      expect(
        PpRoles.puedeEjecutar('eliminar_logo', PpRoles.tesoreria),
        isFalse,
      );
      expect(
        PpRoles.puedeEjecutar('eliminar_logo', PpRoles.auditoria),
        isFalse,
      );
      expect(PpRoles.puedeEjecutar('eliminar_logo', PpRoles.gerencia), isFalse);
      expect(
        PpRoles.puedeEjecutar('eliminar_logo', PpRoles.desarrollador),
        isFalse,
      );
    });
  });

  group('PpRoles editar_nombre_planilla', () {
    test('tesoreria puede editar el nombre de una planilla cargada', () {
      expect(
        PpRoles.puedeEjecutar('editar_nombre_planilla', PpRoles.tesoreria),
        isTrue,
      );
      expect(
        PpRoles.puedeEjecutar('editar_nombre_planilla', PpRoles.auditoria),
        isFalse,
      );
      expect(
        PpRoles.puedeEjecutar('editar_nombre_planilla', PpRoles.gerencia),
        isFalse,
      );
    });
  });
}
