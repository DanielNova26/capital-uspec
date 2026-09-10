import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_archivo_plano.dart';

/// Los datos son inventados a propósito: el archivo real trae cédulas, cuentas
/// bancarias y sueldos de personas concretas, y eso no entra al repositorio.
/// Lo que se copia del ejemplo es la FORMA, que es lo que hay que respetar.
void main() {
  PlanoPagoFila fila({
    String identificacion = '1014267058',
    String nombre = 'PERSONA DE PRUEBA UNO',
    String banco = '62',
    String tipoCuenta = '2',
    String cuenta = '111610049888',
    int centavos = 263509500,
    String formaPago = '1',
    DateTime? fechaLimite,
    List<String> conceptos = const ['PAGO NOMINA AGOSTO DE 2026'],
    String email = '',
    String digitoV = '',
    String oficina = '',
  }) => PlanoPagoFila(
    identificacion: identificacion,
    tipoId: '1',
    digitoVerificacion: digitoV,
    nombre: nombre,
    formaPago: formaPago,
    banco: banco,
    tipoCuenta: tipoCuenta,
    numeroCuenta: cuenta,
    codigoOficina: oficina,
    fechaLimite: fechaLimite ?? DateTime(2026, 8, 30),
    importeCentavos: centavos,
    conceptos: conceptos,
    email: email,
  );

  group('códigos con ceros a la izquierda', () {
    test('rellena hasta cuatro dígitos', () {
      // En la hoja el 507 está guardado como número con formato 0000. Si se
      // modelara como int, el archivo saldría con "507" y el banco no
      // reconocería la entidad.
      expect(rellenarCodigoPlano('507'), '0507');
      expect(rellenarCodigoPlano('1'), '0001');
      expect(rellenarCodigoPlano('0'), '0000');
      expect(rellenarCodigoPlano(''), '0000');
    });

    test('nunca recorta un código que ya viene más largo', () {
      // Recortarlo lo convertiría en otro código válido y el pago se iría a
      // otra entidad sin que nada fallara. Que salga largo lo ve la
      // validación; que salga recortado no lo ve nadie.
      expect(rellenarCodigoPlano('12345'), '12345');
    });
  });

  group('fecha límite', () {
    test('va en aaaammdd con forma de pago 1 o 2', () {
      expect(
        fechaLimitePlano(formaPago: '1', fecha: DateTime(2026, 8, 30)),
        '20260830',
      );
      expect(
        fechaLimitePlano(formaPago: '2', fecha: DateTime(2026, 1, 5)),
        '20260105',
      );
    });

    test('con forma de pago 3 van ocho ceros aunque haya fecha', () {
      // Es la regla textual del comentario de la celda en la plantilla.
      expect(
        fechaLimitePlano(formaPago: '3', fecha: DateTime(2026, 8, 30)),
        '00000000',
      );
    });
  });

  group('importe', () {
    test('lleva miles con coma y dos decimales', () {
      expect(importePlano(386869500), '3,868,695.00');
      expect(importePlano(1128000000), '11,280,000.00');
      expect(importePlano(50), '0.50');
    });

    test('el total va sin decimales', () {
      expect(importeTotalPlano(5209654900), '52,096,549');
    });

    test('la suma es exacta porque no pasa por coma flotante', () {
      // 0.1 + 0.2 en double no da 0.3; un lote de 160 sueldos acumula esa
      // deriva y el total de la cabecera deja de cuadrar con el detalle, que
      // es lo primero que revisa el banco.
      final filas = List.generate(3, (_) => fila(centavos: 10));
      expect(totalPlanoPagos(filas), 30);
      expect(importePlano(totalPlanoPagos(filas)), '0.30');
    });
  });

  group('validación', () {
    test('un lote correcto no reporta nada', () {
      expect(validarPlanoPagos([fila()]), isEmpty);
    });

    test('nombra a la persona en cada problema', () {
      // Una lista de 160 líneas con "identificación demasiado larga" y sin
      // decir de quién no sirve para corregir nada.
      final errores = validarPlanoPagos([
        fila(nombre: 'JUANA PEREZ', identificacion: ''),
      ]);

      expect(errores, hasLength(1));
      expect(errores.single.nombre, 'JUANA PEREZ');
      expect(errores.single.toString(), contains('JUANA PEREZ'));
      expect(errores.single.campo, 'Identificación');
    });

    test('devuelve todos los problemas, no solo el primero', () {
      final errores = validarPlanoPagos([
        fila(identificacion: '', nombre: '', cuenta: '', centavos: 0),
      ]);

      expect(errores.length, greaterThanOrEqualTo(4));
      expect(errores.map((e) => e.campo), contains('Importe'));
      expect(errores.map((e) => e.campo), contains('No Cuenta'));
    });

    test('rechaza el nombre que pasa de 36 caracteres', () {
      // Es el límite que impone la validación de la propia hoja del banco.
      final errores = validarPlanoPagos([fila(nombre: 'A' * 37)]);

      expect(errores.single.campo, 'Apellidos y Nombres');
      expect(errores.single.detalle, contains('37'));
    });

    test('rechaza identificaciones y cuentas con puntos o guiones', () {
      expect(
        validarPlanoPagos([fila(identificacion: '1.014.267.058')]).single.campo,
        'Identificación',
      );
      expect(
        validarPlanoPagos([fila(cuenta: '111-610-049')]).single.campo,
        'No Cuenta',
      );
    });

    test('avisa cuando la misma cédula aparece dos veces en el lote', () {
      // Casi siempre es la misma fila pegada dos veces, y son dos
      // transferencias reales si nadie lo mira.
      final errores = validarPlanoPagos([
        fila(identificacion: '1014267058'),
        fila(identificacion: '1014267058'),
      ]);

      expect(errores, hasLength(1));
      expect(errores.single.fila, 1);
      expect(errores.single.detalle, contains('fila 1'));
    });

    test('la forma de pago 1 sin fecha es un error, no ocho ceros', () {
      // Ocho ceros es la marca de "sin fecha límite" y significa otra cosa
      // para el banco: dejarlo pasar cambia la instrucción de pago.
      final errores = validarPlanoPagos([
        PlanoPagoFila(
          identificacion: '1014267058',
          tipoId: '1',
          nombre: 'PERSONA DE PRUEBA',
          formaPago: '1',
          banco: '0013',
          tipoCuenta: '2',
          numeroCuenta: '902027895',
          importeCentavos: 100000,
        ),
      ]);

      expect(errores.single.campo, 'Fecha Limite');
    });

    test('la forma de pago 3 no exige fecha', () {
      expect(
        validarPlanoPagos([
          PlanoPagoFila(
            identificacion: '1014267058',
            tipoId: '1',
            nombre: 'PERSONA DE PRUEBA',
            formaPago: '3',
            banco: '0013',
            tipoCuenta: '2',
            numeroCuenta: '902027895',
            importeCentavos: 100000,
          ),
        ]),
        isEmpty,
      );
    });

    test('el tipo de cuenta solo admite 01 y 02', () {
      expect(validarPlanoPagos([fila(tipoCuenta: '2')]), isEmpty);
      expect(validarPlanoPagos([fila(tipoCuenta: '02')]), isEmpty);
      expect(
        validarPlanoPagos([fila(tipoCuenta: '3')]).single.campo,
        'Tipo Cuenta',
      );
    });

    test('el concepto no pasa de 40 caracteres', () {
      final errores = validarPlanoPagos([
        fila(conceptos: ['B' * 41]),
      ]);

      expect(errores.single.campo, 'Concepto 1');
    });
  });

  group('archivo generado', () {
    test('respeta la forma del ejemplo que el banco ya acepta', () {
      final csv = generarArchivoPlanoCsv([
        fila(
          identificacion: '32763575',
          nombre: 'PERSONA DE PRUEBA UNO',
          banco: '507',
          cuenta: '3246075417',
          centavos: 386869500,
        ),
      ]);
      final lineas = csv.split('\r\n');

      // Cabecera: total en la segunda línea, títulos en la quinta, y la fecha
      // repartida en Año/Mes/Día en la sexta.
      expect(lineas[1], contains('Importe Total:'));
      expect(lineas[1], contains('"3,868,695"'));
      expect(lineas[4], startsWith('Identificación,Tipo Id,Digito V,'));
      expect(lineas[5], contains('Año,Mes,Dia'));

      final pago = lineas[6].split(',');
      expect(pago[5], '0507'); // banco con su cero a la izquierda
      expect(pago[9], '2026');
      expect(pago[10], '08');
      expect(pago[11], '30');
    });

    test('entrecomilla el importe porque lleva comas de miles', () {
      // Sin comillas, "3,868,695.00" se leería como tres columnas y todo lo
      // que va detrás quedaría corrido: el concepto en la casilla del email.
      final csv = generarArchivoPlanoCsv([fila(centavos: 386869500)]);

      expect(csv, contains('"3,868,695.00"'));
    });

    test('todas las filas tienen el mismo número de columnas', () {
      final csv = generarArchivoPlanoCsv([fila(), fila(identificacion: '999')]);
      final anchos = csv
          .split('\r\n')
          .map((l) => l.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)')).length)
          .toSet();

      expect(anchos, hasLength(1));
    });

    test('los conceptos vacíos dejan la casilla vacía, no la corren', () {
      final csv = generarArchivoPlanoCsv([
        fila(conceptos: const ['UNICO CONCEPTO'], email: 'a@b.co'),
      ]);
      final pago = csv
          .split('\r\n')[6]
          .split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)'));

      expect(pago[13], 'UNICO CONCEPTO');
      expect(pago[14], '');
      expect(pago[15], '');
      expect(pago[16], '');
      expect(pago[17], 'a@b.co');
    });
  });
}
