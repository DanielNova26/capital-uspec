import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/user_company.dart';

void main() {
  test('resuelve estructura multiempresa sin usar el empresaId top-level', () {
    final data = <String, dynamic>{
      'empresaId': 'EMPRESA_002',
      'empresas': ['EMPRESA_001', 'EMPRESA_002'],
      'area': 'Auditoría',
      'cargo': 'Auxiliar de Auditoría',
      'empresasDetalle': {
        'EMPRESA_001': {
          'area': 'Contabilidad',
          'areaId': 'EMPRESA_001_contabilidad',
          'cargo': 'Auxiliar De Auditoria',
        },
        'EMPRESA_002': {
          'area': 'Auditoría',
          'areaId': 'EMPRESA_002_auditoria',
          'cargo': 'Auxiliar de Auditoría',
        },
      },
    };

    expect(matchesEmpresaScope(data, 'EMPRESA_001'), isTrue);
    final scoped = mergeCompanyScopedData(data, 'EMPRESA_001');
    expect(scoped['area'], 'Contabilidad');
    expect(scoped['areaId'], 'EMPRESA_001_contabilidad');
    expect(scoped['cargo'], 'Auxiliar De Auditoria');
  });

  test(
    'los módulos específicos de empresa se combinan con el fallback global',
    () {
      final data = <String, dynamic>{
        'apps': ['admindashboard'],
        'empresasDetalle': {
          'EMPRESA_001': {
            'apps': ['talentohumanodashboard'],
          },
        },
      };

      expect(extractUserApps(data, empresaId: 'EMPRESA_001'), [
        'admindashboard',
        'talentohumanodashboard',
      ]);
      expect(extractUserApps(data, empresaId: 'EMPRESA_002'), [
        'admindashboard',
      ]);
    },
  );

  test('el nombre visible no cambia la clave interna de desarrollador', () {
    final data = <String, dynamic>{
      'role': 'usuario',
      'empresasDetalle': {
        'EMPRESA_001': {
          'roleId': 'EMPRESA_001_desarrollador',
          'roleKey': 'desarrollador',
          'roleNombre': 'Administrador técnico',
        },
      },
    };

    expect(
      resolveScopedRoleKey(data, empresaId: 'EMPRESA_001'),
      'desarrollador',
    );
    expect(
      resolveScopedRoleName(data, empresaId: 'EMPRESA_001'),
      'Administrador técnico',
    );
    expect(isDeveloperUser(data, empresaId: 'EMPRESA_001'), isTrue);
    expect(isDeveloperUser(data, empresaId: 'EMPRESA_002'), isFalse);
  });

  test('un desarrollador no aparece en una empresa a la que no pertenece', () {
    final data = <String, dynamic>{
      'desarrollador': true,
      'empresaId': 'EMPRESA_SERVIR',
      'empresas': ['EMPRESA_SERVIR'],
      'empresasDetalle': {
        'EMPRESA_SERVIR': {'roleKey': 'desarrollador'},
      },
    };

    expect(
      matchesEmpresaScope(
        data,
        'EMPRESA_CAPITAL',
        allowLegacyWithoutEmpresa: false,
      ),
      isFalse,
    );
    expect(
      matchesEmpresaScope(
        data,
        'EMPRESA_SERVIR',
        allowLegacyWithoutEmpresa: false,
      ),
      isTrue,
    );
  });

  test('normaliza Facturación al identificador canónico del módulo', () {
    final result = normalizeAppIdList(['facturacion', 'facturaciondashboard']);

    expect(result.ids, ['facturaciondashboard']);
    expect(result.changed, isTrue);
    expect(appIdsEquivalent('facturacion', 'facturaciondashboard'), isTrue);
  });

  test(
    'conserva Planillas como módulo independiente para roles existentes',
    () {
      final data = <String, dynamic>{
        'apps': ['gestiondocumentaldashboard'],
        'empresasDetalle': {
          'EMPRESA_001': {'rolPlanillas': 'auditoria'},
        },
      };

      expect(
        userHasApp(data, 'planillaspagodashboard', empresaId: 'EMPRESA_001'),
        isTrue,
      );
      expect(
        userHasApp(data, 'planillaspagodashboard', empresaId: 'EMPRESA_002'),
        isFalse,
      );
      expect(appIdsEquivalent('planillas', 'planillaspagodashboard'), isTrue);
    },
  );
}
