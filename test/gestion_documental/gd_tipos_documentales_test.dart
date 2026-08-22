import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';

/// El código del tipo documental es la raíz del código interno del expediente
/// (`TUT100826-001`), así que lo que se garantiza aquí es que dos personas
/// escribiendo lo mismo de formas distintas obtengan el mismo código, y que
/// nunca salga un código con caracteres que rompan el formato.
void main() {
  group('GdTipoDocumental.normalizarCodigo', () {
    test('pasa a mayúsculas y descarta espacios y signos', () {
      expect(GdTipoDocumental.normalizarCodigo(' tut '), 'TUT');
      expect(GdTipoDocumental.normalizarCodigo('d-p.e'), 'DPE');
      expect(GdTipoDocumental.normalizarCodigo('r q 1'), 'RQ1');
    });

    test('quita acentos y la ñ en vez de descartar la letra', () {
      expect(GdTipoDocumental.normalizarCodigo('cál'), 'CAL');
      expect(GdTipoDocumental.normalizarCodigo('ñom'), 'NOM');
      expect(GdTipoDocumental.normalizarCodigo('Ú'), 'U');
    });

    test('corta estrictamente en tres caracteres', () {
      expect(GdTipoDocumental.normalizarCodigo('requerimiento'), 'REQ');
    });

    test('deja vacío lo que no aporta ningún caracter válido', () {
      expect(GdTipoDocumental.normalizarCodigo('--- ...'), '');
    });
  });

  group('GdTipoDocumental.codigoSugerido', () {
    test('propone las primeras tres letras del nombre', () {
      expect(GdTipoDocumental.codigoSugerido('Tutela'), 'TUT');
      expect(GdTipoDocumental.codigoSugerido('Solicitud'), 'SOL');
      expect(GdTipoDocumental.codigoSugerido('Calidad'), 'CAL');
    });

    test('ignora los espacios al tomar las tres primeras letras', () {
      // "Derecho de petición" no debe quedar como "DE " ni "DED".
      expect(GdTipoDocumental.codigoSugerido('Derecho de petición'), 'DER');
    });

    test('devuelve lo que haya cuando el nombre es más corto', () {
      expect(GdTipoDocumental.codigoSugerido('SG'), 'SG');
    });
  });

  group('etiqueta y búsqueda', () {
    const tipo = GdTipoDocumental(
      id: 'EMPRESA_001_TUT',
      empresaId: 'EMPRESA_001',
      codigo: 'TUT',
      nombre: 'Tutela',
      alias: 'tutelas acciones',
    );

    test('la etiqueta muestra código y nombre juntos', () {
      expect(tipo.etiqueta, 'TUT · Tutela');
    });

    test('cae al nombre cuando el registro viejo no tiene código', () {
      const sinCodigo = GdTipoDocumental(
        id: 'x',
        empresaId: 'EMPRESA_001',
        codigo: '',
        nombre: 'Circular',
      );
      expect(sinCodigo.etiqueta, 'Circular');
    });

    test('el texto de búsqueda incluye el alias', () {
      expect(tipo.textoBusqueda.contains('acciones'), isTrue);
      expect(tipo.textoBusqueda.contains('tut'), isTrue);
    });
  });
}
