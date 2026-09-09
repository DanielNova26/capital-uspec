/// Combinación de correspondencia sobre plantillas .docx.
///
/// Reemplaza la macro de Excel con la que Talento Humano venía armando los
/// documentos de finalización de contrato uno por uno: se sube una plantilla de
/// Word con marcadores y un Excel con una fila por persona, y sale un .zip con
/// un documento por fila.
///
/// El trabajo fino está en [reemplazarEnXml]. Word no guarda el texto de un
/// párrafo de corrido: lo parte en `<w:r>` cada vez que cambia una propiedad —
/// y el corrector ortográfico parte incluso donde no cambia nada. Un
/// `{{NOMBRE}}` escrito de una sentada puede quedar como `{{NOM`, `BRE`, `}}`
/// en tres nodos distintos. Por eso no sirve un reemplazo directo sobre el XML:
/// hay que aplanar el párrafo, ubicar el marcador en el texto plano y devolver
/// el valor a los nodos que lo cubrían.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;


/// Nombre canónico de un marcador o de un encabezado de Excel.
///
/// Iguala `{{ Primer Nombre }}` de la plantilla con la columna "PRIMER NOMBRE"
/// del Excel: mayúsculas, sin tildes y con un solo separador. Sin esto, la
/// combinación falla por una tilde y nadie entiende por qué.
String normalizarClave(String valor) {
  final base = valor
      .trim()
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U')
      .replaceAll('Ñ', 'N');
  return base.replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(
    RegExp(r'^_+|_+$'),
    '',
  );
}

/// Una fila del Excel: los datos de una persona.
class FilaCombinacion {
  /// Valores por clave normalizada.
  final Map<String, String> valores;

  /// Número de fila en el Excel (1 = primera fila de datos). Sirve para
  /// nombrar el archivo cuando la fila no trae cédula ni nombre.
  final int numero;

  const FilaCombinacion({required this.valores, required this.numero});

  String operator [](String clave) => valores[normalizarClave(clave)] ?? '';

  /// Cédula de la persona, buscada entre los encabezados que suele traer el
  /// Excel de nómina.
  String get cedula => _primero(const [
    'CEDULA',
    'DOCUMENTO',
    'NO_DOCUMENTO',
    'NUMERO_DE_DOCUMENTO',
    'NUMERO_DOCUMENTO',
    'IDENTIFICACION',
  ]);

  /// Nombre completo, armado de lo que exista.
  String get nombre {
    final completo = _primero(const [
      'NOMBRE_COMPLETO',
      'NOMBRES_Y_APELLIDOS',
      'NOMBRE',
      'TRABAJADOR',
      'EMPLEADO',
    ]);
    if (completo.isNotEmpty) return completo;
    final nombres = _primero(const ['NOMBRES', 'PRIMER_NOMBRE']);
    final apellidos = _primero(const ['APELLIDOS', 'PRIMER_APELLIDO']);
    return '$nombres $apellidos'.trim();
  }

  String _primero(List<String> claves) {
    for (final clave in claves) {
      final valor = valores[clave]?.trim() ?? '';
      if (valor.isNotEmpty) return valor;
    }
    return '';
  }
}

/// Resultado de leer el Excel de datos.
class DatosCombinacion {
  final List<String> encabezados;
  final List<FilaCombinacion> filas;

  const DatosCombinacion({required this.encabezados, required this.filas});

  bool get isEmpty => filas.isEmpty;
}

/// Un documento generado, listo para entrar al .zip.
class DocumentoGenerado {
  final String nombreArchivo;
  final Uint8List bytes;
  final FilaCombinacion fila;

  const DocumentoGenerado({
    required this.nombreArchivo,
    required this.bytes,
    required this.fila,
  });
}

/// Lo que salió mal en una fila, sin abortar el resto del lote.
class ErrorCombinacion {
  final int numeroFila;
  final String detalle;

