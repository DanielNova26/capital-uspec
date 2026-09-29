import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gerencia/gerencia_dashboard_screen.dart';
import 'package:todo/gerencia/gerencia_permisos.dart';

Map<String, dynamic> persona({
  Map<String, dynamic>? a,
  Map<String, dynamic>? b,
  String rol = '',
}) => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  if (rol.isNotEmpty) 'roleKey': rol,
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{'activo': true, 'areaId': 'A_nutricion', ...?a},
    'B': <String, dynamic>{'activo': true, 'areaId': 'B_calidad', ...?b},
  },
};

Map<String, dynamic> rol(Map<String, bool> permisos) => {
  'rolGerenciaId': 'X_mod_gerencia_r',
  'permisosGerencia': permisos,
};

void main() {
  test('sin rol no entra, aunque tenga la app', () {
    final acceso = resolverAccesoGerencia(
      persona(
        a: {
          'apps': ['gerenciadashboard'],
        },
      ),
      'A',
    );
    expect(acceso.permitido, isFalse);
    expect(acceso.motivo, contains('No tienes un rol de Gerencia'));
    expect(acceso.empresas, isEmpty);
  });

  test('los permisos sin vínculo al rol no cuentan', () {
    final acceso = resolverAccesoGerencia(
      persona(
        a: {
          'permisosGerencia': {kGerPermDashboard: true},
        },
      ),
      'A',
    );
    expect(acceso.permitido, isFalse);
  });

  test('rol inactivo (todo apagado) no deja entrar', () {
    final acceso = resolverAccesoGerencia(
      persona(a: rol({for (final p in kGerenciaPermisos) p.clave: false})),
      'A',
    );
    expect(acceso.permitido, isFalse);
    expect(acceso.motivo, contains('inactivo'));
  });

  test('solo su área: la de su ficha, comparada por nombre', () {
    final acceso = resolverAccesoGerencia(
      persona(a: rol({kGerPermDashboard: true})),
      'A',
    ).conAreaPropia({'A': 'Nutrición'});
    expect(acceso.permitido, isTrue);
    expect(acceso.empresas, {'A'});
    expect(acceso.limitadoPorArea, isTrue);
    expect(acceso.incluye('A', 'NUTRICION'), isTrue);
    expect(acceso.incluye('A', 'Calidad'), isFalse);
    // Otra empresa no entra sin "Todas sus empresas".
    expect(acceso.incluye('B', 'Nutrición'), isFalse);
  });

  test('sin área en su ficha no ve registros de áreas', () {
    final acceso = resolverAccesoGerencia(
      persona(a: rol({kGerPermDashboard: true})),
      'A',
    ).conAreaPropia({'A': 'Sin área'});
    expect(acceso.incluye('A', 'Sin área'), isFalse);
    expect(acceso.incluye('A', 'Calidad'), isFalse);
  });

  test('todas las áreas ve cualquier área de su empresa', () {
    final acceso = resolverAccesoGerencia(
      persona(a: rol({kGerPermDashboard: true, kGerPermTodasLasAreas: true})),
      'A',
    );
    expect(acceso.limitadoPorArea, isFalse);
    expect(acceso.incluye('A', 'Calidad'), isTrue);
    expect(acceso.incluye('A', 'Sin área'), isTrue);
  });

  test('todas sus empresas suma solo las que también le dan rol', () {
    final sinRolEnB = resolverAccesoGerencia(
      persona(
        a: rol({kGerPermDashboard: true, kGerPermTodasLasEmpresas: true}),
      ),
      'A',
    );
    expect(sinRolEnB.empresas, {'A'});

    final conRolEnB = resolverAccesoGerencia(
      persona(
        a: rol({
          kGerPermDashboard: true,
          kGerPermTodasLasEmpresas: true,
          kGerPermTodasLasAreas: true,
        }),
        b: rol({kGerPermPuntos: true}),
      ),
      'A',
    ).conAreaPropia({'A': 'Nutrición', 'B': 'Calidad'});
    expect(conRolEnB.empresas, {'A', 'B'});
    // Pestañas y exportar: las del rol de la empresa activa.
    expect(pestanasGerenciaPermitidas(conRolEnB.permisos), [0]);
    // El área, la del rol de cada empresa: en B solo su área.
    expect(conRolEnB.incluye('A', 'Calidad'), isTrue);
    expect(conRolEnB.incluye('B', 'Calidad'), isTrue);
    expect(conRolEnB.incluye('B', 'Nutrición'), isFalse);
    expect(conRolEnB.limitadoPorArea, isTrue);
  });

  test('una empresa inhabilitada no entra ni con rol', () {
    final data = persona(
      a: rol({kGerPermDashboard: true, kGerPermTodasLasEmpresas: true}),
      b: {
        ...rol({kGerPermDashboard: true}),
        'activo': false,
      },
    );
    expect(resolverAccesoGerencia(data, 'A').empresas, {'A'});
    expect(resolverAccesoGerencia(data, 'B').permitido, isFalse);
  });

  test('Desarrollo entra con todo sin rol', () {
    final acceso = resolverAccesoGerencia(persona(rol: 'desarrollador'), 'A');
    expect(acceso.permitido, isTrue);
    expect(acceso.permisos.exportar, isTrue);
    expect(pestanasGerenciaPermitidas(acceso.permisos), [0, 1, 2]);
  });

  test('catálogo extensible: lo que falte es falso; un texto invalida', () {
    final viejo = GerenciaPermisos.fromMap({kGerPermDashboard: true})!;
    expect(viejo.exportar, isFalse);
    expect(viejo.toMap().keys, [for (final p in kGerenciaPermisos) p.clave]);
    expect(GerenciaPermisos.fromMap({kGerPermExportar: 'sí'}), isNull);
    expect(GerenciaPermisos.fromMap('todo'), isNull);
    // Claves ajenas al catálogo se ignoran.
    expect(
      GerenciaPermisos.fromMap({
        'borrarTodo': true,
      })!.igualA(const GerenciaPermisos.ninguno()),
      isTrue,
    );
  });

  test('pestañas en el orden del módulo', () {
    expect(
      pestanasGerenciaPermitidas(
        const GerenciaPermisos({
          kGerPermInterventoria: true,
          kGerPermDashboard: true,
        }),
      ),
      [0, 2],
    );
    expect(
      pestanasGerenciaPermitidas(const GerenciaPermisos.ninguno()),
      isEmpty,
    );
  });
}
