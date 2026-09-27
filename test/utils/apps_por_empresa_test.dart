import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/user_company.dart';

/// Persona de A (principal) y B. La lista general la dejó Talento Humano
/// igual a lo último que editó en A; B tiene su propia lista.
Map<String, dynamic> _persona({bool marcada = false}) => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'apps': ['tareasdashboard', 'comprasdashboard'],
  if (marcada) kCampoAppsPorEmpresa: true,
  'empresasDetalle': {
    'A': {
      'apps': ['tareasdashboard', 'comprasdashboard'],
    },
    'B': {
      'apps': ['tareasdashboard', 'rutasdashboard'],
    },
  },
};

void main() {
  test('sin la marca, B suma la lista general (el comportamiento de antes)', () {
    expect(
      extractUserApps(_persona(), empresaId: 'B'),
      containsAll(['tareasdashboard', 'rutasdashboard', 'comprasdashboard']),
    );
    expect(appsHeredadasEnEmpresa(_persona(), 'B'), ['comprasdashboard']);
    expect(appsHeredadasEnEmpresa(_persona(), 'A'), isEmpty);
  });

  test('con la marca, cada empresa ve solo su lista', () {
    final p = _persona(marcada: true);
    expect(extractUserApps(p, empresaId: 'B'), [
      'tareasdashboard',
      'rutasdashboard',
    ]);
    expect(userHasApp(p, 'compras', empresaId: 'B'), isFalse);
    expect(userHasApp(p, 'compras', empresaId: 'A'), isTrue);
    expect(appsHeredadasEnEmpresa(p, 'B'), isEmpty);
  });

  test('con la marca y sin lista propia: la general solo en la principal', () {
    final p = <String, dynamic>{
      ..._persona(marcada: true),
      'empresasDetalle': <String, dynamic>{'B': <String, dynamic>{}},
    };
    expect(extractUserApps(p, empresaId: 'A'), [
      'tareasdashboard',
      'comprasdashboard',
    ]);
    expect(extractUserApps(p, empresaId: 'B'), isEmpty);
  });

  group('planearAppsPorEmpresa', () {
    test('congela lo que cada empresa ve hoy: nadie pierde nada', () {
      final plan = planearAppsPorEmpresa(_persona());
      expect(plan.porEmpresa['B'], [
        'comprasdashboard',
        'rutasdashboard',
        'tareasdashboard',
      ]);
      expect(plan.porEmpresa['A'], ['comprasdashboard', 'tareasdashboard']);
      // Lo común: versiones anteriores de la app no pasan nada de una a otra.
      expect(plan.raiz, ['comprasdashboard', 'tareasdashboard']);
      final rutas = plan.comoRutas();
      expect(rutas[kCampoAppsPorEmpresa], isTrue);
      expect(rutas['empresasDetalle.B.apps'], plan.porEmpresa['B']);
    });

    test('quitar heredadas deja a B con su lista', () {
      final plan = planearAppsPorEmpresa(_persona(), quitarHeredadas: true);
      expect(plan.porEmpresa['B'], ['rutasdashboard', 'tareasdashboard']);
      expect(plan.raiz, ['tareasdashboard']);
    });

    test('editar A no toca B', () {
      final antes = _persona(marcada: true);
      final plan = planearAppsPorEmpresa(
        antes,
        cambios: {
          'A': ['tareas', 'nutricion'],
        },
      );
      expect(plan.porEmpresa['A'], ['nutriciondashboard', 'tareasdashboard']);
      expect(plan.porEmpresa['B'], ['rutasdashboard', 'tareasdashboard']);

      // Aplicado, B sigue igual y A cambia.
      final despues = {
        ...antes,
        'apps': plan.raiz,
        'empresasDetalle': {
          for (final e in plan.porEmpresa.entries) e.key: {'apps': e.value},
        },
      };
      expect(userHasApp(despues, 'nutricion', empresaId: 'B'), isFalse);
      expect(userHasApp(despues, 'nutricion', empresaId: 'A'), isTrue);
      expect(userHasApp(despues, 'rutas', empresaId: 'B'), isTrue);
    });

    test('una empresa nueva entra con su lista', () {
      final plan = planearAppsPorEmpresa(
        _persona(marcada: true),
        cambios: {
          'C': ['tareas'],
        },
      );
      expect(plan.porEmpresa.keys, containsAll(['A', 'B', 'C']));
      expect(plan.porEmpresa['C'], ['tareasdashboard']);
      expect(plan.raiz, ['tareasdashboard']);
    });

    test('sin empresas no borra la lista general', () {
      final plan = planearAppsPorEmpresa({
        'apps': ['tareas'],
      });
      expect(plan.porEmpresa, isEmpty);
      expect(plan.raiz, ['tareasdashboard']);
    });
  });
}
