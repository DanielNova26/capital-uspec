import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'visitas_models.dart';

/// Copia para consultar el formulario completo, incluido el borrador del editor.
/// No guarda ni publica cambios en el maestro.
Uint8List exportarFormatoVisitasExcel(VisitaFormato formato) {
  final libro = Excel.createExcel();
  void hoja(String nombre, List<List<String>> filas, List<double> anchos) {
    final h = libro[nombre];
    for (final fila in filas) {
      h.appendRow([for (final valor in fila) TextCellValue(valor)]);
    }
    for (var c = 0; c < anchos.length; c++) {
      h.setColumnWidth(c, anchos[c]);
    }
    for (var r = 0; r < filas.length; r++) {
      for (var c = 0; c < filas[r].length; c++) {
        h
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .cellStyle = CellStyle(
          bold: r == 0,
          backgroundColorHex: ExcelColor.fromHexString(
            r == 0 ? '#7C3AED' : '#FFFFFF',
          ),
          fontColorHex: ExcelColor.fromHexString(
            r == 0 ? '#FFFFFF' : '#202020',
          ),
          textWrapping: TextWrapping.WrapText,
          verticalAlign: VerticalAlign.Top,
        );
      }
    }
  }

  hoja(
    'Formato',
    [
      ['Campo', 'Contenido'],
      ['Nombre', formato.nombre],
      ['Departamento', formato.areaNombre],
      ['Código', formato.codigo],
      ['Versión del documento', formato.versionDocumento],
      ['Elaboración', formato.elaboracion],
      ['Sistema', formato.sistema],
      ['Estado seleccionado', formato.estado],
      ['Predeterminado', formato.predeterminado ? 'Sí' : 'No'],
      ['Cargos', formato.cargos.join('\n')],
      ['Preguntas', '${formato.items.length}'],
      ['Tablas', '${formato.tablas.length}'],
      [
        'Uso',
        'Copia de consulta del formulario en edición. Incluye cambios sin guardar. Para guardar o publicar cambios utiliza el editor de Visitas.',
      ],
    ],
    [28, 90],
  );
  hoja(
    'Preguntas',
    [
      [
        'Orden',
        'Parte',
        'Sección',
        'Pregunta',
        'Tipo de respuesta',
        'Opciones',
        'Obligatoria',
        'Evidencia obligatoria',
        'Cantidad esperada',
        'Ayuda',
      ],
      for (final it in formato.itemsOrdenados)
        [
          '${it.orden}',
          it.parte,
          it.seccion,
          it.texto,
          kItemTiposLabel[it.tipo] ?? it.tipo,
          it.opciones.join('\n'),
          it.obligatoria ? 'Sí' : 'No',
          it.requiereEvidencia ? 'Sí' : 'No',
          it.unidad,
          it.ayuda,
        ],
    ],
    [9, 22, 28, 70, 32, 35, 16, 22, 22, 60],
  );
  hoja(
    'Tablas',
    [
      [
        'Parte',
        'Tabla',
        'Nombre de cada fila',
        'Columnas para escribir',
        'Columnas para calificar',
        'Escala',
        'Filas fijas',
      ],
      for (final t in formato.tablas)
        [
          t.parte,
          t.nombre,
          t.etiquetaFila,
          t.camposTexto.map((c) => c.label).join('\n'),
          t.camposEstado.map((c) => c.label).join('\n'),
          kEscalasLabel[t.escala] ?? t.escala,
          t.filasFijas.join('\n'),
        ],
    ],
    [22, 40, 28, 40, 40, 40, 45],
  );
  hoja(
    'Partes',
    [
      ['Código', 'Nombre', 'Versión', 'Elaboración'],
      for (final p in formato.partes)
        [p.codigo, p.nombre, p.version, p.elaboracion],
    ],
    [25, 70, 18, 30],
  );
  libro.delete('Sheet1');
  libro.setDefaultSheet('Formato');
  return Uint8List.fromList(libro.encode()!);
}
