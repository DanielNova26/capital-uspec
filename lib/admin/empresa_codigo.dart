/// Código (id) de una empresa a partir de su nombre.
///
/// El id de una empresa es el **doc id** de `TBL_EMPRESAS` y aparece dentro de
/// otros ids del sistema: `TBL_APPS` usa `{empresaId}_{appId}`, los empleados
/// `{empresaId}_{cedula}`, y Storage lo mete en las rutas de facturación. Por
/// eso no puede llevar espacios, tildes ni barras: no es una etiqueta bonita,
/// es una clave que viaja concatenada.
///
/// Cambiar el id de una empresa que ya opera es una migración, no un `update`
/// —el mismo problema que la cédula—, así que se genera una vez y se enseña
/// antes de crear nada.
library;

/// Longitud mínima y máxima aceptadas, las mismas que ya validaba el panel.
const int kEmpresaCodigoMin = 3;
const int kEmpresaCodigoMax = 80;

const String _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
const String _sinTilde = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';

/// Convierte el nombre en código: mayúsculas, sin tildes y con guion bajo.
///
/// No intenta ser listo. No quita "SAS" ni "LTDA" ni abrevia: dos empresas del
/// mismo grupo se distinguen justamente por ese sufijo, y un código que adivina
/// produce colisiones que solo se ven cuando ya hay datos dentro.
String codigoEmpresaDesdeNombre(String nombre) {
  final buffer = StringBuffer();
  for (final rune in nombre.trim().runes) {
    final char = String.fromCharCode(rune);
    final i = _conTilde.indexOf(char);
    buffer.write(i == -1 ? char : _sinTilde[i]);
  }
  final limpio = buffer
      .toString()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return limpio.length > kEmpresaCodigoMax
      ? limpio.substring(0, kEmpresaCodigoMax).replaceAll(RegExp(r'_+$'), '')
      : limpio;
}

/// Devuelve el motivo por el que este nombre no sirve, o `null` si sirve.
///
/// [codigosExistentes] son los ids de empresa que ya hay. Una colisión **no se
/// resuelve sola** añadiendo un número al final: que dos empresas produzcan el
/// mismo código casi siempre significa que se está creando una que ya existe, y
/// un `EMPRESA_2` creado en silencio es un duplicado que nadie va a notar hasta
/// que la información esté repartida entre las dos.
String? validarNombreEmpresaNueva(
  String nombre, {
  Set<String> codigosExistentes = const {},
}) {
  if (nombre.trim().isEmpty) return 'Escribe el nombre de la empresa.';
  final codigo = codigoEmpresaDesdeNombre(nombre);
  if (codigo.length < kEmpresaCodigoMin) {
    return 'El nombre debe tener al menos $kEmpresaCodigoMin letras o números.';
  }
  if (codigosExistentes.contains(codigo)) {
    return 'Ya existe una empresa con el código $codigo.';
  }
  return null;
}
