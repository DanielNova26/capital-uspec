import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/plantilla_combinacion.dart';

/// Envuelve trozos de texto en la estructura mínima de un párrafo de Word.
/// Cada elemento de [nodos] es un `<w:t>` distinto: así se reproduce el corte
/// en `<w:r>` que Word hace por su cuenta.
String parrafo(List<String> nodos) {
  final runs = nodos
      .map((texto) => '<w:r><w:t>$texto</w:t></w:r>')
      .join();
  return '<w:p>$runs</w:p>';
}

/// Documento .docx mínimo pero real: un zip con `word/document.xml`.
Uint8List docx(String cuerpo) {
  final archivo = Archive();
  void agregar(String nombre, String contenido) {
    final bytes = utf8.encode(contenido);
    archivo.addFile(ArchiveFile(nombre, bytes.length, bytes));
  }

  agregar(
    '[Content_Types].xml',
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/'
        'package/2006/content-types"/>',
  );
  agregar('word/document.xml', '<?xml version="1.0"?><w:document><w:body>'
      '$cuerpo</w:body></w:document>');
  return Uint8List.fromList(ZipEncoder().encode(archivo)!);
}

String textoDe(Uint8List generado) {
  final archivo = ZipDecoder().decodeBytes(generado);
  final documento = archivo.files.firstWhere(
    (f) => f.name == 'word/document.xml',
  );
  final xml = utf8.decode(documento.content as List<int>);
  // Se desescapa igual que haría Word al abrirlo: lo que se compara en los
  // tests es el texto que ve la persona, no el XML.
  return RegExp(r'<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>')
      .allMatches(xml)
      .map((m) => m.group(1)!)
      .join()
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

void main() {
  group('normalización de claves', () {
    test('iguala la plantilla con el encabezado del Excel', () {
      // La columna del Excel y el marcador de Word casi nunca se escriben
      // igual: sobra un espacio, falta una tilde, cambia la mayúscula.
      expect(normalizarClave(' Primer Nombre '), 'PRIMER_NOMBRE');
      expect(normalizarClave('PRIMER NOMBRE'), 'PRIMER_NOMBRE');
      expect(normalizarClave('Número de Documento'), 'NUMERO_DE_DOCUMENTO');
      expect(normalizarClave('CÉDULA'), 'CEDULA');
      expect(normalizarClave('Año/Mes'), 'ANO_MES');
    });

    test('no deja separadores colgando en los extremos', () {
      expect(normalizarClave('  ¿Cargo?  '), 'CARGO');
      expect(normalizarClave('---'), '');
    });
  });

  group('reemplazo dentro del XML de Word', () {
    test('reemplaza un marcador que cabe en un solo nodo', () {
      final xml = parrafo(['Señor {{NOMBRE}}, buenas.']);
      final salida = reemplazarEnXml(xml, {'NOMBRE': 'JUAN PÉREZ'});
      expect(salida, contains('Señor JUAN PÉREZ, buenas.'));
      expect(salida, isNot(contains('{{')));
    });

    test('reemplaza un marcador partido entre varios nodos', () {
      // Este es el caso que rompe cualquier reemplazo directo sobre el XML:
      // Word parte el marcador aunque se haya escrito de una sentada.
      final xml = parrafo(['Señor {{NOM', 'BRE', '}}, buenas.']);
      final salida = reemplazarEnXml(xml, {'NOMBRE': 'JUAN PÉREZ'});
      expect(textoDe(docx(salida)), 'Señor JUAN PÉREZ, buenas.');
    });

    test('reemplaza un marcador partido carácter por carácter', () {
      final xml = parrafo(['{', '{', 'C', 'A', 'R', 'G', 'O', '}', '}']);
      final salida = reemplazarEnXml(xml, {'CARGO': 'CONTADORA'});
      expect(textoDe(docx(salida)), 'CONTADORA');
    });

    test('respeta el texto que rodea al marcador en cada nodo', () {
      final xml = parrafo(['Cargo: {{CAR', 'GO}} — vigente']);
      final salida = reemplazarEnXml(xml, {'CARGO': 'AUXILIAR'});
      expect(textoDe(docx(salida)), 'Cargo: AUXILIAR — vigente');
    });

    test('reemplaza varios marcadores en el mismo párrafo', () {
      final xml = parrafo(['{{NOMBRE}} con CC {{CEDULA}} en {{CARGO}}']);
      final salida = reemplazarEnXml(xml, {
        'NOMBRE': 'ANA',
        'CEDULA': '1010',
        'CARGO': 'AUXILIAR',
      });
      expect(textoDe(docx(salida)), 'ANA con CC 1010 en AUXILIAR');
    });

    test('un marcador no cruza de un párrafo a otro', () {
      // Un "{{" suelto en un párrafo y un "}}" suelto en otro no pueden
      // emparejarse: eso borraría todo el texto intermedio.
      final xml = '${parrafo(['Inicio {{ suelto'])}${parrafo(['final }} fin'])}';
      final salida = reemplazarEnXml(xml, {'SUELTO': 'X'});
      expect(textoDe(docx(salida)), 'Inicio {{ suelto' 'final }} fin');
    });

    test('deja intacto el marcador que ninguna columna alimenta', () {
      // Preferimos que salga impreso "{{SUELDO}}" a que salga un vacío
      // silencioso: así Talento Humano ve que le faltó una columna.
      final xml = parrafo(['{{NOMBRE}} gana {{SUELDO}}']);
      final salida = reemplazarEnXml(xml, {'NOMBRE': 'ANA'});
      expect(textoDe(docx(salida)), 'ANA gana {{SUELDO}}');
    });

    test('escapa los caracteres que romperían el XML', () {
      final xml = parrafo(['{{EMPRESA}}']);
      final salida = reemplazarEnXml(xml, {'EMPRESA': 'Pérez & Cía <SAS>'});
      expect(salida, contains('&amp;'));
      expect(salida, contains('&lt;SAS&gt;'));
      // Y al releerlo vuelve a ser el texto original.
      expect(textoDe(docx(salida)), 'Pérez & Cía <SAS>');
    });

    test('preserva los espacios de los extremos', () {
      // Sin xml:space="preserve" Word recorta y queda "SeñorANA".
      final xml = parrafo(['Señor ', '{{NOMBRE}}']);
      final salida = reemplazarEnXml(xml, {'NOMBRE': 'ANA'});
      expect(salida, contains('xml:space="preserve"'));
      expect(textoDe(docx(salida)), 'Señor ANA');
    });

    test('no toca un documento sin marcadores', () {
      final xml = parrafo(['Un texto cualquiera.']);
      expect(reemplazarEnXml(xml, {'NOMBRE': 'ANA'}), xml);
    });
  });

  group('plantilla .docx completa', () {
    test('lista los marcadores aunque estén partidos', () {
      final plantilla = docx(
        '${parrafo(['{{NOM', 'BRE}}'])}${parrafo(['{{ Cargo }}'])}',
      );
      expect(marcadoresDePlantilla(plantilla), {'NOMBRE', 'CARGO'});
    });

    test('genera un .docx válido con los valores puestos', () {
      final plantilla = docx(parrafo(['Yo, {{NOMBRE}}, {{CARGO}}.']));
      final generado = generarDocumento(plantilla, {
        'NOMBRE': 'ANA GÓMEZ',
        'CARGO': 'CONTADORA',
      });
      expect(textoDe(generado), 'Yo, ANA GÓMEZ, CONTADORA.');
      // El resto del paquete tiene que seguir ahí, o Word no abre el archivo.
      final partes = ZipDecoder()
          .decodeBytes(generado)
          .files
          .map((f) => f.name)
          .toSet();
      expect(partes, contains('[Content_Types].xml'));
      expect(partes, contains('word/document.xml'));
    });
  });

  group('combinación por lote', () {
    DatosCombinacion datos(List<Map<String, String>> filas) =>
        DatosCombinacion(
          encabezados: filas.isEmpty ? [] : filas.first.keys.toList(),
          filas: [
            for (var i = 0; i < filas.length; i++)
              FilaCombinacion(
                valores: {
                  for (final e in filas[i].entries)
                    normalizarClave(e.key): e.value,
                },
                numero: i + 1,
              ),
          ],
        );

    test('produce un documento por fila, con su nombre', () {
      final plantilla = docx(parrafo(['{{NOMBRE}} — {{CARGO}}']));
      final resultado = combinar(
        plantilla: plantilla,
        datos: datos([
          {'Cedula': '1010', 'Nombre': 'Ana Gómez', 'Cargo': 'Contadora'},
          {'Cedula': '2020', 'Nombre': 'Luis Ruiz', 'Cargo': 'Auxiliar'},
        ]),
      );

      expect(resultado.documentos, hasLength(2));
      expect(resultado.errores, isEmpty);
      expect(resultado.documentos.first.nombreArchivo, '1010 - Ana Gómez.docx');
      expect(textoDe(resultado.documentos.first.bytes), 'Ana Gómez — Contadora');
      expect(textoDe(resultado.documentos.last.bytes), 'Luis Ruiz — Auxiliar');
    });

    test('avisa qué marcadores no tienen columna que los llene', () {
      final plantilla = docx(parrafo(['{{NOMBRE}} gana {{SUELDO}}']));
      final resultado = combinar(
        plantilla: plantilla,
        datos: datos([
          {'Nombre': 'Ana'},
        ]),
      );
      expect(resultado.marcadoresSinDato, ['SUELDO']);
      expect(resultado.documentos, hasLength(1));
    });

    test('dos personas sin cédula ni nombre no se pisan en el zip', () {
      final plantilla = docx(parrafo(['{{CARGO}}']));
      final resultado = combinar(
        plantilla: plantilla,
        datos: datos([
          {'Cargo': 'Auxiliar'},
          {'Cargo': 'Contadora'},
        ]),
      );
      final nombres = resultado.documentos
          .map((d) => d.nombreArchivo)
          .toList();
      expect(nombres.toSet(), hasLength(2));
    });

    test('el zip trae todos los documentos generados', () {
      final plantilla = docx(parrafo(['{{NOMBRE}}']));
      final resultado = combinar(
        plantilla: plantilla,
        datos: datos([
          {'Cedula': '1010', 'Nombre': 'Ana'},
          {'Cedula': '2020', 'Nombre': 'Luis'},
        ]),
      );
      final zip = ZipDecoder().decodeBytes(empaquetarZip(resultado.documentos));
      expect(zip.files.map((f) => f.name).toSet(), {
        '1010 - Ana.docx',
        '2020 - Luis.docx',
      });
    });
  });
}