  const ErrorCombinacion({required this.numeroFila, required this.detalle});
}

class ResultadoCombinacion {
  final List<DocumentoGenerado> documentos;
  final List<ErrorCombinacion> errores;

  /// Marcadores de la plantilla que ninguna columna del Excel alimenta. No
  /// aborta la generación, pero hay que mostrarlos: son los que van a salir
  /// impresos en blanco.
  final List<String> marcadoresSinDato;

  const ResultadoCombinacion({
    required this.documentos,
    required this.errores,
    required this.marcadoresSinDato,
  });
}

/// Lee el Excel de datos: la primera fila con contenido son los encabezados.
DatosCombinacion leerExcelCombinacion(Uint8List bytes) {
  final workbook = xl.Excel.decodeBytes(bytes);
  for (final nombreHoja in workbook.tables.keys) {
    final hoja = workbook.tables[nombreHoja];
    if (hoja == null) continue;

    List<String>? encabezados;
    final filas = <FilaCombinacion>[];
    for (final fila in hoja.rows) {
      final celdas = fila.map((celda) => _textoCelda(celda?.value)).toList();
      if (celdas.every((valor) => valor.trim().isEmpty)) continue;
      if (encabezados == null) {
        encabezados = celdas.map((valor) => valor.trim()).toList();
        continue;
      }
      final valores = <String, String>{};
      for (var i = 0; i < encabezados.length; i++) {
        final clave = normalizarClave(encabezados[i]);
        if (clave.isEmpty) continue;
        valores[clave] = i < celdas.length ? celdas[i].trim() : '';
      }
      filas.add(
        FilaCombinacion(valores: valores, numero: filas.length + 1),
      );
    }
    if (encabezados != null && filas.isNotEmpty) {
      return DatosCombinacion(
        encabezados: encabezados.where((v) => v.isNotEmpty).toList(),
        filas: filas,
      );
    }
  }
  return const DatosCombinacion(encabezados: [], filas: []);
}

/// Partes de un .docx donde puede haber texto visible. Los marcadores también
/// aparecen en encabezados y pies (el membrete con la fecha, por ejemplo), así
/// que reemplazar solo en `document.xml` deja la mitad del oficio sin llenar.
bool _esParteConTexto(String nombre) =>
    nombre == 'word/document.xml' ||
    RegExp(r'^word/(header|footer)\d*\.xml$').hasMatch(nombre) ||
    nombre == 'word/footnotes.xml' ||
    nombre == 'word/endnotes.xml';

/// Marcadores `{{...}}` presentes en la plantilla, ya normalizados.
Set<String> marcadoresDePlantilla(Uint8List docx) {
  final archivo = ZipDecoder().decodeBytes(docx);
  final encontrados = <String>{};
  for (final entrada in archivo.files) {
    if (!entrada.isFile || !_esParteConTexto(entrada.name)) continue;
    final xml = utf8.decode(entrada.content as List<int>, allowMalformed: true);
    for (final parrafo in _parrafos(xml)) {
      final plano = _textoPlano(parrafo);
      for (final m in _patronMarcador.allMatches(plano)) {
        final clave = normalizarClave(m.group(1)!);
        if (clave.isNotEmpty) encontrados.add(clave);
      }
    }
  }
  return encontrados;
}

/// Genera un .docx con los marcadores reemplazados.
Uint8List generarDocumento(Uint8List plantilla, Map<String, String> valores) {
  final archivo = ZipDecoder().decodeBytes(plantilla);
  final salida = Archive();
  for (final entrada in archivo.files) {
    if (!entrada.isFile) continue;
    if (!_esParteConTexto(entrada.name)) {
      salida.addFile(
        ArchiveFile(
          entrada.name,
          (entrada.content as List<int>).length,
          entrada.content,
        ),
      );
      continue;
    }
    final xml = utf8.decode(entrada.content as List<int>, allowMalformed: true);
    final bytes = utf8.encode(reemplazarEnXml(xml, valores));
    salida.addFile(ArchiveFile(entrada.name, bytes.length, bytes));
  }
  final zip = ZipEncoder().encode(salida);
  if (zip == null) throw StateError('No fue posible empaquetar el documento.');
  return Uint8List.fromList(zip);
}

