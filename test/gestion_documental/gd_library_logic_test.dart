import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_library_logic.dart';
import 'package:todo/gestion_documental/gd_models.dart';

void main() {
  group('estructura de Biblioteca Documental', () {
    test('separa formatos, contrato y normograma', () {
      expect(gdSectionForCategory('Formato'), GdLibrarySection.formatos);
      expect(
        gdSectionForCategory('Certificado de existencia'),
        GdLibrarySection.contrato,
      );
      expect(gdSectionForCategory('Resolución'), GdLibrarySection.normograma);
    });

    test('genera código por dependencia y consecutivo', () {
      expect(
        gdNextDocumentCode(
          area: 'Talento Humano',
          existingCodes: const ['TAL-001', 'TAL-004', 'CAL-010'],
        ),
        'TAL-005',
      );
      expect(gdDepartmentPrefix('Gestión Ambiental'), 'GA');
    });

    test('normaliza palabras clave sin duplicarlas', () {
      expect(
        gdNormalizeKeywords(
          'Compras locales, dotación; compras locales\nGuantes',
        ),
        ['Compras locales', 'dotación', 'Guantes'],
      );
    });

    test('busca por palabras clave y calcula documentos asociados', () {
      final norm = _doc(
        id: 'norma',
        title: 'Resolución de dotación',
        category: 'Norma aplicable',
        keywords: const ['dotación', 'guantes'],
      );
      final format = _doc(
        id: 'formato',
        title: 'Entrega de elementos',
        category: 'Formato',
        keywords: const ['guantes'],
      );

      expect(gdDocumentMatchesQuery(norm, 'DOTACION'), isTrue);
      expect(gdRelatedDocumentsCount(norm, [norm, format]), 1);
    });

    test('el modelo conserva palabras clave y fecha de aprobación', () {
      final approvedAt = Timestamp.now();
      final document = DocumentoDoc.fromMap('doc', {
        'empresaId': 'empresa',
        'codigo': 'CAL-001',
        'titulo': 'Formato aprobado',
        'palabrasClave': ['calidad', 'formato'],
        'versionActual': 'v1',
        'estado': 'aprobado',
        'creadoPor': 'redactor',
        'aprobadoPor': 'calidad',
        'aprobadoEn': approvedAt,
      });

      expect(document.palabrasClave, ['calidad', 'formato']);
      expect(document.aprobadoPor, 'calidad');
      expect(document.aprobadoEn, approvedAt);
    });
  });
}

DocumentoDoc _doc({
  required String id,
  required String title,
  required String category,
  List<String> keywords = const [],
}) {
  return DocumentoDoc(
    docId: id,
    empresaId: 'empresa',
    codigo: 'DOC-001',
    titulo: title,
    categoria: category,
    palabrasClave: keywords,
    versionActual: 'v1',
    estado: GdEstado.borrador,
    creadoPor: 'usuario',
    createdAt: Timestamp.now(),
  );
}
