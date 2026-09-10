/// Archivo plano de pagos para el banco.
///
/// Hoy lo arma Tesorería a mano en una macro de Excel
/// ("ARCHIVO PLANO COTA ADMINISTRATIVA"). Talento Humano pasa la información y
/// alguien la transcribe fila por fila; es de las cosas que más tiempo consumen
/// y donde un cero de menos manda un sueldo a la cuenta equivocada.
///
/// Este archivo es **solo la regla**: modelo, validación y rendida del texto.
/// No sabe de Firestore ni de widgets, para poder probarlo entero sin levantar
/// nada. Quien lo llame se encarga de traer las personas y de guardar o
/// descargar el resultado.
///
/// ## De dónde sale la especificación
///
/// De la propia plantilla del banco, no de una suposición: los comentarios de
/// las celdas de la hoja `Pagos` y sus validaciones de datos.
///
/// - `Fecha Limite`: "Si la forma de pago es 1 o 2, formato aaaammdd. Si la
///   forma de pago es 3, ingrese 8 ceros: 00000000".
/// - `Concepto 1`: "Concepto del pago (máximo 40 caracteres)".
/// - `Banco`: "Código ACH de cada banco".
/// - `Cod Oficina`: "Código de cada oficina".
/// - `Apellidos y Nombres` y `E-mail`: la validación de la hoja exige
///   `LEN <= 36`.
/// - `Identificación`: `LEN <= 15`.
/// - `Tipo Cuenta`: lista `01,02`.
///
/// ## Por qué todo es texto y no números
///
/// En la hoja, `Banco`, `Tipo Cuenta`, `Forma Pago`, `Dígito V` y `Cod Oficina`
/// están guardados como números con formato `0000`: el 507 se **ve** como
/// "0507" y el 1 como "0001". El cero de la izquierda solo existe al pintarlo.
/// Si esto se modelara con `int`, el archivo saldría con "507" y el banco no
/// reconocería la entidad. Aquí se guardan como texto ya rellenado, que es lo
/// que el banco recibe.
///
/// El importe tampoco es `double`: es un entero de centavos. Un sueldo sumado
/// en coma flotante deja de cuadrar con el total por unos centavos, y el total
/// es lo primero que revisa el banco.
library;

/// Ancho de los códigos que el banco espera rellenados con ceros.
const int kPlanoAnchoCodigo = 4;

/// Tope de caracteres de cada campo, tal como los valida la hoja del banco.
const int kPlanoMaxIdentificacion = 15;
const int kPlanoMaxNombre = 36;
const int kPlanoMaxConcepto = 40;
const int kPlanoMaxEmail = 36;

/// Cuántos conceptos admite una fila.
const int kPlanoMaxConceptos = 4;

/// Forma de pago que NO lleva fecha límite (el banco espera ocho ceros).
const String kPlanoFormaPagoSinFecha = '3';

/// Rellena un código con ceros a la izquierda hasta [ancho].
///
/// Si ya viene más largo se devuelve intacto: recortarlo cambiaría el código
/// del banco por otro que existe, y un pago iría a la entidad equivocada sin
/// que nada fallara. Que salga largo lo detecta la validación; que salga
/// recortado no lo detecta nadie.
String rellenarCodigoPlano(String valor, {int ancho = kPlanoAnchoCodigo}) {
  final limpio = valor.trim();
  if (limpio.isEmpty) return ''.padLeft(ancho, '0');
  return limpio.length >= ancho ? limpio : limpio.padLeft(ancho, '0');
}

