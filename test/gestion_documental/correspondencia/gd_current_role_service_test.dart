import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_service.dart';
import 'package:todo/gestion_documental/correspondencia/gd_colaboracion_models.dart';
import 'package:todo/gestion_documental/correspondencia/gd_colaboracion_service.dart';
import 'package:todo/services/task_service.dart';
import '../../support/memory_firestore.dart';
import '../../support/correspondence_functions.dart';

class _Storage extends Fake implements FirebaseStorage {}

void main() {
  late MemoryFirestore db;
  late GdCorrespondenciaService service;
  late GdColaboracionService collaboration;
  late GdExpediente expediente;
  setUp(() async {
    db = MemoryFirestore();
    final storage = _Storage();
    service = GdCorrespondenciaService(
      db: db,
      storage: storage,
      functions: CorrespondenceFunctions(),
    );
    collaboration = GdColaboracionService(
      db: db,
      storage: storage,
      taskService: TaskService(db: db, storage: storage),
    );
    db.documents['TBL_USUARIOS/persona'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'role': 'usuario',
      'appsPorEmpresa': true,
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{
          'activo': true,
          'apps': ['correodashboard'],
          'rolCorreo': 'operador',
        },
        'B': <String, dynamic>{
          'activo': true,
          'apps': ['correodashboard'],
        },
      },
    };
    db.documents['TBL_GD_EXPEDIENTES/doc'] = {
      'empresaId': 'A',
      'estado': 'asignado',
      'asunto': 'Original',
    };
    expediente = GdExpediente.fromFirestore(
      await db.collection('TBL_GD_EXPEDIENTES').doc('doc').get(),
    );
  });
  tearDown(() => db.close());
  Map<String, dynamic> detail() =>
      db.documents['TBL_USUARIOS/persona']!['empresasDetalle']['A'];
  Future<void> alias() => service.guardarAlias(
    expediente: expediente,
    userId: 'persona',
    alias: 'Control de septiembre',
  );
  Future<void> response() => service.guardarRespuesta(
    expediente: expediente,
    userId: 'persona',
    destinatario: 'correo@example.com',
    asunto: 'Respuesta',
    cuerpo: 'Contenido',
    cc: [],
    requiereAprobacion: false,
  );
  Future<void> type([String empresaId = 'A']) => service.guardarTipoDocumental(
    empresaId: empresaId,
    userId: 'persona',
    codigo: 'SOL',
    nombre: 'Solicitud',
  );
  void assignment(String level) => db.documents['TBL_CORREO_ROLES/A_persona'] =
      {'empresaId': 'A', 'usuarioId': 'persona', 'rol': level};
  const attachment = GdCorrespondenciaAdjunto(
    nombre: 'archivo.pdf',
    mimeType: 'application/pdf',
    storagePath: 'foreign/path',
    downloadUrl: 'https://example.com/file.pdf',
    size: 1,
  );

  test(
    'formulario abierto no guarda respuesta, alias ni adjuntos después de pasar a Visor',
    () async {
      assignment('visor');
      await expectLater(response(), throwsStateError);
      await expectLater(alias(), throwsStateError);
      await expectLater(
        service.subirAdjuntoRespuesta(
          expediente: expediente,
          userId: 'persona',
          file: PlatformFile(name: 'archivo.pdf', size: 1),
        ),
        throwsStateError,
      );
      await expectLater(
        service.quitarAdjuntoRespuesta(
          expediente: expediente,
          userId: 'persona',
          attachment: attachment,
        ),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );
  test(
    'retirar app o habilitación impide escritura con nivel antiguo',
    () async {
      assignment('administrador');
      detail()['apps'] = <String>[];
      await expectLater(alias(), throwsStateError);
      detail()['apps'] = ['correodashboard'];
      detail()['activo'] = false;
      await expectLater(response(), throwsStateError);
      expect(db.writes, 0);
    },
  );
  test(
    'lectura vigente del expediente impide guardar objeto de otra empresa',
    () async {
      db.documents['TBL_GD_EXPEDIENTES/doc']!['empresaId'] = 'B';
      await expectLater(alias(), throwsStateError);
      await expectLater(response(), throwsStateError);
      expect(db.writes, 0);
    },
  );
  test(
    'Operador guarda alias y borrador con trazabilidad conservando etapa',
    () async {
      await alias();
      await response();
      final current = db.documents['TBL_GD_EXPEDIENTES/doc']!;
      expect(current['alias'], 'Control de septiembre');
      expect(current['estado'], 'asignado');
      expect(current['respuestaCuerpo'], 'Contenido');
      expect(current['respuestaActualizadaPor'], 'persona');
      final events = db.documents.entries
          .where((e) => e.key.startsWith('TBL_GD_EXPEDIENTES_EVENTOS/'))
          .toList();
      expect(events.length, 2);
      expect(
        events.every(
          (e) =>
              e.value['empresaId'] == 'A' && e.value['usuarioId'] == 'persona',
        ),
        isTrue,
      );
    },
  );
  test(
    'Clasificador no administra maestro ni siembra tipos; Administrador sí',
    () async {
      assignment('clasificador');
      await expectLater(type(), throwsStateError);
      await expectLater(
        service.sembrarTiposBase(empresaId: 'A', userId: 'persona'),
        throwsStateError,
      );
      expect(db.writes, 0);
      assignment('administrador');
      await type();
      expect(
        db.documents['TBL_GD_TIPOS_DOCUMENTALES/A_SOL']!['nombre'],
        'Solicitud',
      );
      await expectLater(type('B'), throwsStateError);
      expect(db.documents['TBL_GD_TIPOS_DOCUMENTALES/B_SOL'], isNull);
    },
  );
  test(
    'desactivación del maestro relee el nivel aunque el editor siga abierto',
    () async {
      assignment('administrador');
      await type();
      final writes = db.writes;
      assignment('visor');
      await expectLater(
        service.cambiarEstadoTipoDocumental(
          id: 'A_SOL',
          userId: 'persona',
          activo: false,
        ),
        throwsStateError,
      );
      expect(db.writes, writes);
      expect(
        db.documents['TBL_GD_TIPOS_DOCUMENTALES/A_SOL']!['activo'],
        isTrue,
      );
    },
  );
  test(
    'colaboración no escribe cuando Visor conserva acceso de consulta',
    () async {
      assignment('visor');
      await expectLater(
        collaboration.agregarEntrada(
          expediente: expediente,
          userId: 'persona',
          mensaje: 'Comentario',
          tipo: 'comentario',
        ),
        throwsStateError,
      );
      db.documents['TBL_GD_COLABORACION/entrada'] = {
        'empresaId': 'A',
        'expedienteId': 'doc',
        'usuarioId': 'persona',
      };
      final entrada = GdColaboracionEntrada.fromFirestore(
        await db.collection('TBL_GD_COLABORACION').doc('entrada').get(),
      );
      await expectLater(
        collaboration.resolverEntrada(entrada: entrada, userId: 'persona'),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );
  test(
    'solicitud de colaboración no se resuelve con autor o empresa desactualizados',
    () async {
      db.documents['TBL_GD_COLABORACION/entrada'] = {
        'empresaId': 'A',
        'expedienteId': 'doc',
        'usuarioId': 'persona',
      };
      final entrada = GdColaboracionEntrada.fromFirestore(
        await db.collection('TBL_GD_COLABORACION').doc('entrada').get(),
      );
      db.documents['TBL_GD_COLABORACION/entrada']!['usuarioId'] = 'otro';
      await expectLater(
        collaboration.resolverEntrada(entrada: entrada, userId: 'persona'),
        throwsStateError,
      );
      db.documents['TBL_GD_COLABORACION/entrada']!['usuarioId'] = 'persona';
      db.documents['TBL_GD_COLABORACION/entrada']!['empresaId'] = 'B';
      await expectLater(
        collaboration.resolverEntrada(entrada: entrada, userId: 'persona'),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );
  test('Operador resuelve únicamente su solicitud vigente', () async {
    db.documents['TBL_GD_COLABORACION/entrada'] = {
      'empresaId': 'A',
      'expedienteId': 'doc',
      'usuarioId': 'persona',
      'estado': 'pendiente',
    };
    final entrada = GdColaboracionEntrada.fromFirestore(
      await db.collection('TBL_GD_COLABORACION').doc('entrada').get(),
    );
    await collaboration.resolverEntrada(entrada: entrada, userId: 'persona');
    expect(db.documents['TBL_GD_COLABORACION/entrada']!['estado'], 'resuelto');
    expect(
      db.documents['TBL_GD_COLABORACION/entrada']!['resueltoPor'],
      'persona',
    );
  });
}
