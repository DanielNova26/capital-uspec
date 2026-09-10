import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_cuentas_models.dart';

/// Cédulas y cuentas inventadas. Lo que se copia del maestro real son las
/// formas del problema, no los datos de nadie.
void main() {
  CuentaBancaria cuenta({
    String cedula = '1014267058',
    String nombre = 'PERSONA DE PRUEBA UNO',
    String banco = '0013',
    String numero = '902027895',
  }) => CuentaBancaria(
    cedula: cedula,
    empresaId: 'capital',
    nombre: nombre,
    bancoCodigo: banco,
    numeroCuenta: numero,
  );

  group('código de banco', () {
    test('el mismo banco escrito de dos formas queda igual', () {
      // En la hoja real hay 21 valores distintos para 14 bancos: unas celdas
      // guardan "0013" como texto y otras el número 13 con formato 0000.
      // Comparar el código en crudo deja fuera a media plantilla del BBVA.
      expect(
        cuenta(banco: '13').bancoCodigo,
        cuenta(banco: '0013').bancoCodigo,
      );
      expect(cuenta(banco: '507').bancoCodigo, '0507');
      expect(cuenta(banco: '7').bancoCodigo, '0007');
    });

    test('también normaliza al leer de Firestore, no solo al escribir', () {
      // Un documento que entró por una importación vieja o por consola trae
      // "13" y tiene que comportarse igual que uno que trae "0013".
      final leida = CuentaBancaria.fromMap('capital_123', {
        'cedula': '123',
        'empresaId': 'capital',
        'nombre': 'ALGUIEN',
        'bancoCodigo': '13',
        'numeroCuenta': '1',
      });

      expect(leida.bancoCodigo, '0013');
    });
  });

  group('quién ve el número de cuenta', () {
    test('Talento Humano no lo ve', () {
      expect(puedeVerNumeroCuenta(kCuentaRolTalentoHumano), isFalse);
      expect(puedeEditarNumeroCuenta(kCuentaRolTalentoHumano), isFalse);
    });

    test('Talento Humano sí registra el banco', () {
      expect(puedeEditarBancoCuenta(kCuentaRolTalentoHumano), isTrue);
    });

    test('Tesorería ve y edita todo', () {
      expect(puedeVerNumeroCuenta(kCuentaRolTesoreria), isTrue);
      expect(puedeEditarNumeroCuenta(kCuentaRolTesoreria), isTrue);
      expect(puedeEditarBancoCuenta(kCuentaRolTesoreria), isTrue);
    });

    test('un rol desconocido no ve ni edita nada', () {
      expect(puedeVerNumeroCuenta('interventoria'), isFalse);
      expect(puedeEditarBancoCuenta(''), isFalse);
    });

    test('paraRol tapa el número a quien no le compete', () {
      final vista = cuenta(
        numero: '902027895',
      ).paraRol(kCuentaRolTalentoHumano);

      expect(vista.numeroCuenta, endsWith('7895'));
      expect(vista.numeroCuenta, isNot(contains('902')));
      expect(vista.bancoCodigo, '0013'); // el banco sí lo ve
    });

    test('deja ver que la cuenta existe, sin decir cuál', () {
      // Un campo vacío y un campo oculto se ven igual, y llevan a pedir un
      // dato que ya está registrado.
      expect(enmascararNumeroCuenta('902027895'), isNotEmpty);
      expect(enmascararNumeroCuenta(''), isEmpty);
    });

    test('una cuenta muy corta se tapa entera', () {
      expect(enmascararNumeroCuenta('123'), '•••');
    });
  });

  group('id del documento', () {
    test('lleva la empresa, para que el permiso sea por empresa', () {
      expect(
        cuentaBancariaDocId('capital', '1014267058'),
        'capital_1014267058',
      );
      expect(
        cuentaBancariaDocId('fyc', '1014267058'),
        isNot(cuentaBancariaDocId('capital', '1014267058')),
      );
    });
  });

  group('importación del maestro', () {
    test('un lote limpio entra completo', () {
      final r = analizarImportacionCuentas([
        cuenta(cedula: '1'),
        cuenta(cedula: '2', numero: '999'),
      ]);

      expect(r.listas, hasLength(2));
      expect(r.conflictos, isEmpty);
    });

    test('la misma cédula dos veces se bloquea, no se elige una', () {
      // El maestro real trae cuatro casos. Son dos cuentas distintas para la
      // misma persona y nadie sabe cuál es la vigente: quedarse con la
      // primera sería decidir a dónde va un sueldo.
      final r = analizarImportacionCuentas([
        cuenta(cedula: '1014267058', numero: '111'),
        cuenta(cedula: '1014267058', numero: '222'),
      ]);

      expect(r.listas, hasLength(1));
      expect(r.bloqueos, hasLength(1));
      expect(r.bloqueos.single.detalle, contains('fila 1'));
    });

    test('dos personas con la misma cuenta se avisa pero entra', () {
      // Pasa de verdad: una pareja que cobra en la misma cuenta.
      final r = analizarImportacionCuentas([
        cuenta(cedula: '1', numero: '555'),
        cuenta(cedula: '2', numero: '555'),
      ]);

      expect(r.listas, hasLength(2));
      expect(r.avisos, hasLength(1));
      expect(r.bloqueos, isEmpty);
    });

    test('un banco fuera del catálogo se avisa, nunca se bloquea', () {
      // En el maestro real hay once personas cobrando en 0507, 0551 y 0809,
      // que el catálogo del propio Excel no tiene, y llevan meses cobrando
      // sin problema. El catálogo está viejo, no los datos. Bloquear aquí
      // dejaría a once personas sin sueldo por culpa de nuestra tabla.
      final r = analizarImportacionCuentas(
        [cuenta(banco: '0507')],
        codigosBancoConocidos: const {'0013', '0007'},
      );

      expect(r.listas, hasLength(1));
      expect(r.avisos, hasLength(1));
      expect(r.avisos.single.detalle, contains('0507'));
      expect(r.bloqueos, isEmpty);
    });

    test('sin catálogo no inventa avisos de banco', () {
      final r = analizarImportacionCuentas([cuenta(banco: '0507')]);

      expect(r.conflictos, isEmpty);
    });

    test('bloquea lo que el banco rechazaría', () {
      final r = analizarImportacionCuentas([
        cuenta(numero: '902-027-895'),
        cuenta(cedula: '2', nombre: 'A' * 37, numero: '1'),
        cuenta(cedula: '3', banco: '0', numero: '2'),
      ]);

      expect(r.listas, isEmpty);
      expect(r.bloqueos, hasLength(3));
    });

    test('cada conflicto dice de quién es', () {
      final r = analizarImportacionCuentas([
        cuenta(nombre: 'JUANA PEREZ', numero: ''),
      ]);

      expect(r.bloqueos.single.toString(), contains('JUANA PEREZ'));
    });
  });

  group('paso al archivo plano', () {
    test(
      'la cuenta se convierte en línea de pago con su banco normalizado',
      () {
        final fila = cuenta(banco: '13').aFilaDePago(
          importeCentavos: 386869500,
          fechaLimite: DateTime(2026, 8, 30),
          conceptos: const ['PAGO NOMINA AGOSTO DE 2026'],
        );

        expect(fila.banco, '0013');
        expect(fila.celdas[5], '0013');
        expect(fila.identificacion, '1014267058');
      },
    );
  });
}
