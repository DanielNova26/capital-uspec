import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;

import 'visitas_models.dart';

/// Importa la plantilla de preguntas. El resultado siempre es borrador para
/// que la jefatura revise el contenido antes de habilitar visitas reales.
VisitaFormato importarFormatoVisitasExcel(
  Uint8List bytes, {
  required String empresaId,
  required String areaId,
  required String areaNombre,
  required String nombre,
}) {
  if (areaId.trim().isEmpty || nombre.trim().isEmpty) {
    throw const FormatException(
      'Selecciona el área y escribe el nombre del formato.',
    );
  }
  final libro = xl.Excel.decodeBytes(_normalizarRelaciones(bytes));
  final hoja =
      libro.tables['Preguntas'] ??
      (libro.tables.isEmpty ? null : libro.tables.values.first);
  if (hoja == null || hoja.rows.isEmpty) {
    throw const FormatException('El Excel no contiene una hoja de preguntas.');
  }
  final cabecera = hoja.rows.first
      .map((c) => _normalizar(_texto(c?.value)))
      .toList();
  int columna(String nombre) => cabecera.indexOf(_normalizar(nombre));
  final preguntaCol = columna('Pregunta');
  if (preguntaCol < 0) {
    throw const FormatException(
      'Falta la columna Pregunta en la primera fila.',
    );
  }
  final seccionCol = columna('Sección');
  final tipoCol = columna('Tipo');
  final evidenciaCol = columna('Evidencia obligatoria');
  final unidadCol = columna('Unidad');
  String celda(List<xl.Data?> fila, int columna) =>
      columna < 0 || columna >= fila.length
      ? ''
      : _texto(fila[columna]?.value).trim();

  final items = <VisitaFormatoItem>[];
  for (var i = 1; i < hoja.rows.length; i++) {
    final fila = hoja.rows[i];
    if (fila.every((c) => _texto(c?.value).trim().isEmpty)) continue;
    final pregunta = celda(fila, preguntaCol);
    if (pregunta.isEmpty) {
      throw FormatException('Fila ${i + 1}: falta la pregunta.');
    }
    final tipoTexto = _normalizar(celda(fila, tipoCol));
    final tipo = switch (tipoTexto) {
      '' ||
      'calificacion' ||
      'cumple/no cumple/no aplica' => kItemTipoCalificacion,
      'si/no' || 'si_no' => kItemTipoSiNo,
      'elemento' => kItemTipoElemento,
      _ => throw FormatException(
        'Fila ${i + 1}: tipo no reconocido: ${celda(fila, tipoCol)}.',
      ),
    };
    final evidenciaTexto = _normalizar(celda(fila, evidenciaCol));
    if (!['', 'si', 'no', 'true', 'false', '1', '0'].contains(evidenciaTexto)) {
      throw FormatException(
        'Fila ${i + 1}: Evidencia obligatoria debe ser Sí o No.',
      );
    }
    items.add(
      VisitaFormatoItem(
        id: 'p${(items.length + 1).toString().padLeft(3, '0')}',
        orden: items.length + 1,
        seccion: celda(fila, seccionCol),
        texto: pregunta,
        tipo: tipo,
        requiereEvidencia: ['si', 'true', '1'].contains(evidenciaTexto),
        unidad: celda(fila, unidadCol),
      ),
    );
  }
  if (items.isEmpty) {
    throw const FormatException(
      'Agrega al menos una pregunta antes de importar.',
    );
  }
  final formato = VisitaFormato(
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre.trim(),
    estado: kFormatoBorrador,
    items: items,
  );
  final errores = validarFormato(formato);
  if (errores.isNotEmpty) throw FormatException(errores.join(' '));
  return formato;
}

/// Algunas herramientas Excel escriben destinos absolutos y prefijos `x:`
/// en el XML. El lector `excel` espera rutas relativas y etiquetas sin prefijo.
Uint8List _normalizarRelaciones(Uint8List bytes) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    final reconstruido = Archive();
    var cambios = false;
    for (final archivo in zip) {
      if (!archivo.name.startsWith('xl/') ||
          !archivo.name.endsWith('.xml') && !archivo.name.endsWith('.rels')) {
        reconstruido.addFile(archivo);
        continue;
      }
      final original = utf8.decode(archivo.content as List<int>);
      var xml = original.replaceAll('Target="/xl/', 'Target="');
      xml = xml
          .replaceAll('xmlns:x=', 'xmlns=')
          .replaceAll('<x:', '<')
          .replaceAll('</x:', '</');
      if (archivo.name.startsWith('xl/worksheets/')) {
        xml = xml.replaceAllMapped(
          RegExp(r'<c\b[^>]*\bt="str"[^>]*/>'),
          (m) => m.group(0)!.replaceAll(' t="str"', ''),
        );
      }
      if (xml != original) cambios = true;
      final contenido = utf8.encode(xml);
      reconstruido.addFile(
        ArchiveFile(archivo.name, contenido.length, contenido),
      );
    }
    if (!cambios) return bytes;
    final codificado = ZipEncoder().encode(reconstruido);
    return codificado == null ? bytes : Uint8List.fromList(codificado);
  } catch (_) {
    return bytes;
  }
}

String _texto(xl.CellValue? valor) => switch (valor) {
  xl.TextCellValue v => v.value.toString(),
  xl.IntCellValue v => v.value.toString(),
  xl.DoubleCellValue v => v.value.toString(),
  xl.BoolCellValue v => v.value ? 'Sí' : 'No',
  xl.FormulaCellValue v => v.formula,
  _ => '',
};

String _normalizar(String valor) => valor
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[áà]'), 'a')
    .replaceAll(RegExp(r'[éè]'), 'e')
    .replaceAll(RegExp(r'[íì]'), 'i')
    .replaceAll(RegExp(r'[óò]'), 'o')
    .replaceAll(RegExp(r'[úù]'), 'u');