/// Combina la plantilla con todas las filas y devuelve los documentos.
ResultadoCombinacion combinar({
  required Uint8List plantilla,
  required DatosCombinacion datos,
  String extension = 'docx',
}) {
  final marcadores = marcadoresDePlantilla(plantilla);
  final columnas = datos.filas.isEmpty
      ? <String>{}
      : datos.filas.first.valores.keys.toSet();
  final sinDato = marcadores.difference(columnas).toList()..sort();

  final documentos = <DocumentoGenerado>[];
  final errores = <ErrorCombinacion>[];
  final usados = <String>{};

  for (final fila in datos.filas) {
    try {
      final bytes = generarDocumento(plantilla, fila.valores);
      var nombre = _nombreArchivo(fila, extension);
      // Dos personas con el mismo nombre y sin cédula colisionarían dentro del
      // zip y una se perdería sin aviso.
      if (!usados.add(nombre.toLowerCase())) {
        nombre = _nombreArchivo(fila, extension, sufijo: '_${fila.numero}');
        usados.add(nombre.toLowerCase());
      }
      documentos.add(
        DocumentoGenerado(nombreArchivo: nombre, bytes: bytes, fila: fila),
      );
    } catch (error) {
      // Una fila mala no puede tumbar el lote: se reporta y se sigue.
      errores.add(
        ErrorCombinacion(numeroFila: fila.numero, detalle: error.toString()),
      );
    }
  }

  return ResultadoCombinacion(
    documentos: documentos,
    errores: errores,
    marcadoresSinDato: sinDato,
  );
}

/// Empaqueta los documentos generados en un solo .zip.
Uint8List empaquetarZip(List<DocumentoGenerado> documentos) {
  final archivo = Archive();
  for (final documento in documentos) {
    archivo.addFile(
      ArchiveFile(
        documento.nombreArchivo,
        documento.bytes.length,
        documento.bytes,
      ),
    );
  }
  final zip = ZipEncoder().encode(archivo);
  if (zip == null) throw StateError('No fue posible empaquetar el .zip.');
  return Uint8List.fromList(zip);
}

String _nombreArchivo(
  FilaCombinacion fila,
  String extension, {
  String sufijo = '',
}) {
  final partes = [
    if (fila.cedula.isNotEmpty) fila.cedula,
    if (fila.nombre.isNotEmpty) fila.nombre,
  ];
  final base = partes.isEmpty ? 'FILA_${fila.numero}' : partes.join(' - ');
  final limpio = base
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '$limpio$sufijo.$extension';
}

final _patronMarcador = RegExp(r'\{\{([^{}]{1,120})\}\}');
final _patronParrafo = RegExp(r'<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>');
final _patronTexto = RegExp(r'(<w:t(?:\s[^>]*)?>)([\s\S]*?)(</w:t>)');

Iterable<String> _parrafos(String xml) =>
    _patronParrafo.allMatches(xml).map((m) => m.group(0)!);

String _textoPlano(String parrafo) => _patronTexto
    .allMatches(parrafo)
    .map((m) => _desescapar(m.group(2)!))
    .join();

/// Reemplaza los marcadores de un XML de Word.
///
/// Trabaja párrafo por párrafo porque un marcador nunca cruza un párrafo, y
/// acotarlo así evita que un `}}` de más al final del documento se empareje con
/// un `{{` del principio.
String reemplazarEnXml(String xml, Map<String, String> valores) {
  if (valores.isEmpty) return xml;
  return xml.replaceAllMapped(
    _patronParrafo,
    (m) => _reemplazarEnParrafo(m.group(0)!, valores),
  );
}

