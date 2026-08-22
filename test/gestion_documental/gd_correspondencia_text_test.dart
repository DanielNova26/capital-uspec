import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_text.dart';

void main() {
  test('convierte HTML y entidades a texto visible', () {
    expect(
      gdTextoCorreoLegible(
        '<html><body><p>Señores&nbsp;Capital &amp; Asociados</p>'
        '<p>Solicitud de información</p></body></html>',
      ),
      'Señores Capital & Asociados\nSolicitud de información',
    );
  });

  test('corrige texto UTF-8 interpretado como Windows-1252', () {
    expect(
      gdTextoCorreoLegible('Solicitud de informaciÃ³n y atenciÃ³n'),
      'Solicitud de información y atención',
    );
  });

  test('no modifica texto Unicode correcto', () {
    const original = 'Respuesta válida — próxima revisión: 12/08/2026';
    expect(gdTextoCorreoLegible(original), original);
  });
}
