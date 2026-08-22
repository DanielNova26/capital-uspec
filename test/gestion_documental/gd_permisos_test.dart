import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_permisos.dart';

/// Lo que se garantiza aquí es la regla de fondo del módulo: clasificar y
/// asignar no lo puede hacer cualquiera que entre, y quien sí puede conserva
/// todo lo que podía antes.
void main() {
  group('jerarquía', () {
    test('el clasificador incluye las funciones del operador', () {
      // Fue el acuerdo textual de la reunión: "usuario clasificador y asignador
      // que incluya las funciones de un usuario".
      const clasificador = GdPermisos(GdRolCorrespondencia.clasificador);
      expect(clasificador.puedeClasificar, isTrue);
      expect(clasificador.puedeAsignar, isTrue);
      expect(clasificador.puedeRadicar, isTrue);
      expect(clasificador.puedeGestionarAsignado, isTrue);
    });

    test('el operador trabaja lo suyo pero no clasifica ni asigna', () {
      const operador = GdPermisos(GdRolCorrespondencia.operador);
      expect(operador.puedeGestionarAsignado, isTrue);
      expect(operador.puedeClasificar, isFalse);
      expect(operador.puedeAsignar, isFalse);
      expect(operador.puedeRadicar, isFalse);
    });

    test('el visor solo consulta', () {
      const visor = GdPermisos(GdRolCorrespondencia.visor);
      expect(visor.esSoloConsulta, isTrue);
      expect(visor.puedeGestionarAsignado, isFalse);
      expect(visor.puedeClasificar, isFalse);
    });

    test('el administrador puede todo', () {
      const admin = GdPermisos(GdRolCorrespondencia.administrador);
      expect(admin.puedeClasificar, isTrue);
      expect(admin.puedeAdministrarTipos, isTrue);
      expect(admin.puedeAdministrarFiltros, isTrue);
      expect(admin.puedeCerrarCualquiera, isTrue);
    });

    test('los maestros y los filtros son solo del administrador', () {
      // Un clasificador decide sobre un expediente; no sobre la configuración
      // del módulo. "Los filtros nada más lo podemos hacer tú y yo".
      const clasificador = GdPermisos(GdRolCorrespondencia.clasificador);
      expect(clasificador.puedeAdministrarFiltros, isFalse);
      expect(clasificador.puedeAdministrarTipos, isFalse);
      expect(clasificador.puedeCerrarCualquiera, isFalse);
    });

    test('el orden de los niveles no se altera', () {
      expect(
        GdRolCorrespondencia.values.map((r) => r.nivel).toList(),
        [1, 2, 3, 4],
        reason: 'el enum va de menor a mayor alcance, sin saltos ni empates',
      );
      expect(
        GdRolCorrespondencia.administrador.alcanza(
          GdRolCorrespondencia.clasificador,
        ),
        isTrue,
      );
      expect(
        GdRolCorrespondencia.operador.alcanza(
          GdRolCorrespondencia.clasificador,
        ),
        isFalse,
      );
    });
  });

  group('mientras se resuelve el rol', () {
    test('el permiso inicial es el más restrictivo', () {
      // Al revés se alcanzaría a pintar "Clasificar y asignar" a quien no puede,
      // y el usuario vería aparecer y desaparecer el botón.
      expect(GdPermisos.cargando.puedeClasificar, isFalse);
      expect(GdPermisos.cargando.puedeGestionarAsignado, isFalse);
    });
  });

  group('GdRolCorrespondencia.desdeTexto', () {
    test('reconoce las formas del rol clasificador', () {
      for (final texto in const [
        'clasificador',
        'CLASIFICADOR',
        'clasificadora',
        'asignador',
        'clasificador_asignador',
        'clasificador y asignador',
        '  Clasificador  ',
      ]) {
        expect(
          GdRolCorrespondencia.desdeTexto(texto),
          GdRolCorrespondencia.clasificador,
          reason: texto,
        );
      }
    });

    test('desarrollador y superadmin cuentan como administrador', () {
      for (final texto in const [
        'administrador',
        'admin',
        'manager',
        'gestor',
        'superadmin',
        'desarrollador',
        'developer',
      ]) {
        expect(
          GdRolCorrespondencia.desdeTexto(texto),
          GdRolCorrespondencia.administrador,
          reason: texto,
        );
      }
    });

    test('un texto desconocido no se convierte en permiso', () {
      // Es la parte que importa de verdad: si alguien escribe "jurídica" en el
      // campo rol, no puede terminar clasificando por descarte.
      for (final texto in const [
        'jurídica',
        'usuario',
        'talento humano',
        'clasificar',
        '',
        null,
      ]) {
        expect(GdRolCorrespondencia.desdeTexto(texto), isNull, reason: '$texto');
      }
    });
  });

  group('rol por defecto', () {
    test('quien entra sin rol asignado es operador', () {
      // Conserva el comportamiento anterior para quien solo responde lo suyo:
      // el cambio quita permisos de clasificar, no acceso al módulo.
      expect(GdPermisosService.rolPorDefecto, GdRolCorrespondencia.operador);
      const porDefecto = GdPermisos(GdRolCorrespondencia.operador);
      expect(porDefecto.puedeGestionarAsignado, isTrue);
      expect(porDefecto.puedeClasificar, isFalse);
    });
  });
}
