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
      expect(gdIsInstitutionalFormat('Política'), isTrue);
      expect(gdIsInstitutionalFormat('Formato'), isTrue);
      expect(gdIsInstitutionalFormat('Documento contractual'), isFalse);
      expect(gdIsInstitutionalFormat('Norma aplicable'), isFalse);
      // Contrato y normograma se publican al cargarlos; solo formatos llevan flujo.
      expect(gdIsReferenceDocument('RUT'), isTrue);
      expect(gdIsReferenceDocument('Ley'), isTrue);
      expect(gdIsReferenceDocument('Formato'), isFalse);
      expect(gdIsReferenceDocument(null), isFalse);
      expect(GdRoles.puedeEjecutar('validar_formato', GdRoles.revisor), isTrue);
      expect(
        GdRoles.puedeEjecutar('validar_formato', GdRoles.redactor),
        isFalse,
      );
    });

    test('genera código por área (formatos) o tipo (contrato y normas)', () {
      expect(
        gdNextDocumentCode(
          prefix: gdDepartmentPrefix('Talento Humano'),
          existingCodes: const ['TAL-001', 'TAL-004', 'CAL-010'],
        ),
        'TAL-005',
      );
      expect(gdDepartmentPrefix('Gestión Ambiental'), 'GA');
      expect(
        gdCodePrefixFor(
          section: GdLibrarySection.formatos,
          area: 'Calidad',
          categoria: 'Formato',
        ),
        'CAL',
      );
      // Contrato y normograma no piden área: el prefijo sale del tipo.
      expect(
        gdCodePrefixFor(
          section: GdLibrarySection.contrato,
          area: '',
          categoria: 'Documentación interna',
        ),
        'DIN',
      );
      expect(
        gdCodePrefixFor(
          section: GdLibrarySection.normograma,
          area: '',
          categoria: 'Resolución',
        ),
        'RES',
      );
      expect(gdContractCategories, contains('Documentacion interna'));
      expect(gdContractFolders.first, 'Documentos básicos');
    });

    test(
      'el título sale en mayúscula aunque se haya guardado en minúscula',
      () {
        final doc = DocumentoDoc.fromMap('x', {
          'empresaId': 'e1',
          'codigo': 'RES-001',
          'titulo': '  Estatuto general de contratación ',
        });
        expect(doc.titulo, 'ESTATUTO GENERAL DE CONTRATACIÓN');
      },
    );

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

    test(
      'busca documentos contractuales por carpeta, alias y código externo',
      () {
        final document = DocumentoDoc.fromMap('contrato', {
          'empresaId': 'empresa',
          'codigo': 'JUR-001',
          'titulo': 'Lineamiento de alimentación',
          'categoria': 'Documento contractual',
          'carpeta': 'Nutricionales',
          'alias': 'Manejo de fiambreras para PPL',
          'codigoExterno': 'Resolución USPEC 001-26',
          'versionActual': 'v1',
          'estado': 'borrador',
          'creadoPor': 'redactor',
        });

        expect(gdDocumentMatchesQuery(document, 'nutricionales'), isTrue);
        expect(gdDocumentMatchesQuery(document, 'FIAMBRERAS'), isTrue);
        expect(gdDocumentMatchesQuery(document, 'USPEC 001-26'), isTrue);
        expect(document.toMap()['codigoExterno'], 'Resolución USPEC 001-26');
        expect(document.copyWith(carpeta: 'Jurídicas').carpeta, 'Jurídicas');
      },
    );

    test('busca el normograma por número de ley y tema', () {
      final norm = DocumentoDoc.fromMap('norma', {
        'empresaId': 'empresa',
        'codigo': 'CAL-001',
        'titulo': 'Dotación de elementos para PPL',
        'categoria': 'Ley',
        'codigoExterno': 'Ley 123 de 2026',
        'versionActual': 'v1',
        'estado': 'borrador',
        'creadoPor': 'redactor',
      });

      expect(gdDocumentMatchesQuery(norm, 'Ley 123'), isTrue);
      expect(gdDocumentMatchesQuery(norm, 'dotacion PPL'), isTrue);
      expect(gdSectionForCategory(norm.categoria), GdLibrarySection.normograma);
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
