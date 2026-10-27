import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_export.dart';
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_models.dart';

void main() {
  test(
    'exporta datos documentales, todas las preguntas y las tablas de SST',
    () {
      final f = formatoSstOficial('e');
      final libro = Excel.decodeBytes(exportarFormatoVisitasExcel(f));
      expect(libro.tables.keys, ['Formato', 'Preguntas', 'Tablas', 'Partes']);
      expect(libro['Preguntas'].maxRows, f.items.length + 1);
      expect(libro['Tablas'].maxRows, f.tablas.length + 1);
      expect(libro['Partes'].maxRows, f.partes.length + 1);
      expect(libro['Formato'].rows[1][1]!.value.toString(), f.nombre);
      expect(libro['Formato'].rows[3][1]!.value.toString(), f.codigo);
      final tabla = libro['Tablas'].rows[1];
      expect(
        tabla[3]!.value.toString(),
        f.tablas.first.camposTexto.map((c) => c.label).join('\n'),
      );
      expect(
        tabla[4]!.value.toString(),
        f.tablas.first.camposEstado.map((c) => c.label).join('\n'),
      );
    },
  );

  test('conserva selección múltiple, textos extensos y valores como texto', () {
    final texto =
        'Pregunta muy larga ${List.filled(30, 'sin recortar').join(' ')}';
    final f = VisitaFormato(
      empresaId: 'e',
      areaId: 'a',
      areaNombre: 'Calidad',
      nombre: 'Borrador',
      items: [
        VisitaFormatoItem(
          id: 'p',
          orden: 1,
          seccion: 'Cocina',
          texto: texto,
          tipo: kItemTipoSeleccionMultiple,
          opciones: const ['Uno; dos', '=1+1'],
          obligatoria: false,
          ayuda: 'Ayuda actual sin guardar',
        ),
      ],
    );
    final libro = Excel.decodeBytes(exportarFormatoVisitasExcel(f));
    final fila = libro['Preguntas'].rows[1];
    expect(fila[3]!.value.toString(), texto);
    expect(
      fila[4]!.value.toString(),
      kItemTiposLabel[kItemTipoSeleccionMultiple],
    );
    expect(fila[5]!.value, isA<TextCellValue>());
    expect(fila[5]!.value.toString(), 'Uno; dos\n=1+1');
    expect(fila[6]!.value.toString(), 'No');
    expect(fila[9]!.value.toString(), 'Ayuda actual sin guardar');
    expect(
      libro['Formato'].rows.last[1]!.value.toString(),
      contains('sin guardar'),
    );
  });

  test('permite consultar un borrador vacío sin exigir publicarlo', () {
    final f = VisitaFormato(
      empresaId: 'e',
      areaId: 'a',
      areaNombre: 'Calidad',
      nombre: '',
    );
    final libro = Excel.decodeBytes(exportarFormatoVisitasExcel(f));
    expect(libro['Preguntas'].maxRows, 1);
    expect(libro['Tablas'].maxRows, 1);
  });
}
