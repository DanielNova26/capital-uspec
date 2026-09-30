import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/talento_humano_roles.dart';

void main() {
  final user = <String, dynamic>{
    'empresas': ['A', 'B'],
    'appsPorEmpresa': true,
    'empresasDetalle': {
      'A': {
        'activo': true,
        'apps': ['talentohumanodashboard'],
      },
      'B': {'activo': true, 'apps': <String>[]},
    },
  };

  test('el acceso anterior por app conserva la gestión hasta consolidarlo', () {
    expect(
      resolverNivelTalentoHumano(user: user, empresaId: 'A', userId: 'persona'),
      TalentoHumanoLevel.administrador,
    );
    expect(
      resolverNivelTalentoHumano(user: user, empresaId: 'B', userId: 'persona'),
      TalentoHumanoLevel.ninguno,
    );
  });

  test('la asignación canónica reduce el nivel y no cruza empresas', () {
    expect(
      resolverNivelTalentoHumano(
        user: user,
        empresaId: 'A',
        userId: 'persona',
        assignment: {'empresaId': 'A', 'userId': 'persona', 'rol': 'consulta'},
      ),
      TalentoHumanoLevel.consulta,
    );
    expect(
      resolverNivelTalentoHumano(
        user: user,
        empresaId: 'A',
        userId: 'persona',
        assignment: {
          'empresaId': 'B',
          'userId': 'persona',
          'rol': 'administrador',
        },
      ),
      TalentoHumanoLevel.ninguno,
    );
    expect(
      resolverNivelTalentoHumano(
        user: user,
        empresaId: 'A',
        userId: 'persona',
        assignment: {
          'empresaId': 'A', 'userId': 'persona', 'rol': 'desconocido',
        },
      ),
      TalentoHumanoLevel.ninguno,
    );
  });

  test('los niveles separan solicitudes, reclutamiento y gestión', () {
    expect(TalentoHumanoLevel.consulta.puedeSolicitar, isFalse);
    expect(TalentoHumanoLevel.solicitante.puedeSolicitar, isTrue);
    expect(TalentoHumanoLevel.solicitante.puedeReclutar, isFalse);
    expect(TalentoHumanoLevel.reclutador.puedeReclutar, isTrue);
    expect(TalentoHumanoLevel.reclutador.puedeGestionar, isFalse);
    expect(TalentoHumanoLevel.gestor.puedeGestionar, isTrue);
    expect(TalentoHumanoLevel.gestor.puedeAdministrar, isFalse);
    expect(TalentoHumanoLevel.administrador.puedeAdministrar, isTrue);
  });

  test('inhabilitar a una persona la deja sin acceso', () {
    expect(
      resolverNivelTalentoHumano(
        user: {...user, 'activo': false},
        empresaId: 'A',
        userId: 'persona',
      ),
      TalentoHumanoLevel.ninguno,
    );
  });
}
