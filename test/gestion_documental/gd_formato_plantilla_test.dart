import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla.dart';

/// PNG válido de 4x2 px (firma + IHDR + IDAT + IEND). Solo importa la
/// cabecera: el generador lee ancho/alto, no decodifica píxeles.
Uint8List _pngDePrueba() {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.add([0, 0, 0, 13]);
  b.add(ascii.encode('IHDR'));
  b.add([0, 0, 0, 4, 0, 0, 0, 2, 8, 6, 0, 0, 0]);
  b.add([0, 0, 0, 0]); // crc (no se valida)
  b.add([0, 0, 0, 0]);
  b.add(ascii.encode('IEND'));
  b.add([0xAE, 0x42, 0x60, 0x82]);
  return b.toBytes();
}

Map<String, String> _partes(Uint8List xlsx) {
  final archive = ZipDecoder().decodeBytes(xlsx);
  return {
    for (final f in archive.files)
      if (f.isFile && f.name.endsWith('.xml') || f.name.endsWith('.rels'))
        f.name: utf8.decode(f.content as List<int>),
  };
}

void main() {
  group('plantilla Excel de formato institucional', () {
    test('la clave de hoja usa el mismo hash que Excel/openpyxl', () {
      expect(gdHashClaveHoja('CALIDAD-USPEC'), '88EA');
      expect(gdHashClaveHoja('abc'), 'CC1A');
    });

    test('el encabezado va bloqueado y el contenido libre', () {
      final datos = GdPlantillaFormatoDatos(
        empresaNombre: 'UT Alfa',
        titulo: 'Acta de baja de mercancía',
        codigo: 'LOG-001',
        dependencia: 'Logística',
        version: 'v1',
        fecha: DateTime(2026, 9, 14),
      );
      final partes = _partes(gdGenerarPlantillaFormato(datos));
      final hoja = partes['xl/worksheets/sheet1.xml']!;
      final estilos = partes['xl/styles.xml']!;

      expect(hoja, contains('<sheetProtection password="88EA" sheet="1"'));
      expect(hoja, contains('selectLockedCells="1"'));
      expect(hoja, contains('formatCells="0"'));
      expect(hoja, contains('<mergeCell ref="C1:G3"/>'));
      expect(hoja, contains('Acta de baja de mercancía'));
      expect(hoja, contains('Pendiente de validación'));
      expect(hoja, contains('14/09/2026'));
      expect(hoja, contains('topLeftCell="A7"'));
      expect(hoja, isNot(contains('<drawing')));
      // Sin logo, el recuadro muestra el nombre de la empresa.
      expect(hoja, contains('<c r="A1" s="1" t="inlineStr"><is><t xml:space="preserve">UT Alfa'));
      // El estilo 0 (todas las celdas no escritas) está desbloqueado.
      expect(
        estilos,
        contains(
          '<cellXfs count="8"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyProtection="1"><protection locked="0"/></xf>',
        ),
      );
      expect(partes.containsKey('xl/drawings/drawing1.xml'), isFalse);
    });

    test('con logo inserta la imagen y el sello de aprobación', () {
      final datos = GdPlantillaFormatoDatos(
        empresaNombre: 'UT Alfa',
        titulo: 'Lista de chequeo <cocina>',
        codigo: 'NUT-003',
        dependencia: 'Nutrición',
        version: 'v2',
        fecha: DateTime(2026, 9, 14),
        aprobadoPor: 'María Pérez',
        aprobadoEn: DateTime(2026, 9, 15, 10, 30),
        logo: _pngDePrueba(),
        colorPrimario: '#AABBCC',
        colorSecundario: 'no-es-hex',
      );
      final xlsx = gdGenerarPlantillaFormato(datos);
      final partes = _partes(xlsx);
      final hoja = partes['xl/worksheets/sheet1.xml']!;
      final dibujo = partes['xl/drawings/drawing1.xml']!;

      expect(hoja, contains('<drawing r:id="rId1"/>'));
      expect(hoja, contains('Lista de chequeo &lt;cocina&gt;'));
      expect(hoja, contains('María Pérez · 15/09/2026'));
      expect(dibujo, contains('<xdr:oneCellAnchor>'));
      expect(dibujo, contains('noChangeAspect="1"'));
      expect(partes['xl/drawings/_rels/drawing1.xml.rels'], contains('image1.png'));
      expect(partes['[Content_Types].xml'], contains('Extension="png"'));
      expect(
        ZipDecoder().decodeBytes(xlsx).files.any((f) => f.name == 'xl/media/image1.png'),
        isTrue,
      );
      // Color válido se usa; inválido cae al defecto.
      expect(partes['xl/styles.xml'], contains('FFAABBCC'));
      expect(partes['xl/styles.xml'], contains('FF$kGdPlantillaColorSecundario'));
      // Logo 4x2 dentro de un recuadro más alto que ancho: se escala al
      // ancho y conserva proporción 2:1.
      final ext = RegExp(r'<xdr:ext cx="(\d+)" cy="(\d+)"/>').firstMatch(dibujo)!;
      expect(int.parse(ext.group(1)!), int.parse(ext.group(2)!) * 2);
    });

    test('un logo que no es imagen se ignora sin romper el archivo', () {
      final datos = GdPlantillaFormatoDatos(
        empresaNombre: 'UT Alfa',
        titulo: 'X',
        codigo: 'X-1',
        dependencia: 'X',
        version: 'v1',
        fecha: DateTime(2026, 1, 1),
        logo: Uint8List.fromList(List.filled(64, 7)),
      );
      final partes = _partes(gdGenerarPlantillaFormato(datos));
      expect(partes.containsKey('xl/drawings/drawing1.xml'), isFalse);
    });

    test('nombre de archivo legible', () {
      expect(
        gdNombreArchivoPlantilla(
          GdPlantillaFormatoDatos(
            empresaNombre: '',
            titulo: '  Acta de baja / mercancía  ',
            codigo: 'LOG-001',
            dependencia: '',
            version: 'v1',
            fecha: DateTime(2026),
          ),
        ),
        'LOG-001_Acta_de_baja_mercancía_v1.xlsx',
      );
    });
  });
}
