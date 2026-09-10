/// Maestro de datos bancarios del personal.
///
/// Es la hoja `CUENTAS` del Excel de Tesorería convertida en colección. Vive
/// **aparte de `TBL_USUARIOS`** a propósito: el número de cuenta de una persona
/// no puede quedar en el mismo documento que su nombre y su foto, porque ese
/// documento lo lee media aplicación para pintar avatares. Separarlo es lo que
/// permite que la regla de Firestore sea distinta.
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

/// Colección del maestro.
const String kCuentasBancariasCol = 'TBL_NOMINA_CUENTAS';

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
/// Lleva la empresa además de la cédula porque el permiso es por empresa: la
/// Tesorería de una no debe leer las cuentas del personal de la otra. El precio
/// es que alguien que trabaja en las dos queda con dos registros y hay que
/// actualizar ambos si cambia de banco; se prefiere ese trabajo a que un
/// maestro global quede legible para todas las tesorerías.
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

  factory CuentaBancaria.fromMap(String docId, Map<String, dynamic> d) =>
      CuentaBancaria(
        cedula: (d['cedula'] ?? '').toString(),
        empresaId: (d['empresaId'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        // Se normaliza AL LEER, no solo al escribir: los documentos que entren
        // por una importación vieja o por consola traen "13" y tienen que
        // comportarse igual que los que traen "0013".
        bancoCodigo: (d['bancoCodigo'] ?? '').toString(),
        numeroCuenta: (d['numeroCuenta'] ?? '').toString(),
        tipoId: (d['tipoId'] ?? '1').toString(),
        digitoVerificacion: (d['digitoVerificacion'] ?? '0').toString(),
        formaPago: (d['formaPago'] ?? '1').toString(),
        tipoCuenta: (d['tipoCuenta'] ?? '2').toString(),
        codigoOficina: (d['codigoOficina'] ?? '0').toString(),
        email: (d['email'] ?? '').toString(),
        numeroActualizadoPor: d['numeroActualizadoPor']?.toString(),
        numeroActualizadoEn: d['numeroActualizadoEn'] is Timestamp
            ? d['numeroActualizadoEn'] as Timestamp
            : null,
        actualizadoPor: d['actualizadoPor']?.toString(),
        updatedAt: d['updatedAt'] is Timestamp
            ? d['updatedAt'] as Timestamp
            : null,
      );

  Map<String, dynamic> toMap() => {
    'cedula': cedula,
    'empresaId': empresaId,
    'nombre': nombre,
    'bancoCodigo': bancoCodigo,
    'numeroCuenta': numeroCuenta,
    'tipoId': tipoId,
    'digitoVerificacion': digitoVerificacion,
    'formaPago': formaPago,
    'tipoCuenta': tipoCuenta,
    'codigoOficina': codigoOficina,
    'email': email,
    if (numeroActualizadoPor != null)
      'numeroActualizadoPor': numeroActualizadoPor,
    if (numeroActualizadoEn != null) 'numeroActualizadoEn': numeroActualizadoEn,
    if (actualizadoPor != null) 'actualizadoPor': actualizadoPor,
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
