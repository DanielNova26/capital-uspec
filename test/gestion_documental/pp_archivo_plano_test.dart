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

  group('de la planilla firmada al plano', () {
    Map<String, dynamic> filaExcel(Map<String, String> extras, double valor) =>
        {'valor': valor, 'extras': extras};

    test('lee el NIT, la cuenta y el banco de la planilla', () {
      // La planilla ya trae todo lo que el banco necesita: no hace falta el
      // maestro de cuentas, que es para la nómina.
      final filas = filasPlanoDesdePlanilla(
        [
          filaExcel(const {
            'NIT': '860.046.201',
            'DV': '2',
            'PROVEEDOR': 'PROVEEDOR DE PRUEBA',
            'N CUENTA': '019068402',
            'CTE': 'X',
            'BANCO': '23',
          }, 20580830),
        ],
        fechaLimite: DateTime(2026, 9, 4),
        concepto: 'ANTICIPO',
      );

      expect(filas.single.identificacion, '860046201'); // sin puntos
      expect(filas.single.celdas[2], '0002'); // relleno a cuatro
      expect(filas.single.tipoCuenta, '1'); // CTE marcada
      expect(filas.single.celdas[5], '0023'); // banco relleno
      expect(filas.single.importeCentavos, 2058083000);
      expect(filas.single.conceptos, ['ANTICIPO']);
    });

    test('la X va en AHO y el tipo de cuenta es 02', () {
      final filas = filasPlanoDesdePlanilla([
        filaExcel(const {
          'NIT': '890319193',
          'No Cuenta': '06049670476',
          'AHO': 'x',
          'BANCO': '7',
        }, 14158178),
      ], fechaLimite: DateTime(2026, 9, 4));

      expect(filas.single.tipoCuenta, '2');
      expect(filas.single.celdas[6], '0002');
    });

    test('acepta los nombres de columna que use el Excel', () {
      // Las cabeceras las escriben personas y cambian de un archivo a otro.
      final filas = filasPlanoDesdePlanilla([
        filaExcel(const {
          'identificacion': '900123456',
          'numero_cuenta': '1234',
          'beneficiario': 'ALGUIEN SAS',
          'tipo de cuenta': 'AHORROS',
          'codigo banco': '13',
        }, 1000),
      ], fechaLimite: DateTime(2026, 9, 4));

      expect(filas.single.nombre, 'ALGUIEN SAS');
      expect(filas.single.numeroCuenta, '1234');
      expect(filas.single.tipoCuenta, '2');
    });

    test('una fila incompleta entra y la validación dice de quién es', () {
      // Omitirla produciría un archivo que cuadra consigo mismo pero no con la
      // planilla firmada.
      final filas = filasPlanoDesdePlanilla([
        filaExcel(const {'PROVEEDOR': 'SIN CUENTA SAS'}, 500),
      ], fechaLimite: DateTime(2026, 9, 4));

      expect(filas, hasLength(1));
      final errores = validarPlanoPagos(filas);
      expect(errores, isNotEmpty);
      expect(errores.first.toString(), contains('SIN CUENTA SAS'));
    });

    test('un NIT largo se marca como tipo 2', () {
      final filas = filasPlanoDesdePlanilla([
        filaExcel(const {'NIT': '12345678901', 'N CUENTA': '1'}, 100),
      ], fechaLimite: DateTime(2026, 9, 4));

      expect(filas.single.tipoId, '2');
    });
  });

  group('codificación del archivo', () {
    test('conserva tildes y eñes, que sí existen en latin1', () {
      expect(aLatin1Seguro('NUTRICIÓN Y COMPAÑÍA'), 'NUTRICIÓN Y COMPAÑÍA');
    });

    test('cambia lo que latin1 no sabe escribir', () {
      // Comillas y guiones que alguien pegó desde Word.
      expect(aLatin1Seguro('PAGO – “X”'), 'PAGO - "X"');
      expect(aLatin1Seguro('emoji \u{1F600}'), 'emoji ?');
    });
  });

  group('el maestro completa lo que al archivo le falta', () {
    const maestro = {
      '860046201': DatosBeneficiario(
        nombre: 'PROVEEDOR DEL MAESTRO',
        banco: '0013',
        tipoCuenta: '2',
        numeroCuenta: '999888777',
        digitoVerificacion: '5',
      ),
    };

    PlanoPagoFila filaDeArchivo({
      String banco = '',
      String cuenta = '',
      String nombre = '',
    }) => PlanoPagoFila(
      identificacion: '860046201',
      tipoId: '2',
      nombre: nombre,
      banco: banco,
      tipoCuenta: '',
      numeroCuenta: cuenta,
      importeCentavos: 100000,
      fechaLimite: DateTime(2026, 9, 4),
    );

    test('rellena la cuenta y el banco que el archivo no traía', () {
      // Es lo que evita que generar el plano sea un trabajo manual.
      final completadas = completarConMaestro([filaDeArchivo()], maestro);

      expect(completadas.single.numeroCuenta, '999888777');
      expect(completadas.single.banco, '0013');
      expect(completadas.single.nombre, 'PROVEEDOR DEL MAESTRO');
      expect(completadas.single.tipoCuenta, '2');
    });

    test('el archivo manda sobre el maestro', () {
      // Puede ser un pago excepcional a otra cuenta: sustituirlo por "lo de
      // siempre" mandaria el dinero a donde el archivo no dijo.
      final completadas = completarConMaestro([
        filaDeArchivo(banco: '0007', cuenta: '111', nombre: 'OTRO NOMBRE'),
      ], maestro);

      expect(completadas.single.numeroCuenta, '111');
      expect(completadas.single.banco, '0007');
      expect(completadas.single.nombre, 'OTRO NOMBRE');
    });

    test('un beneficiario que no está en el maestro se queda igual', () {
      final fila = PlanoPagoFila(
        identificacion: '999999999',
        tipoId: '1',
        nombre: 'DESCONOCIDO',
        banco: '',
        tipoCuenta: '',
        numeroCuenta: '',
        importeCentavos: 5000,
        fechaLimite: DateTime(2026, 9, 4),
      );
      final completadas = completarConMaestro([fila], maestro);

      // No se inventa nada: la validación dirá qué le falta y de quién es.
      expect(completadas.single.numeroCuenta, isEmpty);
      expect(validarPlanoPagos(completadas), isNotEmpty);
    });

    test('dice a quién hay que dar de alta antes de reintentar', () {
      final faltan = beneficiariosSinMaestro([
        filaDeArchivo(),
        PlanoPagoFila(
          identificacion: '999999999',
          tipoId: '1',
          nombre: 'NUEVO',
          banco: '',
          tipoCuenta: '',
          numeroCuenta: '',
          importeCentavos: 1,
          fechaLimite: DateTime(2026, 9, 4),
        ),
      ], maestro);

      expect(faltan, ['999999999']);
    });

    test('sin maestro las filas pasan tal cual', () {
      final completadas = completarConMaestro([filaDeArchivo(cuenta: '5')], {});

      expect(completadas.single.numeroCuenta, '5');
    });
  });

  group('cadena completa: del Excel guardado al CSV', () {
    // La forma es la de un consolidado real (dos proveedores, uno en corriente
    // y otro en ahorros); los valores son inventados.
    final filasGuardadas = [
      {
        'rowIndex': 0,
        'valor': 20580830.0,
        'extras': {
          'No': '804',
          'NIT': '900111222',
          'DV': '2',
          'PROVEEDOR': 'PROVEEDOR UNO SAS',
          'N Factura /Orden de Compra': 'PAGO FACT FE-000001',
          'N CUENTA': '019068402',
          'CTE': 'X',
          'AHO': '',
          'BANCO': '23',
        },
      },
      {
        'rowIndex': 1,
        'valor': 14158178.0,
        'extras': {
          'No': '804',
          'NIT': '900333444',
          'DV': '3',
          'PROVEEDOR': 'PROVEEDOR DOS SAS',
          'N Factura /Orden de Compra': 'PAGO FACT 04IZ-000002',
          'N CUENTA': '06049670476',
          'CTE': '',
          'AHO': 'x',
          'BANCO': '7',
        },
      },
    ];

    test('sale el archivo que el banco espera, sin volver a subir nada', () {
      final filas = filasPlanoDesdePlanilla(
        filasGuardadas,
        fechaLimite: DateTime(2026, 9, 4),
        concepto: 'ANTICIPO ALIMENTAR CAPITAL',
      );

      // Nada que el banco vaya a rechazar.
      expect(validarPlanoPagos(filas), isEmpty);

      final lineas = generarArchivoPlanoCsv(filas).split('\r\n');
      final campos = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');

      // El total de la cabecera cuadra con la suma de las dos filas.
      expect(lineas[1], contains('"34,739,008"'));

      final uno = lineas[6].split(campos);
      expect(uno[0], '900111222');
      expect(uno[2], '0002'); // DV relleno
      expect(uno[5], '0023'); // banco relleno
      expect(uno[6], '0001'); // CTE -> corriente
      expect(uno[9], '2026');
      expect(uno[10], '09');
      expect(uno[11], '04');
      expect(uno[12], '"20,580,830.00"');
      expect(uno[13], 'ANTICIPO ALIMENTAR CAPITAL');

      final dos = lineas[7].split(campos);
      expect(dos[5], '0007'); // banco relleno
      expect(dos[6], '0002'); // AHO -> ahorros
    });

    test('el maestro rellena una fila a la que le falta la cuenta', () {
      // El caso que hace que esto no sea un trabajo manual: el Excel trae el
      // pago y el maestro pone los datos bancarios del beneficiario conocido.
      final sinCuenta = [
        {
          'valor': 500000.0,
          'extras': {'NIT': '900111222', 'PROVEEDOR': 'PROVEEDOR UNO SAS'},
        },
      ];
      final filas = filasPlanoDesdePlanilla(
        sinCuenta,
        fechaLimite: DateTime(2026, 9, 4),
        concepto: 'ANTICIPO',
      );
      expect(validarPlanoPagos(filas), isNotEmpty); // sin maestro, falla

      final completadas = completarConMaestro(filas, const {
        '900111222': DatosBeneficiario(
          nombre: 'PROVEEDOR UNO SAS',
          banco: '0023',
          tipoCuenta: '1',
          numeroCuenta: '019068402',
          digitoVerificacion: '2',
        ),
      });

      expect(validarPlanoPagos(completadas), isEmpty);
      expect(completadas.single.numeroCuenta, '019068402');
    });
  });
}
