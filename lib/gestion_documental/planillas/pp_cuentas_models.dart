/// Maestro de datos bancarios de **beneficiarios de pago**.
///
/// No es un maestro de nómina. Un beneficiario es cualquiera a quien la empresa
/// le paga: un empleado por cédula o un proveedor por NIT. La nómina y los
/// anticipos a proveedores usan el mismo archivo plano y las mismas columnas,
/// así que separarlos en dos maestros obligaría a mantener dos veces la misma
/// tabla y a que el generador supiera de cuál leer.
///
/// Arrancó siendo la hoja `CUENTAS` del Excel de Tesorería. Vive **aparte de
/// `TBL_USUARIOS`** a propósito: el número de cuenta no puede quedar en el
/// mismo documento que el nombre y la foto, porque ese documento lo lee media
/// aplicación para pintar avatares. Separarlo es lo que permite que la regla de
/// Firestore sea distinta.
///
/// ## Quién ve qué
///
/// Tesorería trabaja con el maestro completo. Talento Humano registra **en qué
/// banco** está la persona —que es el dato que ellos reciben cuando alguien
/// entra o cambia de banco— y no ve el número de cuenta. No es desconfianza: es
/// que el número de cuenta no le hace falta a Talento Humano para nada, y un
/// dato que no se necesita no se muestra.
///
/// ## Por qué el código de banco es texto y se normaliza siempre
///
/// En la hoja real, el mismo banco aparece escrito de dos formas: `0013` y
/// `13`, `0507` y `507`, `0809` y `809`. Son 21 valores distintos para 14
/// bancos, porque unas celdas están guardadas como texto y otras como número
/// con formato `0000`. Comparar `bancoCodigo == '0013'` deja fuera a media
/// plantilla del BBVA. Todo entra por [normalizarCodigoBanco].
///
/// Es el mismo problema de los ids de área en `core/area_directory.dart`, y se
/// resuelve igual: una sola puerta de entrada.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'pp_archivo_plano.dart';

/// Colección del maestro, **sin el número de cuenta**.
///
/// Nombre, banco, tipo y forma de pago. La lee Talento Humano y Tesorería.
const String kCuentasBancariasCol = 'TBL_PAGOS_BENEFICIARIOS';

/// Colección aparte donde vive **solo el número de cuenta**.
///
/// ## Por qué son dos colecciones y no dos campos
///
/// **Firestore no tiene seguridad por campo.** Una regla decide si se puede
/// leer un documento entero, no una parte. Si Talento Humano puede leer el
/// documento para ver el banco, puede leer el número de cuenta con él, y el
/// enmascarado de la pantalla no lo impide: basta con abrir la consola.
///
/// La única forma de que "TH ve el banco y no la cuenta" sea cierta de verdad
/// —y no una cortesía de la interfaz— es que el número esté en otro documento
/// con otra regla. De ahí el corte.
///
/// El id es el mismo en las dos, así que una cuenta y su número se emparejan
/// sin buscar nada.
const String kCuentasNumeroCol = 'TBL_PAGOS_BENEFICIARIOS_CUENTA';

/// Rol de Talento Humano para este maestro.
///
/// `PpRoles` describe el flujo de firmas de las planillas en PDF, que es otro
/// asunto; aquí solo hace falta distinguir quién toca el número de cuenta.
const String kCuentaRolTalentoHumano = 'talento_humano';
const String kCuentaRolTesoreria = 'tesoreria';
const String kCuentaRolAdminDoc = 'admin_doc';
const String kCuentaRolDesarrollador = 'desarrollador';

/// Quién puede ver el número de cuenta completo.
const Set<String> kCuentaRolesVenNumero = {
  kCuentaRolTesoreria,
  kCuentaRolAdminDoc,
  kCuentaRolDesarrollador,
};

/// Quién puede escribir el número de cuenta.
const Set<String> kCuentaRolesEditanNumero = {
  kCuentaRolTesoreria,
  kCuentaRolAdminDoc,
  kCuentaRolDesarrollador,
};

