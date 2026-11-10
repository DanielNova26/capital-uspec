import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_models.dart';
import 'package:todo/gestion_documental/planillas/pp_service.dart';
import 'package:todo/services/task_service.dart';

import '../../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {
  final archivos = <String, Uint8List>{};
  String? nombreConFalla;

  @override
  Reference ref([String? path]) => _Reference(this, path!);
}

class _Reference extends Fake implements Reference {
  _Reference(this.storage, this.path);

  @override
  final _Storage storage;
  final String path;

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    if (storage.nombreConFalla != null &&
        path.endsWith(storage.nombreConFalla!)) {
      throw StateError('No se pudo subir el PDF');
    }
    storage.archivos[path] = data;
    return _Upload();
  }

  @override
  Future<String> getDownloadURL() async => 'https://example.test/$path';

  @override
  Future<void> delete() async {
    storage.archivos.remove(path);
  }
}

class _Snapshot extends Fake implements TaskSnapshot {}

class _Upload extends Fake implements UploadTask {
  @override
  Future<T> then<T>(
    FutureOr<T> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => Future<TaskSnapshot>.value(_Snapshot()).then(onValue, onError: onError);
}

class _Functions extends Fake implements FirebaseFunctions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFirestore db;
  late PpService service;
  late _Storage storage;
  setUp(() {
    db = MemoryFirestore();
    storage = _Storage();
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
  Future<String> generar({String segundoNombre = 'Proveedores'}) =>
      service.crearPlanillasConsolidadasDesdeExcel(
        empresaId: 'A',
        actorId: 'persona',
        rolPlanillas: 'tesoreria',
        sinLogo: true,
        planillas: [
          (
            consolidado: '101',
            filas: const [
              PpExcelFila(
                rowIndex: 0,
                excelRowNumber: 2,
                nombrePlanilla: '101',
                valor: 1250,
              ),
              PpExcelFila(
                rowIndex: 1,
                excelRowNumber: 3,
                nombrePlanilla: '101',
                valor: 3750,
              ),
            ],
            nombrePdf: 'Nómina.pdf',
          ),
          (
            consolidado: '102',
            filas: const [
              PpExcelFila(
                rowIndex: 2,
                excelRowNumber: 4,
                nombrePlanilla: '102',
                valor: 980,
              ),
            ],
            nombrePdf: segundoNombre,
          ),
        ],
      );

  test(
    'un lote publica dos PDF y Auditoría firma directo a Gerencia',
    () async {
      final loteId = await generar();
      final lote = db.documents['TBL_PP_LOTES/$loteId']!;
      expect(lote['totalPlanillas'], 2);
      expect(lote['estado'], 'en_proceso');
      final planillas = db.documents.entries
          .where((entry) => entry.key.startsWith('TBL_PP_PLANILLAS/'))
          .toList();
      expect(planillas.map((entry) => entry.value['nombreArchivoOriginal']), [
        'Nómina.pdf',
        'Proveedores.pdf',
      ]);
      expect(planillas.map((entry) => entry.value['valorDetectado']), [
        5000,
        980,
      ]);
      expect(
        planillas.map((entry) => entry.value['estado']),
        everyElement('en_revision_auditoria'),
      );
      expect(storage.archivos.length, 2);
      final primera = planillas.first;
      final planillaId = primera.key.split('/').last;
      final pathOriginal = primera.value['pathPdf'];

      detail()['rolPlanillas'] = 'auditoria';
      await service.aprobarAuditoria(
        planillaId: planillaId,
        empresaId: 'A',
        loteId: loteId,
        actorId: 'persona',
        rolPlanillas: 'auditoria',
      );
      final firmada = db.documents[primera.key]!;
      expect(firmada['estado'], 'pendiente_firma_gerencia');
      expect(firmada['revisadoPor'], 'persona');
      expect(firmada['pathPdf'], isNot(pathOriginal));
      expect(firmada['nombrePdfPersonalizado'], 'Nómina.pdf');
      expect(
        db.documents.values
            .where((doc) => doc['planillaId'] == planillaId)
            .map((doc) => doc['accion']),
        ['carga_enviada_auditoria', 'aprobado_auditoria'],
      );
    },
  );

  test('una falla de PDF evita publicar el lote a medias', () async {
    storage.nombreConFalla = 'Proveedores.pdf';
    await expectLater(generar(), throwsStateError);
    expect(db.writes, 0);
    expect(storage.archivos, isEmpty);
  });

  test('los PDF del lote requieren nombres diferentes', () async {
    await expectLater(
      generar(segundoNombre: 'nómina.PDF'),
      throwsA(isA<PpException>()),
    );
    expect(storage.archivos, isEmpty);
    expect(db.writes, 0);
  });

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
