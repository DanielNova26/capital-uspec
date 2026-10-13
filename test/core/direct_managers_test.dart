import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/direct_managers.dart';
import 'package:todo/core/team_company_scope.dart';

void main() {
  final people = <String, Map<String, dynamic>>{
    'persona': {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'jefeId': 'principal',
      'jefe_directo': 'Nombre del principal',
      'segundoJefePorEmpresa': {
        'A': {'id': 'segundo', 'nombre': 'Segundo'},
        'B': {'id': 'otro', 'nombre': 'Otro'},
      },
      'empresasDetalle': {
        'B': {'jefeId': 'principalB'},
      },
    },
    'hijo': {'empresaId': 'A', 'jefeId': 'persona'},
  };
  Set<String> equipo(
    String jefe, [
    String empresa = 'A',
    Map<String, Map<String, dynamic>>? data,
  ]) => TeamCompanyScope.subordinateIds(
    people: (data ?? people).entries,
    managerId: jefe,
    empresaId: empresa,
  );

  test(
    'ambos jefes ven la misma cadena sin usar nombres como identificadores',
    () {
      expect(equipo('principal'), {'persona', 'hijo'});
      expect(equipo('segundo'), {'persona', 'hijo'});
      expect(equipo('Nombre del principal'), isEmpty);
    },
  );
  test('el segundo jefe no se cruza entre empresas', () {
    expect(equipo('segundo', 'B'), isEmpty);
    expect(equipo('otro', 'B'), {'persona'});
    expect(equipo('otro'), isEmpty);
  });
  test('retirar e inactivar la relación elimina el equipo efectivo', () {
    final cleared = {
      ...people,
      'persona': {
        ...people['persona']!,
        'segundoJefePorEmpresa': {
          'A': {'id': '', 'nombre': ''},
        },
      },
    };
    expect(equipo('segundo', 'A', cleared), isEmpty);
    final inactive = {
      ...people,
      'persona': {...people['persona']!, 'estado': 'inactivo'},
    };
    expect(equipo('segundo', 'A', inactive), isEmpty);
  });
  test('conserva estructuras históricas con un solo jefe', () {
    expect(
      equipo('antiguo', 'A', {
        'p': {'empresaId': 'A', 'jefe_directo': 'antiguo'},
      }),
      {'p'},
    );
    expect(directManagerIds({'jefe_directo_id': 'antiguo'}, 'A'), {'antiguo'});
    expect(directManagerIds({'jefeId': 'antiguo'}, 'A'), {'antiguo'});
  });
  test('el detalle de empresa no suplanta el mapa canónico de jefaturas', () {
    final scoped = TeamCompanyScope.scopedPerson({
      ...people['persona']!,
      'empresasDetalle': {
        'A': {
          'segundoJefePorEmpresa': {
            'A': {'id': 'falso'},
          },
        },
      },
    }, 'A')!;
    expect(secondManager(scoped, 'A')['id'], 'segundo');
  });
  test(
    'rechaza repetidos, autorreferencia y ciclos a través del segundo jefe',
    () {
      String? validar(
        String a,
        String b, [
        Map<String, Set<String>> tree = const {},
      ]) => validateDirectManagers(
        personId: 'persona',
        primaryId: a,
        secondId: b,
        managersByPerson: tree,
      );
      expect(validar('jefe', 'jefe'), isNotNull);
      expect(validar('persona', ''), isNotNull);
      expect(validar('', 'segundo'), isNotNull);
      expect(
        validar('jefe', 'segundo', {
          'segundo': {'persona'},
        }),
        isNotNull,
      );
      expect(validar('jefe', 'segundo'), isNull);
    },
  );
}