/// Quién puede escribir el banco.
///
/// Talento Humano entra aquí y **solo** aquí: es el dato que ellos reciben del
/// empleado. Tesorería también puede, porque es quien corrige cuando un pago
/// rebota.
const Set<String> kCuentaRolesEditanBanco = {
  kCuentaRolTalentoHumano,
  kCuentaRolTesoreria,
  kCuentaRolAdminDoc,
  kCuentaRolDesarrollador,
};

bool puedeVerNumeroCuenta(String rol) => kCuentaRolesVenNumero.contains(rol);
bool puedeEditarNumeroCuenta(String rol) =>
    kCuentaRolesEditanNumero.contains(rol);
bool puedeEditarBancoCuenta(String rol) =>
    kCuentaRolesEditanBanco.contains(rol);

/// Deja a la vista los últimos [visibles] dígitos y tapa el resto.
///
/// Para quien no puede ver el número. No se devuelve vacío porque Talento
/// Humano necesita saber si la persona **tiene** cuenta registrada: un campo en
/// blanco y un campo oculto se ven igual y llevan a preguntar por algo que ya
/// está.
String enmascararNumeroCuenta(String numero, {int visibles = 4}) {
  final limpio = numero.trim();
  if (limpio.isEmpty) return '';
  if (limpio.length <= visibles) return '•' * limpio.length;
  final cola = limpio.substring(limpio.length - visibles);
  return '${'•' * (limpio.length - visibles)}$cola';
}

/// Normaliza el código ACH del banco a cuatro dígitos.
String normalizarCodigoBanco(String codigo) => rellenarCodigoPlano(codigo);

/// Id del documento en el maestro.
///
/// Lleva la empresa además de la identificación porque el permiso es por
/// empresa: la Tesorería de una no debe leer las cuentas de los beneficiarios
/// de la otra. El precio es que alguien que trabaja —o factura— en las dos
/// queda con dos registros y hay que actualizar ambos si cambia de banco; se
/// prefiere ese trabajo a que un maestro global quede legible para todas las
/// tesorerías.
///
/// La identificación es la cédula de un empleado o el NIT de un proveedor, sin
/// puntos ni guiones: es la misma clave con la que llegan las filas del Excel.
String cuentaBancariaDocId(String empresaId, String cedula) =>
    '${empresaId}_${cedula.trim()}';

/// Datos bancarios de una persona, tal como los pide el archivo plano.
class CuentaBancaria {
  final String cedula;
  final String empresaId;

  /// Tipo de documento del banco. 1 = cédula en todos los lotes actuales.
  final String tipoId;
  final String digitoVerificacion;

  /// Apellidos y nombres como los quiere el banco (tope de 36 caracteres).
  final String nombre;

  final String formaPago;

  /// Código ACH, siempre normalizado a cuatro dígitos.
  final String bancoCodigo;

  final String tipoCuenta;
  final String numeroCuenta;
  final String codigoOficina;
  final String email;

  /// Quién tocó por última vez el número de cuenta, y cuándo.
  ///
  /// Se guarda aparte de `updatedAt` porque cambiar el banco y cambiar el
  /// número no son lo mismo: al segundo se le sigue el rastro.
  final String? numeroActualizadoPor;
  final Timestamp? numeroActualizadoEn;

  final String? actualizadoPor;
  final Timestamp? updatedAt;

  CuentaBancaria({
    required this.cedula,
    required this.empresaId,
    required this.nombre,
    required String bancoCodigo,
    required this.numeroCuenta,
    this.tipoId = '1',
    this.digitoVerificacion = '0',
    this.formaPago = '1',
    this.tipoCuenta = '2',
    this.codigoOficina = '0',
    this.email = '',
    this.numeroActualizadoPor,
    this.numeroActualizadoEn,
    this.actualizadoPor,
    this.updatedAt,
  }) : bancoCodigo = normalizarCodigoBanco(bancoCodigo);

