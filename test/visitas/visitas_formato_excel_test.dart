import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_excel.dart';
import 'package:todo/visitas/visitas_models.dart';

void main() {
  Uint8List libroCon(
    List<List<String>> filas, {
    String hoja = 'Preguntas',
    Map<String, List<List<String>>> otras = const {},
  }) {
    final libro = Excel.createExcel();
    libro.rename(libro.getDefaultSheet()!, hoja);
    for (final fila in filas) {
      libro[hoja].appendRow([for (final valor in fila) TextCellValue(valor)]);
    }
    for (final e in otras.entries) {
      for (final fila in e.value) {
        libro[e.key].appendRow([for (final v in fila) TextCellValue(v)]);
      }
    }
    return Uint8List.fromList(libro.encode()!);
  }

  final plantilla = Uint8List.fromList(
    File('assets/visitas_plantilla_formato.xlsx').readAsBytesSync(),
  );

  group('plantilla entregada', () {
    test('viene vacía: pide al menos una pregunta', () {
      expect(
        () => importarFormatoVisitasExcel(
          plantilla,
          empresaId: 'e',
          areaId: 'calidad',
          areaNombre: 'Calidad',
          nombre: 'Inspección de Calidad',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'mensaje',
            contains('al menos una pregunta'),
          ),
        ),
      );
    });

    test('los encabezados son los que lee el importador', () {
      final hojas = leerHojasExcel(plantilla);
      expect(hojas.keys, [
        'Instrucciones',
        'Preguntas',
        'Tablas',
        'Ejemplo preguntas',
        'Ejemplo tablas',
      ]);
      String cab(String hoja, int i) => hojas[hoja]!.first[i];
      for (var i = 0; i < kColumnasPreguntas.length; i++) {
        expect(cab('Preguntas', i), kColumnasPreguntas[i]);
      }
      for (var i = 0; i < kColumnasTablas.length; i++) {
        expect(cab('Tablas', i), kColumnasTablas[i]);
      }
    });

    test('el ejemplo se importa y usa todos los tipos en palabras', () {
      final f = importarFormatoVisitasExcel(
        plantilla,
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Ejemplo',
        hojaPreguntas: 'Ejemplo preguntas',
        hojaTablas: 'Ejemplo tablas',
      );
      expect(validarFormato(f), isEmpty);
      expect(f.items.map((i) => i.tipo).toSet(), kItemTiposLabel.keys.toSet());
      final lista = f.items.firstWhere((i) => i.tipo == kItemTipoOpcion);
      expect(lista.opciones, ['Excelente', 'Bueno', 'Regular', 'Malo']);
      final gasas = f.items.firstWhere((i) => i.texto == 'Gasas estériles');
      expect(gasas.unidad, '1 paquete x 20');
      expect(
        f.items.firstWhere((i) => i.tipo == kItemTipoFecha).obligatoria,
        isFalse,
      );
      expect(f.tablas, hasLength(2));
      expect(f.tablas.first.escala, kEscalaBmrnc);
      expect(f.tablas.first.camposTexto.map((c) => c.label), [
        'Ubicación',
        'Tipo',
        'Capacidad',
        'Fecha próxima carga',
      ]);
      expect(f.tablas.last.escala, kEscalaCumple);
      expect(f.tablas.last.filasFijas, [
        'Cocina',
        'Bodega',
        'Comedor',
        'Baños',
      ]);
    });

    test('leer la plantilla la reconoce como plantilla', () {
      final r = leerFormatoVisitasExcel(
        libroCon([
          kColumnasPreguntas,
          ['Cocina', '¿Pisos limpios?', 'Sí / No', '', '', 'Sí', '', ''],
        ]),
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Inspección',
      );
      expect(r.desdePlantilla, isTrue);
      expect(r.formato.items.single.tipo, kItemTipoSiNo);
      expect(r.formato.items.single.requiereEvidencia, isTrue);
    });
  });

  group('plantilla de antes', () {
    test('importa preguntas, códigos viejos y evidencia como borrador', () {
      final bytes = libroCon([
        ['Sección', 'Pregunta', 'Tipo', 'Evidencia obligatoria', 'Unidad'],
        ['Cocina', '¿Hay cadena de frío?', 'calificacion', 'Sí', ''],
        ['Cocina', '¿Existe registro?', 'si_no', 'No', ''],
        ['Botiquín', 'Gasas', 'elemento', 'No', '1 paquete'],
      ]);
      final formato = importarFormatoVisitasExcel(
        bytes,
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Inspección de Calidad',
      );
      expect(formato.estado, kFormatoBorrador);
      expect(formato.areaId, 'calidad');
      expect(formato.items, hasLength(3));
      expect(formato.items.first.requiereEvidencia, isTrue);
      expect(formato.items[1].tipo, kItemTipoSiNo);
      expect(formato.items.last.tipo, kItemTipoElemento);
      expect(formato.items.last.unidad, '1 paquete');
    });

    test('rechaza filas incompletas sin guardar un formato parcial', () {
      final bytes = libroCon([
        ['Sección', 'Pregunta', 'Tipo'],
        ['Cocina', '', 'si_no'],
      ]);
      expect(
        () => importarFormatoVisitasExcel(
          bytes,
          empresaId: 'e',
          areaId: 'calidad',
          areaNombre: 'Calidad',
          nombre: 'Inspección',
        ),
        throwsFormatException,
      );
    });

    test('un tipo que no existe dice cuáles se pueden usar', () {
      expect(
        () => importarFormatoVisitasExcel(
          libroCon([
            ['Pregunta', 'Tipo de respuesta'],
            ['¿Algo?', 'Semáforo'],
          ]),
          empresaId: 'e',
          areaId: 'calidad',
          areaNombre: 'Calidad',
          nombre: 'X',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'mensaje',
            contains('Lista de opciones'),
          ),
        ),
      );
    });

    test('tipoDesdeTexto entiende el nombre, el código y variantes', () {
      expect(tipoDesdeTexto(''), kItemTipoCalificacion);
      expect(
        tipoDesdeTexto('cumple / no cumple / no aplica'),
        kItemTipoCalificacion,
      );
      expect(tipoDesdeTexto('SI/NO'), kItemTipoSiNo);
      expect(tipoDesdeTexto('Elemento'), kItemTipoElemento);
      expect(tipoDesdeTexto('Número'), kItemTipoNumero);
      expect(tipoDesdeTexto('texto largo'), kItemTipoParrafo);
      expect(tipoDesdeTexto('lista'), kItemTipoOpcion);
      expect(tipoDesdeTexto('otra cosa'), isNull);
    });
  });

  group('adaptar cualquier Excel', () {
    test('un formato como el de SST: encabezado, secciones y subtotales', () {
      final bytes = libroCon(hoja: 'Diagnóstico', [
        [
          'SISTEMA DE GESTIÓN DE SEGURIDAD Y SALUD EN EL TRABAJO',
          '',
          'CÓDIGO',
          'F-UT-SST-02',
        ],
        ['FORMATO DE INSPECCIÓN DIAGNÓSTICO SST', '', 'VERSIÓN', '1'],
        ['', '', 'ELABORACIÓN', '15/05/2025'],
        [
          'ITEMS A EVALUAR',
          'PARÁMETROS DE EVALUACIÓN',
          'CALIF.',
          'OBSERVACIONES',
        ],
        ['ORDEN Y ASEO', '¿Pasillos organizados y limpios?', '', ''],
        ['', '¿Se observa limpieza de equipos?', '', ''],
        ['', 'Subtotal', '', ''],
        ['EXTINTORES', '¿Los extintores están señalizados?', '', ''],
        ['', 'Subtotal', '', ''],
        ['FIRMA:', '', '', ''],
      ]);
      final r = leerFormatoVisitasExcel(
        bytes,
        empresaId: 'e',
        areaId: 'hse',
        areaNombre: 'SST',
        nombre: 'Diagnóstico',
      );
      expect(r.desdePlantilla, isFalse);
      final f = r.formato;
      expect(f.estado, kFormatoBorrador);
      expect(f.items.map((i) => i.texto), [
        '¿Pasillos organizados y limpios?',
        '¿Se observa limpieza de equipos?',
        '¿Los extintores están señalizados?',
      ]);
      expect(f.items.map((i) => i.seccion), [
        'ORDEN Y ASEO',
        'ORDEN Y ASEO',
        'EXTINTORES',
      ]);
      expect(f.codigo, 'F-UT-SST-02');
      expect(f.versionDocumento, '1');
      expect(f.elaboracion, '15/05/2025');
      expect(r.avisos.join(' '), contains('PARÁMETROS DE EVALUACIÓN'));
    });

    test(
      'sin encabezado: la columna de textos largos y títulos en mayúscula',
      () {
        final r = leerFormatoVisitasExcel(
          libroCon(hoja: 'Hoja1', [
            ['COCINA'],
            ['1', 'Mesones limpios y desinfectados'],
            ['2', 'Utensilios en buen estado'],
            ['BODEGA'],
            ['3', 'Productos rotulados con fecha'],
          ]),
          empresaId: 'e',
          areaId: 'calidad',
          areaNombre: 'Calidad',
          nombre: 'Lista',
        );
        expect(r.formato.items.map((i) => i.seccion), [
          'COCINA',
          'COCINA',
          'BODEGA',
        ]);
        expect(r.formato.items.first.texto, 'Mesones limpios y desinfectados');
      },
    );

    test('varias hojas: cada una es una parte del formato', () {
      final r = leerFormatoVisitasExcel(
        libroCon(
          hoja: 'Cocina',
          [
            ['Pregunta'],
            ['¿Mesones limpios?'],
          ],
          otras: {
            'Botiquín': [
              ['Elemento', 'Unidad'],
              ['Gasas', '1 paquete'],
            ],
          },
        ),
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Dos hojas',
      );
      final f = r.formato;
      expect(f.partes.map((p) => p.codigo), ['Cocina', 'Botiquín']);
      expect(f.itemsDeParte('Botiquín').single.tipo, kItemTipoElemento);
      expect(f.itemsDeParte('Botiquín').single.unidad, '1 paquete');
      expect(validarFormato(f), isEmpty);
    });

    test('un Excel sin nada que preguntar lo dice', () {
      expect(
        () => leerFormatoVisitasExcel(
          libroCon(hoja: 'Hoja1', [
            ['1', '2'],
          ]),
          empresaId: 'e',
          areaId: 'calidad',
          areaNombre: 'Calidad',
          nombre: 'Nada',
        ),
        throwsFormatException,
      );
    });
  });

  group('pegar desde Excel', () {
    test('con los encabezados de la plantilla', () {
      final r = preguntasDesdeTextoPegado(
        'Sección\tPregunta\tTipo de respuesta\n'
        'Cocina\t¿Pisos limpios?\tSí / No\n'
        'Cocina\tTemperatura de la nevera\tNúmero\n',
        desdeOrden: 5,
      );
      expect(r.items.map((i) => i.orden), [5, 6]);
      expect(r.items.last.tipo, kItemTipoNumero);
    });

    test('sin encabezados: sección y pregunta', () {
      final r = preguntasDesdeTextoPegado(
        'Cocina\tMesones limpios y desinfectados\n'
        'Cocina\tUtensilios en buen estado\n',
      );
      expect(r.items, hasLength(2));
      expect(r.items.first.texto, 'Mesones limpios y desinfectados');
    });
  });
}
