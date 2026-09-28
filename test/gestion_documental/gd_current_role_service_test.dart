import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/gd_service.dart';
import 'package:todo/services/task_service.dart';

import '../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {}

void main() {
  late MemoryFirestore db;
  late GdService service;
  setUp(() {
    db = MemoryFirestore();
    final storage = _Storage();
    service = GdService(
      db: db,
      storage: storage,
      taskService: TaskService(db: db, storage: storage),
    );
    db.documents['TBL_USUARIOS/persona'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'rolDocumental': 'admin_doc',
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{
          'activo': true,
          'apps': ['bibliotecadocumentaldashboard'],
          'rolDocumental': 'redactor',
        },
        'B': <String, dynamic>{
          'activo': true,
          'apps': ['bibliotecadocumentaldashboard'],
        },
      },
    };
  });
  Future<void> save({String empresaId = 'A', String role = 'redactor'}) =>
      service.actualizarClasificacionBiblioteca(
        docId: 'doc',
        empresaId: empresaId,
        actorId: 'persona',
        rolDocumental: role,
        carpeta: 'Contratos',
        alias: 'Mi documento',
        codigoExterno: '',
      );
  Matcher denied() => throwsA(
    isA<GdException>().having((e) => e.mensaje, 'mensaje', contains('cambió')),
  );

  test(
    'formulario con rol viejo se rechaza después de restringir el nivel',
    () async {
      db.documents['TBL_USUARIOS/persona']!['empresasDetalle']['A']['rolDocumental'] =
          'consulta';
      await expectLater(save(), denied());
      expect(db.writes, 0);
    },
  );

  test(
    'no acepta rol administrativo proporcionado sin ese nivel efectivo',
    () async {
      await expectLater(save(role: 'admin_doc'), denied());
      expect(db.writes, 0);
    },
  );

  test('no usa el rol de la principal para escribir en otra empresa', () async {
    await expectLater(save(empresaId: 'B', role: 'admin_doc'), denied());
    expect(db.writes, 0);
  });

  test(
    'revocación de app y membresía se vuelve a comprobar antes de guardar',
    () async {
      final detail =
          db.documents['TBL_USUARIOS/persona']!['empresasDetalle']['A'];
      detail['apps'] = <String>[];
      await expectLater(save(), denied());
      detail['apps'] = ['bibliotecadocumentaldashboard'];
      detail['activo'] = false;
      await expectLater(save(), denied());
      expect(db.writes, 0);
    },
  );

  test(
    'nivel vigente pasa la comprobación y continúa validando el documento',
    () async {
      await expectLater(
        save(),
        throwsA(
          isA<GdException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('documento no existe'),
          ),
        ),
      );
      expect(db.writes, 0);
    },
  );
}
