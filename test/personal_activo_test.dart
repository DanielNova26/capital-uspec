// Reglas de "personal activo" compartidas por todos los módulos.
//
// El retiro se registra en Talento Humano por empresa
// (`PersonnelStatusService.changeStatus`), no en el `estado` global que solo
// controla el inicio de sesión. Estas pruebas fijan esa diferencia, que es
// justo la que hacía que los retirados siguieran apareciendo en los
// desplegables de asignación.

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/user_company.dart';

void main() {
  test('sin datos de estado se considera activo', () {
    expect(isPersonaActivaEnEmpresa({'nombre': 'Ana'}, 'EMP1'), isTrue);
  });

  test('estadoLaboral inactivo en la empresa activa lo excluye', () {
    final data = {
      'estado': 'activo',
      'empresasDetalle': {
        'EMP1': {'estadoLaboral': 'inactivo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, 'EMP1'), isFalse);
  });

  test('el retiro es por empresa: sigue activo en la otra', () {
    final data = {
      'empresasDetalle': {
        'EMP1': {'estadoLaboral': 'inactivo'},
        'EMP2': {'estadoLaboral': 'activo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, 'EMP1'), isFalse);
    expect(isPersonaActivaEnEmpresa(data, 'EMP2'), isTrue);
  });

  test('estado inactivo dentro del bloque de empresa (estructura) excluye', () {
    // TBL_ESTRUCTURA_ORGANIZACIONAL guarda el retiro como `estado`.
    final data = {
      'empresasDetalle': {
        'EMP1': {'estado': 'inactivo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, 'EMP1'), isFalse);
  });

  test('el bloque de la empresa manda sobre el estado raíz', () {
    // El `estado` raíz de la estructura es el de su empresa principal; para
    // otra empresa manda su propio bloque.
    final data = {
      'empresaId': 'EMP1',
      'estado': 'inactivo',
      'empresasDetalle': {
        'EMP2': {'estado': 'activo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, 'EMP2'), isTrue);
    expect(isPersonaActivaEnEmpresa(data, 'EMP1'), isFalse);
  });

  test('activo:false (interruptor de Admin) inhabilita siempre', () {
    final data = {
      'activo': false,
      'empresasDetalle': {
        'EMP1': {'estadoLaboral': 'activo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, 'EMP1'), isFalse);
  });

  test('estado global inactivo excluye cuando la empresa no dice nada', () {
    expect(isPersonaActivaEnEmpresa({'estado': 'inactivo'}, 'EMP1'), isFalse);
  });

  test('sin empresa activa se cae al estado global', () {
    final data = {
      'empresasDetalle': {
        'EMP1': {'estadoLaboral': 'inactivo'},
      },
    };
    expect(isPersonaActivaEnEmpresa(data, null), isTrue);
  });

  // ── Marca "no recibe tareas operativas" ───────────────────────────────────
  // Es distinta del retiro: la persona sigue vinculada y entra a la app, pero
  // deja de aparecer como candidata en los desplegables de asignación.

  test('sin marca, todo el mundo recibe asignaciones', () {
    expect(recibeAsignacionesEnEmpresa({'nombre': 'Ana'}, 'EMP1'), isTrue);
    expect(cargoRecibeAsignaciones({'nombre': 'AUXILIAR'}), isTrue);
  });

  test('la marca del cargo saca a su gente de los desplegables', () {
    expect(
      recibeAsignacionesEnEmpresa({}, 'EMP1', marcaDelCargo: false),
      isFalse,
    );
  });

  test('la marca de la persona manda sobre la del cargo', () {
    final data = {
      'empresasDetalle': {
        'EMP1': {'recibeAsignaciones': true},
      },
    };
    expect(
      recibeAsignacionesEnEmpresa(data, 'EMP1', marcaDelCargo: false),
      isTrue,
    );
  });

  test('la marca es por empresa, igual que el retiro', () {
    final data = {
      'empresasDetalle': {
        'EMP1': {'recibeAsignaciones': false},
        'EMP2': {'recibeAsignaciones': true},
      },
    };
    expect(recibeAsignacionesEnEmpresa(data, 'EMP1'), isFalse);
    expect(recibeAsignacionesEnEmpresa(data, 'EMP2'), isTrue);
  });

  test("un 'false' de texto (importado de Excel) cuenta como false", () {
    // Sin esto Dart lee la cadena como truthy y la marca no hace nada.
    expect(cargoRecibeAsignaciones({'recibeAsignaciones': 'false'}), isFalse);
    expect(cargoRecibeAsignaciones({'recibeAsignaciones': 'NO'}), isFalse);
    expect(cargoRecibeAsignaciones({'recibeAsignaciones': 'Si'}), isTrue);
    // Un valor que no se entiende no puede inhabilitar a nadie.
    expect(cargoRecibeAsignaciones({'recibeAsignaciones': 'quizas'}), isTrue);
  });

  test('asignable exige estar activo Y recibir tareas', () {
    final retirado = {
      'empresasDetalle': {
        'EMP1': {'estadoLaboral': 'inactivo'},
      },
    };
    final administrativo = {
      'empresasDetalle': {
        'EMP1': {'recibeAsignaciones': false},
      },
    };
    expect(esPersonaAsignable(retirado, 'EMP1'), isFalse);
    expect(esPersonaAsignable(administrativo, 'EMP1'), isFalse);
    expect(esPersonaAsignable({'nombre': 'Ana'}, 'EMP1'), isTrue);
    // Activa pero con el cargo marcado: tampoco.
    expect(
      esPersonaAsignable({'nombre': 'Ana'}, 'EMP1', marcaDelCargo: false),
      isFalse,
    );
  });
}
