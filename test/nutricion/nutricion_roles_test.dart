import 'package:flutter_test/flutter_test.dart';
import 'package:todo/nutricion/nutricion_roles.dart';

void main() {
  final user = <String, dynamic>{
    'empresas': ['A', 'B'],
    'appsPorEmpresa': true,
    'empresasDetalle': {
      'A': {
        'activo': true,
        'apps': ['nutriciondashboard'],
      },
      'B': {'activo': true, 'apps': <String>[]},
    },
  };

  test('la app histórica conserva acceso hasta consolidar', () {
    expect(
      resolverNivelNutricion(user: user, empresaId: 'A', userId: 'persona'),
      NutricionLevel.administrador,
    );
    expect(
      resolverNivelNutricion(user: user, empresaId: 'B', userId: 'persona'),
      NutricionLevel.ninguno,
    );
  });

  test('fila canónica reduce acceso y falla cerrada si no corresponde', () {
    NutricionLevel resolve(Map<String, dynamic> row) => resolverNivelNutricion(
      user: user,
      empresaId: 'A',
      userId: 'persona',
      assignment: row,
    );
    expect(
      resolve({'empresaId': 'A', 'userId': 'persona', 'rol': 'consulta'}),
      NutricionLevel.consulta,
    );
    expect(
      resolve({'empresaId': 'B', 'userId': 'persona', 'rol': 'administrador'}),
      NutricionLevel.ninguno,
    );
    expect(
      resolve({'empresaId': 'A', 'userId': 'persona', 'rol': 'inventado'}),
      NutricionLevel.ninguno,
    );
  });

  test('las capacidades dejan un punto de extensión para nuevas secciones', () {
    expect(NutricionLevel.consulta.pestanas, [5]);
    expect(NutricionLevel.clinico.pestanas, [0, 3, 4, 5]);
    expect(NutricionLevel.menus.pestanas, [1, 2, 5]);
    expect(NutricionLevel.coordinador.pestanas, [0, 1, 2, 3, 4, 5]);
    expect(NutricionLevel.consulta.puedeAtender, isFalse);
    expect(NutricionLevel.clinico.puedeAtender, isTrue);
    expect(NutricionLevel.menus.puedeGestionarMenus, isTrue);
    expect(NutricionLevel.clinico.puedeGestionarMenus, isFalse);
  });

  test('la persona inhabilitada queda sin acceso', () {
    expect(
      resolverNivelNutricion(
        user: {...user, 'activo': false},
        empresaId: 'A',
        userId: 'persona',
      ),
      NutricionLevel.ninguno,
    );
  });
}
