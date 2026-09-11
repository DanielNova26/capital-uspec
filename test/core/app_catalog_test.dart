import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/app_catalog.dart';

void main() {
  test('Correo, Correspondencia y Biblioteca son módulos independientes', () {
    final byId = {for (final app in kAppCatalog) app.appId: app};

    expect(byId['correodashboard']?.nombre, 'Correo');
    expect(
      byId['gestiondocumentaldashboard']?.nombre,
      'Gestión de Correspondencia',
    );
    expect(
      byId['bibliotecadocumentaldashboard']?.nombre,
      'Biblioteca Documental',
    );
    expect(byId.length, kAppCatalog.length);
  });
}
