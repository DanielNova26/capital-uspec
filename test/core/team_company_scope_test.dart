import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/team_company_scope.dart';

void main() {
  group('TeamCompanyScope', () {
    test('rechaza personas de otra empresa', () {
      final person = <String, dynamic>{
        'empresaId': 'EMPRESA_B',
        'nombre': 'Persona B',
      };

      expect(TeamCompanyScope.scopedPerson(person, 'EMPRESA_A'), isNull);
    });

    test('usa la relación jerárquica específica de la empresa activa', () {
      final person = <String, dynamic>{
        'empresas': ['EMPRESA_A', 'EMPRESA_B'],
        'jefeId': 'JEFE_B',
        'empresasDetalle': {
          'EMPRESA_A': {'jefeId': 'JEFE_A', 'areaId': 'AREA_A'},
          'EMPRESA_B': {'jefeId': 'JEFE_B', 'areaId': 'AREA_B'},
        },
      };

      final scoped = TeamCompanyScope.scopedPerson(person, 'EMPRESA_A');

      expect(scoped, isNotNull);
      expect(scoped!['jefeId'], 'JEFE_A');
      expect(scoped['areaId'], 'AREA_A');
    });

    test('rechaza afiliación multiempresa ambigua sin detalle activo', () {
      final person = <String, dynamic>{
        'empresaId': 'EMPRESA_B',
        'empresas': ['EMPRESA_A', 'EMPRESA_B'],
        'jefeId': 'JEFE_B',
      };

      expect(TeamCompanyScope.scopedPerson(person, 'EMPRESA_A'), isNull);
    });

    test('construye subordinados recursivos sin incluir otra empresa', () {
      final people = <String, Map<String, dynamic>>{
        'A': {'empresaId': 'EMPRESA_A', 'jefeId': 'JEFE'},
        'B': {'empresaId': 'EMPRESA_A', 'jefeId': 'A'},
        'C': {'empresaId': 'EMPRESA_B', 'jefeId': 'JEFE'},
      };

      final result = TeamCompanyScope.subordinateIds(
        people: people.entries,
        managerId: 'JEFE',
        empresaId: 'EMPRESA_A',
      );

      expect(result, {'A', 'B'});
    });

    test('tareas sin empresa explícita nunca entran al panel del equipo', () {
      expect(
        TeamCompanyScope.taskBelongsToCompany({
          'titulo': 'Legacy sin empresa',
        }, 'EMPRESA_A'),
        isFalse,
      );
      expect(
        TeamCompanyScope.taskBelongsToCompany({
          'empresaId': 'EMPRESA_B',
          'empresas': ['EMPRESA_A', 'EMPRESA_B'],
        }, 'EMPRESA_A'),
        isFalse,
      );
      expect(
        TeamCompanyScope.taskBelongsToCompany({
          'empresas': ['EMPRESA_A', 'EMPRESA_B'],
        }, 'EMPRESA_A'),
        isTrue,
      );
    });
  });
}
