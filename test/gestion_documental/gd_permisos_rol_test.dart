import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_permisos.dart';
import 'package:todo/utils/user_company.dart';

/// El administrador del módulo leía "no tienes permiso para clasificar".
/// `gd_permisos` resolvía el rol de otra forma que el resto de la aplicación:
/// buscaba una bandera `desarrollador: true` y leía el rol de la raíz, cuando
/// en una app multiempresa vive en `empresasDetalle[empresa]`.
void main() {
  group('el desarrollador se reconoce como en el resto de la app', () {
    test('por el rol dentro de la empresa, no por una bandera', () {
      final data = {
        'empresas': ['CAPITAL'],
        'empresasDetalle': {
          'CAPITAL': {'roleKey': 'desarrollador'},
        },
      };

      expect(isDeveloperUser(data, empresaId: 'CAPITAL'), isTrue);
    });

    test('por un roleId terminado en _desarrollador', () {
      // Es la forma en que se crean los roles por empresa.
      final data = {
        'empresas': ['CAPITAL'],
        'empresasDetalle': {
          'CAPITAL': {'roleId': 'CAPITAL_desarrollador'},
        },
      };

      expect(isDeveloperUser(data, empresaId: 'CAPITAL'), isTrue);
    });
  });

  group('el texto del rol se traduce a un permiso', () {
    test('administrador, en cualquiera de sus formas, es administrador', () {
      for (final texto in [
        'administrador',
        'ADMIN',
        'desarrollador',
        'gestor',
      ]) {
        expect(
          GdRolCorrespondencia.desdeTexto(texto),
          GdRolCorrespondencia.administrador,
          reason: texto,
        );
      }
    });

    test('un texto que no se reconoce no concede nada', () {
      // Un rol raro no puede convertirse en permiso por accidente.
      expect(GdRolCorrespondencia.desdeTexto('coordinador'), isNull);
      expect(GdRolCorrespondencia.desdeTexto(''), isNull);
      expect(GdRolCorrespondencia.desdeTexto(null), isNull);
    });
  });

  group('qué puede cada rol', () {
    test('el administrador del módulo puede todo', () {
      const p = GdPermisos(GdRolCorrespondencia.administrador);

      expect(p.puedeClasificar, isTrue);
      expect(p.puedeAsignar, isTrue);
      expect(p.puedeRadicar, isTrue);
      expect(p.puedeAdministrarTipos, isTrue);
      expect(p.puedeAdministrarFiltros, isTrue);
      expect(p.puedeCerrarCualquiera, isTrue);
    });

    test('el operador trabaja lo suyo y no clasifica', () {
      const p = GdPermisos(GdRolCorrespondencia.operador);

      expect(p.puedeGestionarAsignado, isTrue);
      expect(p.puedeClasificar, isFalse);
    });

    test('mientras se resuelve el rol solo se mira', () {
      // El estado intermedio es el más restrictivo, no el contrario.
      expect(GdPermisos.cargando.puedeClasificar, isFalse);
    });
  });
}
