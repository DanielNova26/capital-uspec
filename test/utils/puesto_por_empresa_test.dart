import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/empresa_resolver.dart';
import 'package:todo/core/org_context_resolver.dart';
import 'package:todo/core/task_permissions.dart';
import 'package:todo/utils/user_company.dart';

/// Persona de A (principal) que también trabaja en B. La raíz es la copia
/// de A. En B solo tiene escrito el cargo: el área, el centro y el jefe de B
/// no existen, y NO deben salir los de A.
Map<String, dynamic> _persona() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'nombres': 'Ana',
  'correo': 'ana@x.co',
  'cargo': 'Gerente general',
  'cargoId': 'A_gerente',
  'area': 'Gerencia',
  'areaId': 'A_gerencia',
  'centroId': 'A_2001',
  'centroCostos': 'Cómbita',
  'centrosOperacionIds': ['A_2001'],
  'jefeId': '999',
  'empresasDetalle': {
    'A': {'cargo': 'Gerente general', 'areaId': 'A_gerencia'},
    'B': {'cargo': 'Auxiliar de cocina'},
  },
};

void main() {
  group('raizEsDeEmpresa', () {
    test('la raíz es de la principal', () {
      expect(raizEsDeEmpresa(_persona(), 'A'), isTrue);
      expect(raizEsDeEmpresa(_persona(), 'B'), isFalse);
    });

    test('sin principal: vale con una sola empresa o ninguna', () {
      expect(
        raizEsDeEmpresa({
          'empresas': ['A'],
        }, 'A'),
        isTrue,
      );
      expect(
        raizEsDeEmpresa({
          'empresas': ['A', 'B'],
        }, 'A'),
        isFalse,
      );
      expect(raizEsDeEmpresa({'cargo': 'X'}, 'A'), isTrue);
    });
  });

  group('mergeCompanyScopedData', () {
    test('en otra empresa no hereda el puesto de la principal', () {
      final b = mergeCompanyScopedData(_persona(), 'B');
      expect(b['cargo'], 'Auxiliar de cocina');
      for (final k in [
        'area',
        'areaId',
        'cargoId',
        'centroId',
        'centroCostos',
        'centrosOperacionIds',
        'jefeId',
      ]) {
        expect(b.containsKey(k), isFalse, reason: k);
      }
      // Lo que es de la persona sí se conserva.
      expect(b['nombres'], 'Ana');
      expect(b['correo'], 'ana@x.co');
    });

    test('en la principal la raíz completa lo que falte', () {
      final a = mergeCompanyScopedData(_persona(), 'A');
      expect(a['centroCostos'], 'Cómbita');
      expect(a['cargo'], 'Gerente general');
    });

    test('sin empresa no se toca nada', () {
      expect(mergeCompanyScopedData(_persona(), null)['area'], 'Gerencia');
    });
  });

  test('resolveScopedStringWithFallbacks respeta la regla', () {
    String area(String empresa) => resolveScopedStringWithFallbacks(
      _persona(),
      empresa,
      const ['area'],
      const ['area'],
    );
    expect(area('A'), 'Gerencia');
    expect(area('B'), '');
    // El correo es de la persona: vale en cualquier empresa.
    expect(
      resolveScopedStringWithFallbacks(
        _persona(),
        'B',
        const ['correo'],
        const ['correo'],
      ),
      'ana@x.co',
    );
  });

  test('OrgContextResolver no completa B con la raíz de A', () {
    final b = const OrgContextResolver().resolve(
      userData: _persona(),
      empresaId: 'B',
    );
    expect(b.cargoNombre, 'Auxiliar de cocina');
    expect(b.areaId, isNull);
    expect(b.centroId, isNull);
    final a = const OrgContextResolver().resolve(
      userData: _persona(),
      empresaId: 'A',
    );
    expect(a.centroCostos, 'Cómbita');
  });

  test('EmpresaResolver no usa la raíz para otra empresa', () {
    final sinBloque = {..._persona()}..remove('empresasDetalle');
    final r = const EmpresaResolver().resolveDetalle(
      userData: sinBloque,
      empresaId: 'B',
    );
    expect(r.detail, isNull);
    expect(
      const EmpresaResolver()
          .resolveDetalle(userData: sinBloque, empresaId: 'A')
          .detail?['cargo'],
      'Gerente general',
    );
  });

  group('empresa apagada por un traslado', () {
    Map<String, dynamic> trasladada() => {
      ..._persona(),
      'empresaId': 'B',
      'ultimaEmpresaId': 'A',
      'empresasDetalle': {
        'A': {'cargo': 'Gerente general', 'activo': false, 'trasladadoA': 'B'},
        'B': {'cargo': 'Auxiliar de cocina', 'activo': true},
      },
    };

    test('no se ofrece para entrar, pero sigue siendo membresía', () {
      expect(empresasSeleccionables(trasladada()), ['B']);
      expect(extractUserEmpresaIds(trasladada()), ['A', 'B']);
    });

    test('una sesión guardada en la apagada cae a la abierta', () {
      expect(
        resolveValidEmpresaId(
          data: trasladada(),
          selectedEmpresaId: 'A',
          preferredEmpresaId: 'A',
        ),
        'B',
      );
    });

    test('si todas están apagadas no deja a nadie sin empresa', () {
      final todas = {
        ...trasladada(),
        'empresasDetalle': {
          'A': {'activo': false},
          'B': {'activo': false},
        },
      };
      expect(empresasSeleccionables(todas), ['A', 'B']);
    });
  });

  // Los mismos casos que functions/test/acceso.test.js: la app y el servidor
  // deben decidir igual quién entra.
  group('motivoAccesoBloqueado', () {
    Map<String, dynamic> persona(
      Map<String, dynamic> detalle, [
      Map<String, dynamic> extra = const {},
    ]) => {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'empresasDetalle': detalle,
      ...extra,
    };

    test('activo en sus empresas: entra', () {
      expect(motivoAccesoBloqueado(persona({'A': {}, 'B': {}})), isNull);
    });

    test('cuenta apagada en Administración: no entra', () {
      expect(
        motivoAccesoBloqueado(persona({'A': {}}, {'activo': false})),
        kMensajeCuentaInhabilitada,
      );
      expect(cuentaInhabilitada({'status': 'inactive'}), isTrue);
      expect(cuentaInhabilitada({'estado': 'active'}), isFalse);
      expect(cuentaInhabilitada({'estado': '', 'status': 'activo'}), isFalse);
    });

    test('inhabilitado por Talento Humano en todas: no entra', () {
      final u = persona({
        'A': {'estadoLaboral': 'inactivo'},
        'B': {'estado': 'inactivo'},
      });
      expect(empresasSeleccionables(u), isEmpty);
      expect(motivoAccesoBloqueado(u), kMensajeInhabilitadoEnEmpresas);
      expect(resolveValidEmpresaId(data: u, preferredEmpresaId: 'A'), isNull);
    });

    test('inhabilitado en una: entra solo a la otra', () {
      final u = persona({
        'A': {'estadoLaboral': 'inactivo'},
        'B': {},
      });
      expect(empresasSeleccionables(u), ['B']);
      expect(motivoAccesoBloqueado(u), isNull);
      expect(resolveValidEmpresaId(data: u, selectedEmpresaId: 'A'), 'B');
    });

    test('reactivado: estadoLaboral activo manda', () {
      final u = persona({
        'A': {'estadoLaboral': 'activo', 'estado': 'inactivo'},
      });
      expect(motivoAccesoBloqueado(u), isNull);
    });

    test('apagada por traslado + inhabilitada en la otra: no entra', () {
      final u = persona({
        'A': {'activo': false},
        'B': {'estadoLaboral': 'inactivo'},
      });
      expect(motivoAccesoBloqueado(u), kMensajeInhabilitadoEnEmpresas);
    });

    test('todas apagadas por traslado, sin inhabilitación: no se bloquea', () {
      final u = persona({
        'A': {'activo': false},
        'B': {'activo': false},
      });
      expect(empresasSeleccionables(u), ['A', 'B']);
      expect(motivoAccesoBloqueado(u), isNull);
    });

    test('registro viejo sin empresas: no se bloquea por empresas', () {
      expect(motivoAccesoBloqueado({'nombres': 'X'}), isNull);
    });
  });

  group('personaInhabilitadaEn', () {
    test('lo dice TBL_USUARIOS por empresa', () {
      final u = {
        ..._persona(),
        'empresasDetalle': {
          'A': {'estadoLaboral': 'inactivo'},
          'B': {'estadoLaboral': 'activo'},
        },
      };
      expect(personaInhabilitadaEn(u, 'A'), isTrue);
      expect(personaInhabilitadaEn(u, 'B'), isFalse);
    });

    test('o la estructura: bloque, raíz de la principal o campo literal', () {
      final u = _persona();
      expect(
        personaInhabilitadaEn(
          u,
          'B',
          estructura: {
            'empresaId': 'A',
            'empresas': ['A', 'B'],
            'empresasDetalle': {
              'B': {'estado': 'inactivo'},
            },
          },
        ),
        isTrue,
      );
      expect(
        personaInhabilitadaEn(
          u,
          'A',
          estructura: {
            'empresaId': 'A',
            'empresas': ['A'],
            'estado': 'inactivo',
          },
        ),
        isTrue,
      );
      // El literal con punto es la última decisión: gana sobre el bloque.
      expect(
        personaInhabilitadaEn(
          u,
          'A',
          estructura: {
            'empresaId': 'A',
            'empresas': ['A'],
            'empresasDetalle.A.estado': 'activo',
            'empresasDetalle': {
              'A': {'estado': 'inactivo'},
            },
          },
        ),
        isFalse,
      );
    });

    test('la raíz de la estructura no habla por otra empresa', () {
      expect(
        personaInhabilitadaEn(
          _persona(),
          'B',
          estructura: {
            'empresaId': 'A',
            'empresas': ['A', 'B'],
            'estado': 'inactivo',
          },
        ),
        isFalse,
      );
    });

    test('apagada por traslado no es inhabilitada', () {
      final u = {
        ..._persona(),
        'empresasDetalle': {
          'A': {'activo': false, 'trasladadoA': 'B'},
        },
      };
      expect(personaInhabilitadaEn(u, 'A'), isFalse);
    });

    test('cuenta inhabilitada', () {
      expect(cuentaInhabilitada({'activo': false}), isTrue);
      expect(cuentaInhabilitada({'estado': 'inactivo'}), isTrue);
      expect(cuentaInhabilitada({'estado': 'activo'}), isFalse);
      expect(cuentaInhabilitada(_persona()), isFalse);
    });
  });

  test('ser Gerente en A no da todas las áreas en B', () {
    expect(canCreateTasksAcrossAreas(_persona(), empresaId: 'A'), isTrue);
    expect(canCreateTasksAcrossAreas(_persona(), empresaId: 'B'), isFalse);
  });
}
