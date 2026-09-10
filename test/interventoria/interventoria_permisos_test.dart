import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

/// La matriz de permisos del módulo, fijada como acuerdo del 10 sep 2026.
///
/// Está en pruebas y no solo en un documento porque un permiso que se mueve sin
/// querer no rompe la compilación: se descubre cuando alguien no puede entrar a
/// trabajar, o peor, cuando entra alguien que no debía.
void main() {
  const admin = kRolInterventoriaAdmin;
  const registrador = kRolInterventoriaRegistrador;
  const revisor = kRolInterventoriaRevisor; // Kary
  const calidad = kRolInterventoriaCalidad;
  const gerente = kRolInterventoriaGerente;
  const directivo = kRolInterventoriaDirectivo;

  group('"Por revisar"', () {
    test('entran administración, Kary y gerencia', () {
      expect(puedeRevisarActas(admin), isTrue);
      expect(puedeRevisarActas(revisor), isTrue);
      expect(puedeRevisarActas(gerente), isTrue);
    });

    test('no entran dirección, calidad ni el registrador', () {
      expect(puedeRevisarActas(directivo), isFalse);
      expect(puedeRevisarActas(calidad), isFalse);
      expect(puedeRevisarActas(registrador), isFalse);
    });
  });

  group('reasignar responsables en Subsanaciones', () {
    test('solo administración y gerencia', () {
      expect(puedeReasignarResponsable(admin), isTrue);
      expect(puedeReasignarResponsable(gerente), isTrue);
    });

    test('Kary revisa y devuelve actas, pero no mueve responsables', () {
      // Reasignar cambia a quién se le exige el trabajo; esa decisión es de
      // administración y gerencia.
      expect(puedeReasignarResponsable(revisor), isFalse);
      expect(puedeReasignarResponsable(calidad), isFalse);
      expect(puedeReasignarResponsable(directivo), isFalse);
    });
  });

  group('Maestro de responsabilidades', () {
    test('solo administración y gerencia', () {
      // Cambiarlo mueve el trabajo de todo el mundo.
      expect(puedeConsultarMaestroSubsanaciones(admin), isTrue);
      expect(puedeConsultarMaestroSubsanaciones(gerente), isTrue);
    });

    test('ni Kary ni calidad ni dirección', () {
      expect(puedeConsultarMaestroSubsanaciones(revisor), isFalse);
      expect(puedeConsultarMaestroSubsanaciones(calidad), isFalse);
      expect(puedeConsultarMaestroSubsanaciones(directivo), isFalse);
    });
  });

  group('Análisis', () {
    test('lo ven quienes miran el desempeño', () {
      expect(kInterventoriaRolesDirectivos, contains(directivo));
      expect(kInterventoriaRolesDirectivos, contains(calidad));
      expect(kInterventoriaRolesDirectivos, contains(gerente));
      expect(kInterventoriaRolesDirectivos, contains(admin));
    });

    test('Kary no lo necesita', () {
      // Ella corrige actas; el análisis es de quien mira el desempeño de los
      // establecimientos.
      expect(kInterventoriaRolesDirectivos, isNot(contains(revisor)));
    });
  });

  group('Calidad', () {
    test('es un rol asignable desde el panel de administración', () {
      expect(kInterventoriaRoles, contains(calidad));
      expect(kInterventoriaRoleLabels[calidad], 'Calidad');
    });

    test('mira, no escribe', () {
      // Subsanaciones en solo lectura: sin permiso de escritura no registra
      // seguimiento ni mueve nada.
      expect(kInterventoriaRolesEscritura, isNot(contains(calidad)));
    });
  });

  group('un rol vacío o desconocido no abre nada', () {
    test('sin rol no hay permisos', () {
      for (final rol in ['', 'cualquier_cosa']) {
        expect(puedeRevisarActas(rol), isFalse);
        expect(puedeReasignarResponsable(rol), isFalse);
        expect(puedeConsultarMaestroSubsanaciones(rol), isFalse);
        expect(kInterventoriaRolesDirectivos, isNot(contains(rol)));
        expect(kInterventoriaRolesEscritura, isNot(contains(rol)));
      }
    });
  });
}
