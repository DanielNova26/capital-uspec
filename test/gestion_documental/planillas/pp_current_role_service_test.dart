import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_service.dart';
import 'package:todo/services/task_service.dart';

import '../../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {}

class _Functions extends Fake implements FirebaseFunctions {}

void main() {
  late MemoryFirestore db;
  late PpService service;
  setUp(() {
    db = MemoryFirestore();
    final storage = _Storage();
    service = PpService(
      db: db,
      storage: storage,
      functions: _Functions(),
      taskService: TaskService(db: db, storage: storage),
    );
    db.documents['TBL_USUARIOS/persona'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'role': 'usuario',
      'rolPlanillas': 'admin_doc',
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{
          'activo': true,
          'apps': ['planillaspagodashboard'],
          'rolPlanillas': 'tesoreria',
        },
        'B': <String, dynamic>{
          'activo': true,
          'apps': ['planillaspagodashboard'],
        },
      },
    };
  });
  Map<String, dynamic> detail() =>
      db.documents['TBL_USUARIOS/persona']!['empresasDetalle']['A'];
  Future<void> save({String empresaId = 'A', String role = 'tesoreria'}) =>
      service.actualizarNombrePlanilla(
        planillaId: 'doc',
        empresaId: empresaId,
        actorId: 'persona',
        rolPlanillas: role,
        nombrePlanilla: 'Pago de septiembre',
      );
  Matcher denied() => throwsA(
    isA<PpException>().having((e) => e.mensaje, 'mensaje', contains('cambió')),
  );

  test('formulario con rol viejo se rechaza al cambiar el nivel', () async {
    detail()['rolPlanillas'] = 'auditoria';
    await expectLater(save(), denied());
    expect(db.writes, 0);
  });
  test('no acepta un nivel administrativo proporcionado por cliente', () async {
    await expectLater(save(role: 'admin_doc'), denied());
    expect(db.writes, 0);
  });
  test('no usa rol de la principal para escribir en otra empresa', () async {
    await expectLater(save(empresaId: 'B', role: 'admin_doc'), denied());
    expect(db.writes, 0);
  });
  test('retirar nivel o membresía se comprueba antes de guardar', () async {
    detail()['rolPlanillas'] = '';
    await expectLater(save(), denied());
    detail()['rolPlanillas'] = 'tesoreria';
    detail()['activo'] = false;
    await expectLater(save(), denied());
    expect(db.writes, 0);
  });
  test(
    'nivel vigente continúa con validación de empresa del documento',
    () async {
      db.documents['TBL_PP_PLANILLAS/doc'] = {'empresaId': 'B', 'loteId': ''};
      await expectLater(
        save(),
        throwsA(
          isA<PpException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('empresa o lote'),
          ),
        ),
      );
      expect(db.writes, 0);
    },
  );
  test('nivel vigente permite guardar y conserva la planilla', () async {
    db.documents['TBL_PP_PLANILLAS/doc'] = {
      'empresaId': 'A',
      'loteId': '',
      'estado': 'cargada',
    };
    await save();
    expect(
      db.documents['TBL_PP_PLANILLAS/doc']!['nombrePlanillaDetectado'],
      'Pago de septiembre',
    );
    expect(db.documents['TBL_PP_PLANILLAS/doc']!['estado'], 'cargada');
  });
  test(
    'Tesorería envía a auditoría y registra historial sin saltar la etapa',
    () async {
      db.documents['TBL_PP_PLANILLAS/doc'] = {
        'empresaId': 'A',
        'loteId': '',
        'estado': 'pendiente_validacion',
      };
      await service.enviarAuditoria(
        planillaId: 'doc',
        empresaId: 'A',
        loteId: '',
        actorId: 'persona',
        rolPlanillas: 'tesoreria',
      );
      expect(
        db.documents['TBL_PP_PLANILLAS/doc']!['estado'],
        'en_revision_auditoria',
      );
      final event = db.documents.entries
          .singleWhere((e) => e.key.startsWith('TBL_PP_FLUJO/'))
          .value;
      expect(event['empresaId'], 'A');
      expect(event['realizadoPor'], 'persona');
      expect(event['planillaId'], 'doc');
      await expectLater(
        service.enviarAuditoria(
          planillaId: 'doc',
          empresaId: 'A',
          loteId: '',
          actorId: 'persona',
          rolPlanillas: 'tesoreria',
        ),
        throwsA(
          isA<PpException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Estado actual'),
          ),
        ),
      );
      expect(
        db.documents.keys
            .where((path) => path.startsWith('TBL_PP_FLUJO/'))
            .length,
        1,
      );
    },
  );

  test(
    'gerencia no puede aprobar auditoría y se conserva la excepción de logo',
    () async {
      detail()['rolPlanillas'] = 'gerencia';
      await expectLater(
        service.aprobarAuditoria(
          planillaId: 'doc',
          empresaId: 'A',
          loteId: '',
          actorId: 'persona',
          rolPlanillas: 'gerencia',
        ),
        throwsA(
          isA<PpException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('no tiene permiso'),
          ),
        ),
      );
      db.documents['TBL_USUARIOS/persona']!['role'] = 'desarrollador';
      await expectLater(
        service.eliminarLogo(
          empresaId: 'A',
          actorId: 'persona',
          rolPlanillas: 'desarrollador',
          logoPath: 'planillas_pago/A/config/logo.png',
        ),
        throwsA(
          isA<PpException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('no tiene permiso'),
          ),
        ),
      );
      expect(db.writes, 0);
    },
  );
  test(
    'formulario de logos abierto también comprueba el rol vigente',
    () async {
      detail()['rolPlanillas'] = '';
      await expectLater(
        service.setLogoActivo(
          'A',
          'planillas_pago/A/config/logo.png',
          actorId: 'persona',
          rolPlanillas: 'tesoreria',
        ),
        denied(),
      );
      expect(db.writes, 0);
    },
  );
}
