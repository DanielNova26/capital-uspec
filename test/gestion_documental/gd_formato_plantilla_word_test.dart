import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla_word.dart';

/// 5 oct 2026: "así como me permite generar el Excel cuando quiero cargar un
/// formato, así mismo me permita un Word, con las mismas especificaciones,
/// el mismo encabezado y un pie de página bonito".

/// PNG de 4x2 px: el generador solo lee ancho y alto de la cabecera.
Uint8List _pngDePrueba() {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.add([0, 0, 0, 13]);
  b.add(ascii.encode('IHDR'));
  b.add([0, 0, 0, 4, 0, 0, 0, 2, 8, 6, 0, 0, 0]);
  b.add([0, 0, 0, 0]);
  b.add([0, 0, 0, 0]);
  b.add(ascii.encode('IEND'));
  b.add([0xAE, 0x42, 0x60, 0x82]);
  return b.toBytes();
}

Map<String, List<int>> _archivos(Uint8List docx) => {
  for (final f in ZipDecoder().decodeBytes(docx).files)
    if (f.isFile) f.name: f.content as List<int>,
};

Map<String, String> _partes(Uint8List docx) => {
  for (final e in _archivos(docx).entries)
    if (e.key.endsWith('.xml') || e.key.endsWith('.rels'))
      e.key: utf8.decode(e.value),
};

GdPlantillaFormatoDatos _datos({
  Uint8List? logo,
  String tipo = 'Formato',
  String titulo = 'Acta de baja',
  String? aprobadoPor,
  String colorPrimario = kGdPlantillaColorPrimario,
}) => GdPlantillaFormatoDatos(
  empresaNombre: 'Capital USPEC',
  tipo: tipo,
  titulo: titulo,
  codigo: 'LOG-001',
  area: 'Logística',
  version: 'v2',
  fecha: DateTime(2026, 10, 5),
  aprobadoPor: aprobadoPor,
  logo: logo,
  colorPrimario: colorPrimario,
);

