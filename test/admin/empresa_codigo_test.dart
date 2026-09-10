import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/empresa_codigo.dart';

void main() {
  group('código desde el nombre', () {
    test('mayúsculas, sin tildes y con guion bajo', () {
      expect(codigoEmpresaDesdeNombre('Capital Uspec'), 'CAPITAL_USPEC');
      expect(
        codigoEmpresaDesdeNombre('Nutrición y Compañía'),
        'NUTRICION_Y_COMPANIA',
      );
    });

    test('los signos no llegan al código', () {
      // El id viaja concatenado en TBL_APPS, TBL_EMPLEADOS y en las rutas de
      // Storage: un punto o una barra ahí rompe más de lo que se ve.
      expect(codigoEmpresaDesdeNombre('F & C  S.A.S.'), 'F_C_S_A_S');
      expect(codigoEmpresaDesdeNombre('  Servir / Uspec  '), 'SERVIR_USPEC');
    });

    test('no quita SAS ni abrevia', () {
      // Dos empresas del mismo grupo se distinguen por ese sufijo.
      expect(codigoEmpresaDesdeNombre('Alimentos SAS'), 'ALIMENTOS_SAS');
      expect(codigoEmpresaDesdeNombre('Alimentos LTDA'), 'ALIMENTOS_LTDA');
    });

    test('un nombre larguísimo no deja el código terminado en guion', () {
      final codigo = codigoEmpresaDesdeNombre('${'A' * 78} BC');
      expect(codigo.length, lessThanOrEqualTo(kEmpresaCodigoMax));
      expect(codigo.endsWith('_'), isFalse);
    });
  });

  group('validación del nombre', () {
    test('un nombre normal pasa', () {
      expect(validarNombreEmpresaNueva('Capital Uspec'), isNull);
    });

    test('vacío o solo signos no pasa', () {
      expect(validarNombreEmpresaNueva(''), isNotNull);
      expect(validarNombreEmpresaNueva('   '), isNotNull);
      expect(validarNombreEmpresaNueva('&&&'), isNotNull);
      expect(validarNombreEmpresaNueva('AB'), isNotNull);
    });

    test('una colisión se detiene, no se resuelve con un número', () {
      // Que dos nombres produzcan el mismo código casi siempre significa que se
      // está creando una empresa que ya existe. Un EMPRESA_2 en silencio es un
      // duplicado que nadie nota hasta que los datos están repartidos.
      final error = validarNombreEmpresaNueva(
        'Capital  Uspec',
        codigosExistentes: const {'CAPITAL_USPEC'},
      );

      expect(error, contains('CAPITAL_USPEC'));
    });
  });
}