  /// Reconstruye la cuenta a partir de las dos piezas.
  ///
  /// [numero] llega vacío cuando quien lee no tiene permiso sobre la colección
  /// reservada, que es lo normal en Talento Humano. No es un error: es que ese
  /// dato no le corresponde.
  factory CuentaBancaria.fromMap(
    String docId,
    Map<String, dynamic> d, {
    Map<String, dynamic>? numero,
  }) => CuentaBancaria(
    cedula: (d['cedula'] ?? '').toString(),
    empresaId: (d['empresaId'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    // Se normaliza AL LEER, no solo al escribir: los documentos que entren
    // por una importación vieja o por consola traen "13" y tienen que
    // comportarse igual que los que traen "0013".
    bancoCodigo: (d['bancoCodigo'] ?? '').toString(),
    numeroCuenta: (numero?['numeroCuenta'] ?? d['numeroCuenta'] ?? '')
        .toString(),
    tipoId: (d['tipoId'] ?? '1').toString(),
    digitoVerificacion: (d['digitoVerificacion'] ?? '0').toString(),
    formaPago: (d['formaPago'] ?? '1').toString(),
    tipoCuenta: (d['tipoCuenta'] ?? '2').toString(),
    codigoOficina: (d['codigoOficina'] ?? '0').toString(),
    email: (d['email'] ?? '').toString(),
    numeroActualizadoPor:
        (numero?['numeroActualizadoPor'] ?? d['numeroActualizadoPor'])
            ?.toString(),
    numeroActualizadoEn:
        (numero?['numeroActualizadoEn'] ?? d['numeroActualizadoEn'])
            is Timestamp
        ? (numero?['numeroActualizadoEn'] ?? d['numeroActualizadoEn'])
              as Timestamp
        : null,
    actualizadoPor: d['actualizadoPor']?.toString(),
    updatedAt: d['updatedAt'] is Timestamp ? d['updatedAt'] as Timestamp : null,
  );

  /// Lo que va en el maestro: todo **menos** el número de cuenta.
  Map<String, dynamic> toMapPublico() => {
    'cedula': cedula,
    'empresaId': empresaId,
    'nombre': nombre,
    'bancoCodigo': bancoCodigo,
    'tipoId': tipoId,
    'digitoVerificacion': digitoVerificacion,
    'formaPago': formaPago,
    'tipoCuenta': tipoCuenta,
    'codigoOficina': codigoOficina,
    'email': email,
    if (actualizadoPor != null) 'actualizadoPor': actualizadoPor,
  };

  /// Lo que va en la colección reservada: el número y su rastro.
  Map<String, dynamic> toMapNumero() => {
    'cedula': cedula,
    'empresaId': empresaId,
    'numeroCuenta': numeroCuenta,
    if (numeroActualizadoPor != null)
      'numeroActualizadoPor': numeroActualizadoPor,
    if (numeroActualizadoEn != null) 'numeroActualizadoEn': numeroActualizadoEn,
  };

  CuentaBancaria copyWith({
    String? nombre,
    String? bancoCodigo,
    String? numeroCuenta,
    String? tipoCuenta,
    String? formaPago,
    String? codigoOficina,
    String? email,
    String? actualizadoPor,
  }) => CuentaBancaria(
    cedula: cedula,
    empresaId: empresaId,
    nombre: nombre ?? this.nombre,
    bancoCodigo: bancoCodigo ?? this.bancoCodigo,
    numeroCuenta: numeroCuenta ?? this.numeroCuenta,
    tipoId: tipoId,
    digitoVerificacion: digitoVerificacion,
    formaPago: formaPago ?? this.formaPago,
    tipoCuenta: tipoCuenta ?? this.tipoCuenta,
    codigoOficina: codigoOficina ?? this.codigoOficina,
    email: email ?? this.email,
    numeroActualizadoPor: numeroActualizadoPor,
    numeroActualizadoEn: numeroActualizadoEn,
    actualizadoPor: actualizadoPor ?? this.actualizadoPor,
    updatedAt: updatedAt,
  );

  /// La cuenta como la debe ver [rol]: con el número tapado si no le compete.
  CuentaBancaria paraRol(String rol) => puedeVerNumeroCuenta(rol)
      ? this
      : copyWith(numeroCuenta: enmascararNumeroCuenta(numeroCuenta));

  /// Convierte esta persona en una línea del archivo plano.
  PlanoPagoFila aFilaDePago({
    required int importeCentavos,
    required DateTime? fechaLimite,
    List<String> conceptos = const [],
  }) => PlanoPagoFila(
    identificacion: cedula,
    tipoId: tipoId,
    digitoVerificacion: digitoVerificacion,
    nombre: nombre,
    formaPago: formaPago,
    banco: bancoCodigo,
    tipoCuenta: tipoCuenta,
    numeroCuenta: numeroCuenta,
    codigoOficina: codigoOficina,
    fechaLimite: fechaLimite,
    importeCentavos: importeCentavos,
    conceptos: conceptos,
    email: email,
  );
}

/// Gravedad de lo encontrado al importar.
///
/// La diferencia importa: un aviso se importa y se revisa después; un bloqueo
/// no se importa, porque tomar la decisión por Tesorería sería peor que no
/// importar la fila.
enum CuentaConflictoNivel { aviso, bloqueo }

class CuentaConflicto {
  final int fila;
  final String cedula;
  final String nombre;
  final String detalle;
  final CuentaConflictoNivel nivel;

  const CuentaConflicto({
    required this.fila,
    required this.cedula,
    required this.nombre,
    required this.detalle,
    this.nivel = CuentaConflictoNivel.aviso,
  });

  @override
  String toString() =>
      'Fila ${fila + 1} · ${nombre.isEmpty ? cedula : nombre}: $detalle';
}

class ImportacionCuentas {
  /// Las que se pueden guardar.
  final List<CuentaBancaria> listas;

  /// Lo encontrado: avisos y bloqueos, en orden de aparición.
  final List<CuentaConflicto> conflictos;

  const ImportacionCuentas({required this.listas, required this.conflictos});

  List<CuentaConflicto> get bloqueos =>
      conflictos.where((c) => c.nivel == CuentaConflictoNivel.bloqueo).toList();

  List<CuentaConflicto> get avisos =>
      conflictos.where((c) => c.nivel == CuentaConflictoNivel.aviso).toList();
}

/// Revisa un lote importado antes de escribirlo.
///
/// [codigosBancoConocidos] es el catálogo de bancos; si llega vacío no se
/// comprueba. **Un código que no esté en el catálogo es un aviso, no un
/// bloqueo**: en el maestro real hay once personas cobrando en códigos (0507,
/// 0551, 0809) que el catálogo del propio Excel no tiene, y esos pagos llevan
/// meses funcionando. El catálogo está viejo, no los datos. Bloquear por eso
/// dejaría a once personas sin sueldo por un problema de nuestra tabla.
ImportacionCuentas analizarImportacionCuentas(
  List<CuentaBancaria> filas, {
  Set<String> codigosBancoConocidos = const {},
}) {
  final conflictos = <CuentaConflicto>[];
  final listas = <CuentaBancaria>[];
  final porCedula = <String, int>{};
  final porCuenta = <String, int>{};

  for (var i = 0; i < filas.length; i++) {
    final c = filas[i];
    final cedula = c.cedula.trim();
    final cuenta = c.numeroCuenta.trim();
    var bloqueada = false;

    void conflicto(String detalle, CuentaConflictoNivel nivel) {
      conflictos.add(
        CuentaConflicto(
          fila: i,
          cedula: cedula,
          nombre: c.nombre.trim(),
          detalle: detalle,
          nivel: nivel,
        ),
      );
      if (nivel == CuentaConflictoNivel.bloqueo) bloqueada = true;
    }

    if (cedula.isEmpty) {
      conflicto('no trae cédula', CuentaConflictoNivel.bloqueo);
    } else if (porCedula.containsKey(cedula)) {
      // En un maestro, la misma persona dos veces no es un duplicado
      // inofensivo: son dos cuentas distintas y nadie sabe cuál es la vigente.
      // Elegir una por orden de aparición sería decidir a dónde va un sueldo.
      // El archivo real trae cuatro casos de estos.
      conflicto(
        'aparece también en la fila ${porCedula[cedula]! + 1} con otros datos; '
        'hay que decidir cuál cuenta es la vigente',
        CuentaConflictoNivel.bloqueo,
      );
    } else {
      porCedula[cedula] = i;
    }

    if (cuenta.isEmpty) {
      conflicto('no trae número de cuenta', CuentaConflictoNivel.bloqueo);
    } else if (!RegExp(r'^\d+$').hasMatch(cuenta)) {
      conflicto(
        'el número de cuenta trae guiones, espacios o letras',
        CuentaConflictoNivel.bloqueo,
      );
    } else if (porCuenta.containsKey(cuenta)) {
      // Existe de verdad —una pareja que cobra en la misma cuenta— así que se
      // avisa y se importa. Lo que no puede es pasar desapercibido.
      conflicto(
        'comparte el número de cuenta con la fila ${porCuenta[cuenta]! + 1}',
        CuentaConflictoNivel.aviso,
      );
    } else {
      porCuenta[cuenta] = i;
    }

    if (c.nombre.trim().isEmpty) {
      conflicto('no trae nombre', CuentaConflictoNivel.bloqueo);
    } else if (c.nombre.trim().length > kPlanoMaxNombre) {
      conflicto(
        'el nombre tiene ${c.nombre.trim().length} caracteres y el banco '
        'admite $kPlanoMaxNombre',
        CuentaConflictoNivel.bloqueo,
      );
    }

    if (c.bancoCodigo.replaceAll('0', '').isEmpty) {
      conflicto('no trae banco', CuentaConflictoNivel.bloqueo);
    } else if (codigosBancoConocidos.isNotEmpty &&
        !codigosBancoConocidos.contains(c.bancoCodigo)) {
      conflicto(
        'el código de banco ${c.bancoCodigo} no está en el catálogo; '
        'verifica que el catálogo esté al día',
        CuentaConflictoNivel.aviso,
      );
    }

    if (!bloqueada) listas.add(c);
  }

  return ImportacionCuentas(listas: listas, conflictos: conflictos);
}

// ─────────────────────────────────────────────────────────────────────────────
// Catálogo de bancos
// ─────────────────────────────────────────────────────────────────────────────

/// Códigos ACH y su nombre, copiados de la hoja "Bancos" del Excel de
/// Tesorería.
///
/// Está aquí para que Talento Humano elija "BBVA" y no teclee "0013": el código
/// es un dato del banco, no algo que alguien deba recordar, y un dígito mal
/// escrito manda un sueldo a otra entidad.
///
/// **Está incompleto a propósito, y no pasa nada.** En el maestro real hay
/// personas cobrando en 0507, 0551 y 0809, que esta tabla no tiene: son
/// entidades más nuevas que el Excel. Por eso el catálogo *sugiere* y no
/// *restringe* — un código que no esté aquí se acepta igual, porque el que está
/// viejo es el catálogo, no los datos.
const Map<String, String> kBancosAch = {
  '0001': 'BANCO DE BOGOTA',
  '0002': 'BANCO POPULAR',
  '0006': 'BANCO CORPBANCA',
  '0007': 'BANCOLOMBIA',
  '0008': 'SCOTIA BANK',
  '0009': 'CITIBANK',
  '0010': 'HSBC COLOMBIA',
  '0012': 'BANCO GNB SUDAMERIS',
  '0013': 'BBVA',
  '0014': 'HELM BANK',
  '0019': 'BANCO COLPATRIA',
  '0023': 'BANCO DE OCCIDENTE',
  '0028': 'BANCO MERCANTIL',
  '0032': 'CAJA SOCIAL',
  '0035': 'INTERCONTINENTAL',
  '0040': 'BANCO AGRARIO',
  '0051': 'DAVIVIENDA',
  '0052': 'BANCO AV VILLAS',
  '0055': 'FINANDINA',
  '0058': 'PROCREDIT',
  '0060': 'PICHINCHA',
  '0061': 'BANCOOMEVA',
  '0062': 'FALABELLA',
  '0076': 'COOP. CENTRAL',
};

/// Nombre del banco, o el código si no está en el catálogo.
///
/// Nunca devuelve vacío: un código desconocido se muestra tal cual, que es más
/// útil que una casilla en blanco y deja ver cuál hay que añadir.
String nombreBanco(String codigo) {
  final c = normalizarCodigoBanco(codigo);
  if (c.replaceAll('0', '').isEmpty) return 'Sin banco';
  return kBancosAch[c] ?? 'Código $c';
}