void main() {
  test('el nombre del archivo es el del Excel, en .docx', () {
    expect(
      gdNombreArchivoPlantillaWord(_datos()),
      'LOG-001_Acta_de_baja_v2.docx',
    );
  });

  test('es un Word con encabezado y pie en todas las páginas', () {
    final p = _partes(gdGenerarPlantillaFormatoWord(_datos()));
    expect(
      p.keys,
      containsAll([
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/_rels/document.xml.rels',
        'word/styles.xml',
        'word/settings.xml',
        'word/header1.xml',
        'word/footer1.xml',
        'docProps/core.xml',
      ]),
    );
    final tipos = p['[Content_Types].xml']!;
    expect(tipos, contains('wordprocessingml.document.main+xml'));
    expect(tipos, contains('/word/header1.xml'));
    expect(tipos, contains('/word/footer1.xml'));
    final documento = p['word/document.xml']!;
    expect(
      documento,
      contains('<w:headerReference w:type="default" r:id="rId3"/>'),
    );
    expect(
      documento,
      contains('<w:footerReference w:type="default" r:id="rId4"/>'),
    );
    // Carta vertical, como el Excel.
    expect(documento, contains('<w:pgSz w:w="12240" w:h="15840"/>'));
    final rels = p['word/_rels/document.xml.rels']!;
    expect(rels, contains('Id="rId3"'));
    expect(rels, contains('Target="header1.xml"'));
    expect(rels, contains('Target="footer1.xml"'));
  });

  test('el encabezado trae los mismos datos y la misma forma del Excel', () {
    final h = _partes(
      gdGenerarPlantillaFormatoWord(_datos()),
    )['word/header1.xml']!;
    // Tipo y título en mayúscula; área, versión, fecha y código.
    expect(h, contains('>FORMATO<'));
    expect(h, contains('>ACTA DE BAJA<'));
    expect(h, contains('>Logística<'));
    for (final etiqueta in ['Versión', 'Aprobado', 'Fecha', 'Código']) {
      expect(h, contains('>$etiqueta<'));
    }
    expect(h, contains('>v2<'));
    expect(h, contains('>05/10/2026<'));
    expect(h, contains('>LOG-001<'));
    // Sin validar: "Pendiente", en el control que sella Calidad.
    expect(h, contains('<w:tag w:val="$kGdPlantillaWordEtiquetaAprobado"/>'));
    expect(h, contains('<w:lock w:val="sdtContentLocked"/>'));
    expect(h, contains('>Pendiente<'));
    // Logo en las cuatro filas y título en dos (combinación vertical).
    expect('w:vMerge w:val="restart"'.allMatches(h).length, 2);
    expect('w:vMerge w:val="continue"'.allMatches(h).length, 4);
    // Bordes finos del primario y etiquetas sobre el secundario.
    expect(h, contains('w:color="$kGdPlantillaColorPrimario"'));
    expect(h, contains('w:fill="$kGdPlantillaColorSecundario"'));
    // Sin logo, el nombre de la empresa en su recuadro.
    expect(h, contains('>Capital USPEC<'));
    expect(h, isNot(contains('<w:drawing>')));
  });

  test('con logo lo incrusta en el encabezado sin deformarlo', () {
    final docx = gdGenerarPlantillaFormatoWord(_datos(logo: _pngDePrueba()));
    final archivos = _archivos(docx);
    expect(archivos.keys, contains('word/media/logo.png'));
    final p = _partes(docx);
    expect(p['[Content_Types].xml'], contains('Extension="png"'));
    expect(
      p['word/_rels/header1.xml.rels'],
      contains('Target="media/logo.png"'),
    );
    final h = p['word/header1.xml']!;
    expect(h, contains('r:embed="rIdLogo"'));
    final ext = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"/>').firstMatch(h)!;
    final cx = int.parse(ext.group(1)!);
    final cy = int.parse(ext.group(2)!);
    expect(cx / cy, closeTo(2, 0.01)); // 4x2 px
    expect(h, isNot(contains('>Capital USPEC<')));
  });

  test('el pie lleva empresa, código, versión y "Página X de Y"', () {
    final f = _partes(
      gdGenerarPlantillaFormatoWord(_datos()),
    )['word/footer1.xml']!;
    expect(f, contains('>CAPITAL USPEC<'));
    expect(f, contains('>LOG-001 · Versión v2<'));
    expect(f, contains(' PAGE '));
    expect(f, contains(' NUMPAGES '));
    expect(f, contains('<w:pBdr><w:top w:val="single"'));
  });

  test('ya validado muestra quién; el tipo vacío deja la empresa', () {
    final h = _partes(
      gdGenerarPlantillaFormatoWord(_datos(tipo: '', aprobadoPor: 'Ana Ruiz')),
    )['word/header1.xml']!;
    expect(h, contains('>Ana Ruiz<'));
    expect(h, isNot(contains('>Pendiente<')));
    expect(h, contains('>CAPITAL USPEC<'));
  });

  test('colores de la empresa y textos con símbolos', () {
    final p = _partes(
      gdGenerarPlantillaFormatoWord(
        _datos(titulo: 'Entrega & recibo <obra>', colorPrimario: '#1a7f37'),
      ),
    );
    expect(
      p['word/header1.xml'],
      contains('ENTREGA &amp; RECIBO &lt;OBRA&gt;'),
    );
    expect(p['word/header1.xml'], contains('w:color="1A7F37"'));
    expect(p['word/styles.xml'], contains('w:color="1A7F37"'));
    final otro = _partes(
      gdGenerarPlantillaFormatoWord(_datos(colorPrimario: 'azul')),
    );
    expect(
      otro['word/header1.xml'],
      contains('w:color="$kGdPlantillaColorPrimario"'),
    );
  });

  group('sello de Calidad en el Word', () {
    test('escribe quién validó y deja lo demás igual', () {
      final original = gdGenerarPlantillaFormatoWord(
        _datos(logo: _pngDePrueba()),
      );
      final r = gdSellarPlantillaWordValidada(
        original,
        aprobadoPor: 'Daniel Nova',
        aprobadoEn: DateTime(2026, 10, 5, 10),
      );
      expect(r.bytes, isNotNull, reason: r.detalle);
      final antes = _archivos(original);
      final despues = _archivos(r.bytes!);
      expect(despues.keys.toSet(), antes.keys.toSet());
      for (final k in antes.keys) {
        if (k == 'word/header1.xml') continue;
        expect(despues[k], antes[k], reason: k);
      }
      final h = utf8.decode(despues['word/header1.xml']!);
      expect(h, contains('>Daniel Nova<'));
      expect(h, isNot(contains('>Pendiente<')));
      expect(h, contains('<w:tag w:val="$kGdPlantillaWordEtiquetaAprobado"/>'));
    });

    test('funciona aunque Word haya partido el texto y movido el control', () {
      // Así puede quedar después de guardar en Word: el control en el
      // documento, con el texto en varios trozos y otro formato.
      const documento =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body><w:p><w:sdt><w:sdtPr><w:alias w:val="Aprobado"/>'
          '<w:tag w:val="gdAprobado"/><w:id w:val="99"/></w:sdtPr>'
          '<w:sdtContent><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t>Pen</w:t></w:r>'
          '<w:r><w:t>diente</w:t></w:r></w:sdtContent></w:sdt></w:p></w:body></w:document>';
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'word/document.xml',
            utf8.encode(documento).length,
            utf8.encode(documento),
          ),
        );
      final docx = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final r = gdSellarPlantillaWordValidada(
        docx,
        aprobadoPor: 'Calidad & Co',
        aprobadoEn: DateTime(2026, 10, 5),
      );
      final xml = utf8.decode(_archivos(r.bytes!)['word/document.xml']!);
      expect(
        xml,
        contains(
          '<w:sdtContent><w:r><w:rPr><w:sz w:val="16"/></w:rPr>'
          '<w:t xml:space="preserve">Calidad &amp; Co</w:t></w:r></w:sdtContent>',
        ),
      );
      expect(xml, isNot(contains('diente')));
    });

    test('sella cada copia del encabezado (primera página y demás)', () {
      String encabezado(String texto) =>
          '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:p><w:sdt><w:sdtPr><w:tag w:val="gdAprobado"/></w:sdtPr>'
          '<w:sdtContent><w:r><w:t>$texto</w:t></w:r></w:sdtContent></w:sdt></w:p>'
          '<w:p><w:sdt><w:sdtPr><w:tag w:val="gdAprobado"/></w:sdtPr>'
          '<w:sdtContent><w:r><w:t>$texto</w:t></w:r></w:sdtContent></w:sdt></w:p>'
          '</w:hdr>';
      final archive = Archive();
      for (final n in ['word/header2.xml', 'word/header3.xml']) {
        final bytes = utf8.encode(encabezado('Pendiente'));
        archive.addFile(ArchiveFile(n, bytes.length, bytes));
      }
      final r = gdSellarPlantillaWordValidada(
        Uint8List.fromList(ZipEncoder().encode(archive)!),
        aprobadoPor: 'Ana Ruiz',
        aprobadoEn: DateTime(2026, 10, 5),
      );
      final archivos = _archivos(r.bytes!);
      for (final n in ['word/header2.xml', 'word/header3.xml']) {
        final xml = utf8.decode(archivos[n]!);
        expect('>Ana Ruiz<'.allMatches(xml).length, 2, reason: n);
        expect(xml, isNot(contains('Pendiente')));
      }
    });

    test('sin el encabezado de la plantilla o sin ser Word, no sella', () {
      final excel = gdGenerarPlantillaFormato(_datos());
      expect(
        gdSellarPlantillaWordValidada(
          excel,
          aprobadoPor: 'Ana',
          aprobadoEn: DateTime(2026),
        ).detalle,
        contains('no conserva el encabezado'),
      );
      final r = gdSellarPlantillaWordValidada(
        Uint8List.fromList(utf8.encode('esto no es un zip')),
        aprobadoPor: 'Ana',
        aprobadoEn: DateTime(2026),
      );
      expect(r.bytes, isNull);
      expect(r.detalle, contains('no es un .docx'));
    });
  });
}
