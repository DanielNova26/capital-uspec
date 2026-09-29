import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_models.dart';
import 'package:todo/gestion_documental/gd_role_access.dart';
import 'package:todo/utils/user_company.dart';

DocumentoDoc document(GdEstado state, {String empresaId = 'A'}) => DocumentoDoc(
  docId: 'documento',
  empresaId: empresaId,
  codigo: 'DOC-1',
  titulo: 'Documento',
  versionActual: 'v1',
  estado: state,
  creadoPor: 'persona',
);

Map<String, dynamic> user(String level) => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'rolDocumental': 'admin_doc',
  'appsPorEmpresa': true,
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['bibliotecadocumentaldashboard'],
      'rolDocumental': level,
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['gestiondocumentaldashboard'],
    },
  },
};

void main() {
  test(
    'consulta solo recibe la versión publicada de este documento y empresa',
    () {
      VersionDoc version(
        String id,
        GdEstado state, {
        String empresaId = 'A',
        String docId = 'documento',
      }) => VersionDoc(
        versionId: id,
        docId: docId,
        empresaId: empresaId,
        numero: 1,
        etiqueta: 'v1',
        estado: state,
        subidoPor: 'persona',
      );
      final doc = DocumentoDoc.fromMap('documento', {
        'empresaId': 'A',
        'codigo': 'DOC-1',
        'titulo': 'Publicado',
        'versionActual': 'v1',
        'versionVigenteId': 'publicada',
        'estado': 'vigente',
      });
      final versions = [
        version('publicada', GdEstado.vigente),
        version('borrador', GdEstado.borrador),
        version('anterior', GdEstado.obsoleto),
        version('ajena', GdEstado.vigente, empresaId: 'B'),
        version('otro', GdEstado.vigente, docId: 'otro'),
      ];
      expect(gdVersionsForReader(null, doc, versions).map((v) => v.versionId), [
        'publicada',
      ]);
      expect(gdVersionsForReader('revisor', doc, versions), versions);
      expect(
        gdVersionsForReader(null, document(GdEstado.borrador), versions),
        isEmpty,
      );
      expect(
        gdVersionsForReader(
          null,
          document(GdEstado.vigente),
          versions,
        ).map((v) => v.versionId),
        ['publicada'],
      );
    },
  );

  test('cada nivel muestra las acciones reales y consulta carece de flujo', () {
    expect(gdActionsForLevel(gdReadOnlyLevel), isEmpty);
    expect(gdActionsForLevel(GdRoles.redactor).toSet(), {
      'enviar_revision',
      'reenviar',
      'subir_pdf',
      'nueva_version',
    });
    expect(gdActionsForLevel(GdRoles.revisor).toSet(), {
      'observar',
      'validar_formato',
    });
    expect(gdActionsForLevel(GdRoles.aprobador).toSet(), {
      'observar',
      'aprobar',
      'validar_formato',
      'marcar_vigente',
    });
    expect(gdActionsForLevel(GdRoles.firmante).toSet(), {
      'firmar',
      'marcar_vigente',
    });
    expect(gdActionsForLevel(GdRoles.adminDoc).length, 10);
    expect(gdRoleLevelLabels.containsKey('desarrollador'), isFalse);
  });

  test(
    'vacío, consulta y valor desconocido no heredan el administrador raíz',
    () {
      for (final level in ['', gdReadOnlyLevel, 'inventado']) {
        expect(resolveGdDocumentalRole(user(level), 'A'), isNull);
      }
      expect(resolveGdDocumentalRole(user(' FIRmante '), 'A'), 'firmante');
      expect(
        resolveGdDocumentalRole({
          'empresaId': 'A',
          'rolDocumental': 'redactor',
        }, 'A'),
        'redactor',
      );
    },
  );

  test('rol raíz no habilita otra empresa ni hereda la app combinada', () {
    final data = user('admin_doc');
    expect(resolveGdDocumentalRole(data, 'B'), isNull);
    expect(userHasApp(data, 'biblioteca', empresaId: 'B'), isFalse);
    data['empresasDetalle']['B']['rolDocumental'] = 'revisor';
    expect(resolveGdDocumentalRole(data, 'B'), 'revisor');
    expect(userHasApp(data, 'biblioteca', empresaId: 'B'), isTrue);
  });

  test('consulta solo accede a publicados aun por enlace directo', () {
    final reader = user('consulta');
    expect(gdCanReadDocument(reader, 'A', document(GdEstado.vigente)), isTrue);
    for (final state in GdEstado.values.where((s) => s != GdEstado.vigente)) {
      expect(gdCanReadDocument(reader, 'A', document(state)), isFalse);
    }
    expect(
      gdCanReadDocument(
        reader,
        'A',
        document(GdEstado.vigente, empresaId: 'B'),
      ),
      isFalse,
    );
    expect(gdCanReadDocument(null, 'A', document(GdEstado.vigente)), isFalse);
    expect(
      gdCanReadDocument(user('revisor'), 'A', document(GdEstado.en_revision)),
      isTrue,
    );
  });

  test(
    'revocar app o membresía impide lectura y el desarrollador conserva su bypass',
    () {
      final revoked = user('admin_doc');
      revoked['empresasDetalle']['A']['apps'] = <String>[];
      expect(
        gdCanReadDocument(revoked, 'A', document(GdEstado.vigente)),
        isFalse,
      );
      revoked['empresasDetalle']['A']['activo'] = false;
      expect(resolveGdDocumentalRole(revoked, 'A'), isNull);
      final developer = user('')..['role'] = 'desarrollador';
      expect(resolveGdDocumentalRole(developer, 'A'), GdRoles.desarrollador);
      expect(
        gdCanReadDocument(developer, 'A', document(GdEstado.borrador)),
        isTrue,
      );
    },
  );
}
