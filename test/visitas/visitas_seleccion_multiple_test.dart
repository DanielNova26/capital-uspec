import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_informe_pdf.dart';
import 'package:todo/visitas/visitas_models.dart';

void main() {
  const item = VisitaFormatoItem(
    id: 'equipos',
    orden: 1,
    texto: 'Equipos usados',
    tipo: kItemTipoSeleccionMultiple,
    opciones: ['Horno', 'Estufa; industrial', 'Nevera, grande'],
  );

  test('conserva selecciones con separadores al guardar y volver a abrir', () {
    final valor = codificarSeleccionMultiple(item.opciones.skip(1));
    final respuesta = VisitaRespuesta.fromMap(
      VisitaRespuesta(valor: valor).toMap(),
    );
    final restaurado = VisitaFormatoItem.fromMap(item.toMap());
    expect(restaurado.tipo, kItemTipoSeleccionMultiple);
    expect(seleccionMultipleDesde(respuesta.valor), item.opciones.skip(1));
    expect(valorValidoParaItem(restaurado, respuesta.valor), isTrue);
    expect(
      textoRespuestaFormulario(restaurado, respuesta.valor),
      'Estufa; industrial; Nevera, grande',
    );
    expect(itemPendiente(restaurado, respuesta), isFalse);
    expect(restaurado.califica, isFalse);
  });

  test('obligatoria exige al menos una; opcional permite quitar todas', () {
    final vacia = VisitaRespuesta(valor: codificarSeleccionMultiple([]));
    expect(itemPendiente(item, vacia), isTrue);
    expect(itemPendiente(item.copyWith(obligatoria: false), vacia), isFalse);
    expect(
      itemPendiente(item, const VisitaRespuesta(valor: '["Horno"]')),
      isFalse,
    );
  });

  test('rechaza opciones ajenas, repetidas y valores dañados', () {
    for (final valor in [
      '["Ajena"]',
      '["Horno","Horno"]',
      '[]',
      '[1]',
      'null',
      '{}',
      'Horno',
      '["Horno",',
    ]) {
      expect(valorValidoParaItem(item, valor), isFalse, reason: valor);
      expect(
        itemPendiente(
          item.copyWith(obligatoria: false),
          VisitaRespuesta(valor: valor),
        ),
        isTrue,
        reason: valor,
      );
    }
    expect(
      valorValidoParaItem(item.copyWith(tipo: kItemTipoOpcion), 'Horno'),
      isTrue,
    );
    expect(
      valorValidoParaItem(item.copyWith(tipo: kItemTipoOpcion), '["Horno"]'),
      isFalse,
    );
  });

  test('el formato exige dos opciones distintas para selección múltiple', () {
    VisitaFormato formato(List<String> opciones) => VisitaFormato(
      empresaId: 'e',
      areaId: 'a',
      areaNombre: 'Calidad',
      nombre: 'Inspección',
      items: [item.copyWith(opciones: opciones)],
    );
    expect(validarFormato(formato(['Horno'])), isNotEmpty);
    expect(validarFormato(formato(['Horno', 'Horno'])), isNotEmpty);
    expect(validarFormato(formato(['Horno', ''])), isNotEmpty);
    expect(validarFormato(formato(item.opciones)), isEmpty);
  });

  test(
    'el informe PDF muestra todas las opciones como texto legible',
    () async {
      final formato = VisitaFormato(
        id: 'f',
        empresaId: 'e',
        areaId: 'a',
        areaNombre: 'Calidad',
        nombre: 'Inspección',
        items: [item],
      );
      final visita = VisitaProfesional(
        empresaId: 'e',
        formatoId: 'f',
        formatoNombre: 'Inspección',
        areaId: 'a',
        areaNombre: 'Calidad',
        centroId: 'c',
        centroNombre: 'Centro',
        profesionalId: 'u',
        profesionalNombre: 'Profesional',
        asignadoPorId: 'j',
        asignadoPorNombre: 'Jefe',
        fechaProgramada: DateTime(2026, 10, 26),
        respuestas: {
          'equipos': VisitaRespuesta(
            valor: codificarSeleccionMultiple(['Horno', 'Nevera, grande']),
          ),
        },
      );
      final bytes = await generarInformeVisita(
        v: visita,
        formato: formato,
        empresaNombre: 'Empresa',
      );
      final raw = String.fromCharCodes(bytes);
      final contenido = StringBuffer();
      for (final stream in RegExp(
        r'stream\r?\n([\s\S]*?)\r?\nendstream',
      ).allMatches(raw)) {
        try {
          contenido.write(
            String.fromCharCodes(zlib.decode(stream.group(1)!.codeUnits)),
          );
        } on FormatException {
          // Las imágenes y fuentes no son texto comprimido.
        }
      }
      final texto = RegExp(
        r'\[\((.*?)\)\]TJ',
      ).allMatches(contenido.toString()).map((m) => m.group(1)).join(' ');
      expect(texto, contains('Horno; Nevera, grande'));
      expect(texto, isNot(contains('["Horno"')));
    },
  );
}
