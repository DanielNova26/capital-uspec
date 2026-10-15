import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla_word.dart';
import 'package:xml/xml.dart';

Uint8List zip(Map<String, List<int>> partes) {
  final archive = Archive();
  for (final e in partes.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Map<String, List<int>> partes(Uint8List bytes) => {
  for (final f in ZipDecoder().decodeBytes(bytes).files)
    f.name: f.content as List<int>,
};

const ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
String celda(String texto) =>
    '<w:tc><w:p w:rsidR="1234"><w:r><w:rPr>'
    '<w:sz w:val="18"/></w:rPr><w:t>$texto</w:t></w:r></w:p></w:tc>';
String encabezado() =>
    '<w:hdr xmlns:w="$ns"><w:tbl>'
    '<w:tr>${celda('Versión')}${celda('v1')}</w:tr>'
    '<w:tr>${celda('Aprobado')}${celda('Pendiente')}</w:tr>'
    '<w:tr>${celda('Fecha')}${celda('08/10/2026')}</w:tr>'
    '<w:tr>${celda('Código')}${celda('COM-001')}</w:tr>'
    '</w:tbl></w:hdr>';

void main() {
  test('Word guardado sin gdAprobado: cambia solo el campo del encabezado', () {
    final original = {
      'word/header1.xml': utf8.encode(encabezado()),
      'word/header2.xml': utf8.encode(
        encabezado().replaceAll('w:', 'x:').replaceAll('xmlns:w=', 'xmlns:x='),
      ),
      'word/document.xml': utf8.encode(
        '<w:document xmlns:w="$ns">'
        '<w:body><w:p><w:r><w:t>Pendiente por aprobar</w:t></w:r></w:p>'
        '</w:body></w:document>',
      ),
      'word/media/logo.png': [1, 2, 3, 4],
    };
    final resultado = gdSellarPlantillaWordValidada(
      zip(original),
      aprobadoPor: 'Ana & Co',
      aprobadoEn: DateTime(2026),
    );
    expect(resultado.bytes, isNotNull, reason: resultado.detalle);
    final salida = partes(resultado.bytes!);
    for (final nombre in ['word/header1.xml', 'word/header2.xml']) {
      final xml = XmlDocument.parse(utf8.decode(salida[nombre]!));
      expect(xml.innerText, contains('Ana & Co'));
      expect(xml.innerText, isNot(contains('Pendiente')));
      expect(xml.innerText, contains('08/10/2026'));
      expect(xml.toXmlString(), contains('rsidR="1234"'));
      expect(xml.toXmlString(), contains('val="18"'));
    }
    expect(salida['word/document.xml'], original['word/document.xml']);
    expect(salida['word/media/logo.png'], original['word/media/logo.png']);
  });

  test('una tabla ajena con Aprobado no se modifica', () {
    final resultado = gdSellarPlantillaWordValidada(
      zip({
        'word/header1.xml': utf8.encode(
          '<w:hdr xmlns:w="$ns"><w:tbl>'
          '<w:tr>${celda('Aprobado')}${celda('Pendiente')}</w:tr>'
          '</w:tbl></w:hdr>',
        ),
      }),
      aprobadoPor: 'Ana',
      aprobadoEn: DateTime(2026),
    );
    expect(resultado.bytes, isNull);
  });

  test(
    'Excel: todas las hojas, prefijos, atributos reordenados y sharedStrings',
    () {
      const hoja =
          '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<x:sheetData><x:row r="2">'
          '<x:c t="s" s="4" r="M2"><x:v>0</x:v></x:c>'
          '<x:c s="5" t="s" r="O2"><x:v>1</x:v></x:c>'
          '<x:c r="Q2"><x:f>SUM(A1:A2)</x:f><x:v>8</x:v></x:c>'
          '</x:row></x:sheetData><x:mergeCells><x:mergeCell ref="D2:L3" />'
          '</x:mergeCells></x:worksheet>';
      final original = {
        'xl/worksheets/sheet1.xml': utf8.encode(hoja),
        'xl/worksheets/sheet2.xml': utf8.encode(hoja),
        'xl/sharedStrings.xml': utf8.encode(
          '<sst><si><t>Aprobado</t></si>'
          '<si><t>Pendiente</t></si></sst>',
        ),
        'xl/styles.xml': utf8.encode('<styleSheet/>'),
        'xl/media/logo.png': [1, 2, 3],
      };
      final resultado = gdSellarPlantillaValidada(
        zip(original),
        aprobadoPor: 'Ana & Co',
        aprobadoEn: DateTime(2026),
      );
      expect(resultado.bytes, isNotNull, reason: resultado.detalle);
      final salida = partes(resultado.bytes!);
      for (final nombre in [
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/sheet2.xml',
      ]) {
        final xml = XmlDocument.parse(utf8.decode(salida[nombre]!));
        final celda = xml.descendants.whereType<XmlElement>().singleWhere(
          (e) => e.name.local == 'c' && e.getAttribute('r') == 'O2',
        );
        expect(celda.innerText, 'Ana & Co');
        expect(celda.getAttribute('s'), '5');
        expect(celda.getAttribute('t'), 'inlineStr');
        expect(xml.toXmlString(), contains('SUM(A1:A2)'));
      }
      for (final nombre in [
        'xl/sharedStrings.xml',
        'xl/styles.xml',
        'xl/media/logo.png',
      ]) {
        expect(salida[nombre], original[nombre]);
      }
    },
  );

  test(
    'Excel no reemplaza una celda de otro formato por coincidir el merge',
    () {
      final resultado = gdSellarPlantillaValidada(
        zip({
          'xl/worksheets/sheet1.xml': utf8.encode(
            '<worksheet><sheetData>'
            '<row r="2"><c r="M2" t="inlineStr"><is><t>Inventario</t></is></c>'
            '<c r="O2"><v>123</v></c></row></sheetData>'
            '<mergeCells><mergeCell ref="D2:L3"/></mergeCells></worksheet>',
          ),
        }),
        aprobadoPor: 'Ana',
        aprobadoEn: DateTime(2026),
      );
      expect(resultado.bytes, isNull);
    },
  );

  // Prueba local opcional sobre el adjunto real, sin copiar datos del usuario
  // al repositorio ni generar una aprobación ficticia para entregarla.
  final adjunto = Platform.environment['GD_DOCX_REGRESSION'];
  if (adjunto != null) {
    test(
      'adjunto real COM-001: recupera el campo y conserva las demás partes',
      () {
        final original = File(adjunto).readAsBytesSync();
        final resultado = gdSellarPlantillaWordValidada(
          original,
          aprobadoPor: 'PRUEBA AUTOMÁTICA',
          aprobadoEn: DateTime(2026),
        );
        expect(resultado.bytes, isNotNull, reason: resultado.detalle);
        final antes = partes(original);
        final despues = partes(resultado.bytes!);
        expect(despues.keys, antes.keys);
        for (final nombre in antes.keys) {
          if (nombre == 'word/header1.xml') continue;
          expect(despues[nombre], antes[nombre], reason: nombre);
        }
        final texto = XmlDocument.parse(
          utf8.decode(despues['word/header1.xml']!),
        ).innerText;
        expect(texto, contains('PRUEBA AUTOMÁTICA'));
        expect(texto, isNot(contains('Pendiente')));
      },
    );
  }
}