/// Fecha límite en el formato del banco: `aaaammdd`, u ocho ceros.
///
/// La regla es del comentario de la celda `Fecha Limite`: con forma de pago 3
/// no hay fecha, y el campo va en ceros. Devolver una fecha ahí, o dejarlo
/// vacío, son dos maneras distintas de que el banco rechace el lote entero.
String fechaLimitePlano({required String formaPago, DateTime? fecha}) {
  if (formaPago.trim() == kPlanoFormaPagoSinFecha) return '00000000';
  if (fecha == null) return '00000000';
  final anio = fecha.year.toString().padLeft(4, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  final dia = fecha.day.toString().padLeft(2, '0');
  return '$anio$mes$dia';
}

/// Importe en el formato de la plantilla: miles con coma y dos decimales.
///
/// [centavos] es entero a propósito (ver la nota de la cabecera).
String importePlano(int centavos, {bool conSeparadorDeMiles = true}) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final enteros = (abs ~/ 100).toString();
  final decimales = (abs % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < enteros.length; i++) {
    if (conSeparadorDeMiles && i > 0 && (enteros.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(enteros[i]);
  }
  return '${negativo ? '-' : ''}$buffer.$decimales';
}

/// Total de la cabecera. Va sin decimales, igual que en la plantilla.
String importeTotalPlano(int centavos, {bool conSeparadorDeMiles = true}) {
  final enteros = (centavos.abs() ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < enteros.length; i++) {
    if (conSeparadorDeMiles && i > 0 && (enteros.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(enteros[i]);
  }
  return '${centavos < 0 ? '-' : ''}$buffer';
}

/// Un beneficiario y su pago: una línea del archivo.
class PlanoPagoFila {
  /// Cédula o NIT. Sin puntos ni guiones.
  final String identificacion;

  /// Tipo de documento según el banco (1 = cédula en los lotes actuales).
  final String tipoId;

  /// Dígito de verificación. Solo lo llevan los NIT; en las cédulas va en
  /// ceros, y así viene en los lotes que Tesorería ya envió.
  final String digitoVerificacion;

  /// Apellidos y nombres, como los quiere el banco.
  final String nombre;

  /// 1 y 2 llevan fecha límite; 3 no.
  final String formaPago;

  /// Código ACH del banco del beneficiario.
  final String banco;

  /// 01 / 02.
  final String tipoCuenta;

  final String numeroCuenta;

  /// Código de oficina. "0000" cuando no aplica.
  final String codigoOficina;

  /// Se ignora si [formaPago] es 3.
  final DateTime? fechaLimite;

  /// Pesos * 100. Ver la nota de la cabecera sobre por qué no es `double`.
  final int importeCentavos;

  /// Hasta cuatro, de 40 caracteres cada uno.
  final List<String> conceptos;

  /// Opcional.
  final String email;

  const PlanoPagoFila({
    required this.identificacion,
    required this.tipoId,
    required this.nombre,
    required this.banco,
    required this.tipoCuenta,
    required this.numeroCuenta,
    required this.importeCentavos,
    this.digitoVerificacion = '',
    this.formaPago = '1',
    this.codigoOficina = '',
    this.fechaLimite,
    this.conceptos = const [],
    this.email = '',
  });

  /// Los campos ya rellenados y en el orden del archivo.
  List<String> get celdas => [
    identificacion.trim(),
    tipoId.trim(),
    rellenarCodigoPlano(digitoVerificacion),
    nombre.trim(),
    rellenarCodigoPlano(formaPago),
    rellenarCodigoPlano(banco),
    rellenarCodigoPlano(tipoCuenta),
    numeroCuenta.trim(),
    rellenarCodigoPlano(codigoOficina),
    // La hoja parte la fecha en tres columnas para que una persona la lea; el
    // campo del banco es uno solo de ocho caracteres (ver fechaLimitePlano).
    ...(() {
      final f = fechaLimitePlano(formaPago: formaPago, fecha: fechaLimite);
      return [f.substring(0, 4), f.substring(4, 6), f.substring(6, 8)];
    })(),
    importePlano(importeCentavos),
    for (var i = 0; i < kPlanoMaxConceptos; i++)
      i < conceptos.length ? conceptos[i].trim() : '',
    email.trim(),
  ];
}

/// Un problema encontrado en una fila, con nombre y apellido.
///
/// No es un `String` suelto porque el error hay que poder mostrarlo junto a la
/// persona: un lote de 160 líneas con el mensaje "identificación demasiado
/// larga" y sin decir de quién no sirve para corregir nada.
class PlanoPagoError {
  /// 0-based dentro de la lista de filas.
  final int fila;
  final String identificacion;
  final String nombre;
  final String campo;
  final String detalle;

  const PlanoPagoError({
    required this.fila,
    required this.identificacion,
    required this.nombre,
    required this.campo,
    required this.detalle,
  });

  @override
  String toString() =>
      'Fila ${fila + 1} · ${nombre.isEmpty ? identificacion : nombre} · '
      '$campo: $detalle';
}

/// Revisa un lote contra las reglas de la plantilla del banco.
///
/// Devuelve **todos** los problemas, no el primero. Quien corrige esto trabaja
/// con una lista de gente delante: pararse en el primer error obliga a repetir
/// la generación una vez por cada dato malo.
List<PlanoPagoError> validarPlanoPagos(List<PlanoPagoFila> filas) {
  final errores = <PlanoPagoError>[];
  final identificacionesVistas = <String, int>{};

  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    void error(String campo, String detalle) => errores.add(
      PlanoPagoError(
        fila: i,
        identificacion: f.identificacion.trim(),
        nombre: f.nombre.trim(),
        campo: campo,
        detalle: detalle,
      ),
    );

    final id = f.identificacion.trim();
    if (id.isEmpty) {
      error('Identificación', 'está vacía');
    } else if (id.length > kPlanoMaxIdentificacion) {
      error(
        'Identificación',
        'tiene ${id.length} caracteres y el banco admite '
            '$kPlanoMaxIdentificacion',
      );
    } else if (!RegExp(r'^\d+$').hasMatch(id)) {
      error('Identificación', 'trae puntos, guiones o letras');
    }

    // El banco paga por cuenta, no por persona, pero repetir a alguien en el
    // mismo lote casi siempre es la misma fila pegada dos veces. Se avisa; no
    // se bloquea, porque una segunda transferencia legítima existe.
    if (id.isNotEmpty) {
      final anterior = identificacionesVistas[id];
      if (anterior != null) {
        error(
          'Identificación',
          'ya aparece en la fila ${anterior + 1} de este mismo lote',
        );
      } else {
        identificacionesVistas[id] = i;
      }
    }

    final nombre = f.nombre.trim();
    if (nombre.isEmpty) {
      error('Apellidos y Nombres', 'está vacío');
    } else if (nombre.length > kPlanoMaxNombre) {
      error(
        'Apellidos y Nombres',
        'tiene ${nombre.length} caracteres y el banco admite $kPlanoMaxNombre',
      );
    }

    final cuenta = f.numeroCuenta.trim();
    if (cuenta.isEmpty) {
      error('No Cuenta', 'está vacío');
    } else if (!RegExp(r'^\d+$').hasMatch(cuenta)) {
      error('No Cuenta', 'trae guiones, espacios o letras');
    }

    final banco = f.banco.trim();
    if (banco.isEmpty) {
      error('Banco', 'está vacío');
    } else if (rellenarCodigoPlano(banco).length > kPlanoAnchoCodigo) {
      error(
        'Banco',
        'el código ACH "$banco" no cabe en $kPlanoAnchoCodigo dígitos',
      );
    }

    final tipoCuenta = f.tipoCuenta.trim().replaceFirst(RegExp(r'^0+'), '');
    if (tipoCuenta != '1' && tipoCuenta != '2') {
      error('Tipo Cuenta', 'debe ser 01 o 02, y llegó "${f.tipoCuenta}"');
    }

    final forma = f.formaPago.trim().replaceFirst(RegExp(r'^0+'), '');
    if (!['1', '2', '3'].contains(forma)) {
      error('Forma Pago', 'debe ser 1, 2 o 3, y llegó "${f.formaPago}"');
    } else if (forma != kPlanoFormaPagoSinFecha && f.fechaLimite == null) {
      // Con forma 1 o 2 el banco espera aaaammdd. Sin fecha saldrían ocho
      // ceros, que es la marca de "sin fecha límite" y significa otra cosa.
      error(
        'Fecha Limite',
        'la forma de pago $forma exige fecha y no se indicó ninguna',
      );
    }

    if (f.importeCentavos <= 0) {
      error('Importe', 'debe ser mayor que cero');
    }

    if (f.conceptos.length > kPlanoMaxConceptos) {
      error(
        'Conceptos',
        'son ${f.conceptos.length} y el archivo admite $kPlanoMaxConceptos',
      );
    }
    for (var c = 0; c < f.conceptos.length && c < kPlanoMaxConceptos; c++) {
      final concepto = f.conceptos[c].trim();
      if (concepto.length > kPlanoMaxConcepto) {
        error(
          'Concepto ${c + 1}',
          'tiene ${concepto.length} caracteres y el banco admite '
              '$kPlanoMaxConcepto',
        );
      }
    }

    final email = f.email.trim();
    if (email.length > kPlanoMaxEmail) {
      error(
        'E-mail',
        'tiene ${email.length} caracteres y el banco admite $kPlanoMaxEmail',
      );
    }
  }

  return errores;
}

/// Suma del lote, en centavos.
int totalPlanoPagos(List<PlanoPagoFila> filas) =>
    filas.fold(0, (suma, f) => suma + f.importeCentavos);

/// Escapa un campo para CSV: comillas dobles si trae coma, comilla o salto.
String _campoCsv(String valor) {
  if (!valor.contains(',') &&
      !valor.contains('"') &&
      !valor.contains('\n') &&
      !valor.contains('\r')) {
    return valor;
  }
  return '"${valor.replaceAll('"', '""')}"';
}

/// Número de columnas de la hoja `Pagos`, de `Identificación` a `E-mail`.
const int _kColumnas = 18;

/// Arma el archivo tal como lo entrega hoy la macro de Tesorería.
///
/// Se reproduce la forma exacta del ejemplo recibido —cabecera con el importe
/// total, las dos filas de títulos y luego los pagos— porque ese archivo es el
/// único del que consta que el banco lo acepta. Cualquier "mejora" del formato
/// se descubre el día del pago.
String generarArchivoPlanoCsv(List<PlanoPagoFila> filas) {
  String linea(List<String> celdas) {
    final fila = List<String>.filled(_kColumnas, '');
    for (var i = 0; i < celdas.length && i < _kColumnas; i++) {
      fila[i] = celdas[i];
    }
    return fila.map(_campoCsv).join(',');
  }

  final vacia = List<String>.filled(_kColumnas, '');
  final total = List<String>.filled(_kColumnas, '');
  total[9] = 'Importe Total:';
  total[12] = importeTotalPlano(totalPlanoPagos(filas));

  final grupos = List<String>.filled(_kColumnas, '');
  grupos[0] = 'DATOS GENERALES DEL BENEFICIARIO';
  grupos[9] = 'DATOS OBLIGATORIOS DEL PAGO';
  grupos[14] = 'CONCEPTOS ADICIONALES';
  grupos[17] = 'DATO OPCIONAL';

  const titulos = [
    'Identificación',
    'Tipo Id',
    'Digito V',
    'Apellidos y Nombres',
    'Forma Pago',
    'Banco',
    'Tipo Cuenta',
    'No Cuenta',
    'Cod Oficina',
    'Fecha Limite',
    '',
    '',
    'Importe',
    'Concepto1',
    'Concepto 2',
    'Concepto 3',
    'Concepto 4',
    'E-mail',
  ];

  final subtitulos = List<String>.filled(_kColumnas, '');
  subtitulos[9] = 'Año';
  subtitulos[10] = 'Mes';
  subtitulos[11] = 'Dia';

  return [
    linea(vacia),
    linea(total),
    linea(vacia),
    linea(grupos),
    linea(titulos),
    linea(subtitulos),
    for (final f in filas) linea(f.celdas),
  ].join('\r\n');
}

// ─────────────────────────────────────────────────────────────────────────────
// De una planilla firmada al archivo plano
// ─────────────────────────────────────────────────────────────────────────────

/// Busca un valor en `extras` probando varios nombres de columna.
///
/// El Excel lo llenan personas y las cabeceras cambian: "No Cuenta", "N CUENTA",
/// "numero_cuenta". Se buscan todas las formas conocidas en vez de exigir una.
String _extra(Map<String, String> extras, List<String> alias) {
  String limpiar(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  final normalizados = {
    for (final e in extras.entries) limpiar(e.key): e.value,
  };
  for (final a in alias) {
    final v = normalizados[limpiar(a)];
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// Deja solo los dígitos. Los NIT vienen con puntos y guiones del Excel.
String soloDigitos(String valor) => valor.replaceAll(RegExp(r'[^0-9]'), '');

/// Tipo de cuenta a partir de las columnas CTE / AHO de la planilla.
///
/// En el papel se marca con una X en una de las dos columnas, no con un número.
/// Corriente = 01, Ahorros = 02, que es lo que espera el banco.
String tipoCuentaDesdePlanilla({
  required String marcaCorriente,
  required String marcaAhorros,
  String valorDirecto = '',
}) {
  final directo = valorDirecto.trim().toUpperCase();
  if (directo.isNotEmpty) {
    if (directo.startsWith('C')) return '1';
    if (directo.startsWith('A')) return '2';
    final soloNum = directo.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloNum.isNotEmpty) return soloNum;
  }
  if (marcaCorriente.trim().isNotEmpty) return '1';
  if (marcaAhorros.trim().isNotEmpty) return '2';
  return '';
}

/// Convierte las filas guardadas de una planilla en líneas del archivo plano.
///
/// La planilla ya trae **todo lo que el banco necesita** —NIT, dígito de
/// verificación, beneficiario, cuenta, si es corriente o de ahorros, banco y
/// valor—, así que no hace falta el maestro de cuentas para este caso: el
/// maestro sirve para la nómina, donde el beneficiario es una persona.
///
/// [importeEnPesos] indica si los valores vienen en pesos (lo normal) o ya en
/// centavos.
List<PlanoPagoFila> filasPlanoDesdePlanilla(
  List<Map<String, dynamic>> filasRows, {
  required DateTime? fechaLimite,
  String concepto = '',
  String formaPago = '1',
  bool importeEnPesos = true,
}) {
  final salida = <PlanoPagoFila>[];
  for (final raw in filasRows) {
    final extras =
        (raw['extras'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
        ) ??
        const <String, String>{};

    final nit = soloDigitos(
      _extra(extras, const ['nit', 'identificacion', 'documento', 'cedula']),
    );
    final nombre = _extra(extras, const [
      'proveedor',
      'beneficiario',
      'apellidos y nombres',
      'nombre',
    ]);
    final cuenta = soloDigitos(
      _extra(extras, const [
        'no cuenta',
        'n cuenta',
        'numero cuenta',
        'cuenta',
      ]),
    );
    final valorRaw = raw['valor'];
    final pesos = valorRaw is num
        ? valorRaw.toDouble()
        : double.tryParse(
                _extra(extras, const [
                  'valor a pagar',
                  'valor',
                ]).replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', ''),
              ) ??
              0;

    // Las filas sin cuenta o sin valor no se saltan en silencio: entran, y
    // `validarPlanoPagos` dirá de quién es el problema. Omitirlas produciría un
    // archivo que cuadra consigo mismo pero no con la planilla firmada.
    salida.add(
      PlanoPagoFila(
        identificacion: nit,
        tipoId: nit.length > 10 ? '2' : '1',
        digitoVerificacion: soloDigitos(
          _extra(extras, const ['dv', 'digito v', 'digito verificacion']),
        ),
        nombre: nombre,
        formaPago: formaPago,
        banco: soloDigitos(_extra(extras, const ['banco', 'codigo banco'])),
        tipoCuenta: tipoCuentaDesdePlanilla(
          marcaCorriente: _extra(extras, const ['cte', 'corriente']),
          marcaAhorros: _extra(extras, const ['aho', 'ahorros']),
          valorDirecto: _extra(extras, const ['tipo de cuenta', 'tipo cuenta']),
        ),
        numeroCuenta: cuenta,
        fechaLimite: fechaLimite,
        importeCentavos: importeEnPesos ? (pesos * 100).round() : pesos.round(),
        conceptos: concepto.trim().isEmpty ? const [] : [concepto.trim()],
      ),
    );
  }
  return salida;
}

/// Reemplaza lo que latin1 no sabe escribir, sin romper la codificación.
///
/// El cargador del banco es de los que no entienden UTF-8: un nombre con tilde
/// mal codificado es una fila rechazada. Las tildes y la eñe **sí** existen en
/// latin1 y se conservan; lo que no existe —comillas tipográficas, guiones
/// largos, emojis que alguien pegó desde Word— se cambia por su equivalente
/// simple en vez de reventar el archivo entero.
String aLatin1Seguro(String texto) {
  const equivalencias = {
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '–': '-',
    '—': '-',
    '…': '...',
    ' ': ' ',
  };
  final buffer = StringBuffer();
  for (final rune in texto.runes) {
    final char = String.fromCharCode(rune);
    final reemplazo = equivalencias[char];
    if (reemplazo != null) {
      buffer.write(reemplazo);
    } else if (rune <= 0xFF) {
      buffer.write(char);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}