String _reemplazarEnParrafo(String parrafo, Map<String, String> valores) {
  final nodos = _patronTexto.allMatches(parrafo).toList();
  if (nodos.isEmpty) return parrafo;

  final textos = nodos.map((m) => _desescapar(m.group(2)!)).toList();
  final plano = textos.join();
  if (!plano.contains('{{')) return parrafo;

  // Rango que ocupa cada nodo dentro del texto plano del párrafo.
  final inicios = <int>[];
  var acumulado = 0;
  for (final texto in textos) {
    inicios.add(acumulado);
    acumulado += texto.length;
  }

  var cambio = false;
  // De derecha a izquierda: así los índices ya calculados siguen siendo
  // válidos mientras se van aplicando los reemplazos.
  for (final m in _patronMarcador.allMatches(plano).toList().reversed) {
    final clave = normalizarClave(m.group(1)!);
    final valor = valores[clave];
    if (valor == null) continue;

    final inicio = m.start;
    final fin = m.end;
    final primero = _nodoEn(inicios, textos, inicio);
    final ultimo = _nodoEn(inicios, textos, fin - 1);
    if (primero < 0 || ultimo < 0) continue;

    // El valor entra completo en el primer nodo que tocaba el marcador, así
    // hereda su formato; de los demás solo se borra el pedazo cubierto.
    final desplazamiento = inicio - inicios[primero];
    final antes = textos[primero].substring(0, desplazamiento);
    if (primero == ultimo) {
      final despues = textos[primero].substring(fin - inicios[primero]);
      textos[primero] = '$antes$valor$despues';
    } else {
      textos[primero] = '$antes$valor';
      for (var i = primero + 1; i < ultimo; i++) {
        textos[i] = '';
      }
      textos[ultimo] = textos[ultimo].substring(fin - inicios[ultimo]);
    }
    cambio = true;
  }
  if (!cambio) return parrafo;

  final buffer = StringBuffer();
  var cursor = 0;
  for (var i = 0; i < nodos.length; i++) {
    final nodo = nodos[i];
    buffer.write(parrafo.substring(cursor, nodo.start));
    buffer.write(_conEspacioPreservado(nodo.group(1)!));
    buffer.write(_escapar(textos[i]));
    buffer.write(nodo.group(3)!);
    cursor = nodo.end;
  }
  buffer.write(parrafo.substring(cursor));
  return buffer.toString();
}

int _nodoEn(List<int> inicios, List<String> textos, int posicion) {
  for (var i = 0; i < inicios.length; i++) {
    if (posicion >= inicios[i] && posicion < inicios[i] + textos[i].length) {
      return i;
    }
  }
  return -1;
}

/// Word recorta los espacios de los extremos si el nodo no lo prohíbe, y un
/// "Señor {{NOMBRE}}" quedaría como "SeñorJUAN".
String _conEspacioPreservado(String etiquetaApertura) {
  if (etiquetaApertura.contains('xml:space')) return etiquetaApertura;
  return '${etiquetaApertura.substring(0, etiquetaApertura.length - 1)}'
      ' xml:space="preserve">';
}

String _escapar(String valor) => valor
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _desescapar(String valor) => valor
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _textoCelda(xl.CellValue? value) {
  if (value == null) return '';
  if (value is xl.TextCellValue) return value.value.text?.trim() ?? '';
  if (value is xl.IntCellValue) return value.value.toString();
  if (value is xl.DoubleCellValue) {
    final numero = value.value;
    return numero == numero.roundToDouble()
        ? numero.toInt().toString()
        : numero.toString();
  }
  if (value is xl.DateCellValue) {
    final fecha = value.asDateTimeLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year}';
  }
  if (value is xl.BoolCellValue) return value.value ? 'Sí' : 'No';
  return value.toString().trim();
}
