import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_permisos.dart';
import '../../support/memory_firestore.dart';
import '../../support/correspondence_functions.dart';

Map<String, dynamic> person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'appsPorEmpresa': true,
  'role': 'administrador',
  'rolCorreo': 'administrador',
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

class _DelayedService extends GdPermisosService {
  _DelayedService(MemoryFirestore superDb) : super(db: superDb);
  final requests = <Completer<GdPermisos>>[];
  @override
  Future<GdPermisos> resolver({
    required String empresaId,
    required String userId,
  }) {
    final gate = Completer<GdPermisos>();
    requests.add(gate);
    return gate.future;
  }
}

Future<void> drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemoryFirestore db;
  late CorrespondenceFunctions functions;
  late GdPermisosService service;
  setUp(() {
    db = MemoryFirestore();
    functions = CorrespondenceFunctions();
    db.documents['TBL_USUARIOS/persona'] = person();
    service = GdPermisosService(db: db, functions: functions);
  });
  tearDown(() => db.close());
  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  Future<GdPermisos> resolve([String empresaId = 'A']) =>
      service.resolver(empresaId: empresaId, userId: 'persona');
  void assignment(String level, [String id = 'A_persona']) =>
      db.documents['TBL_CORREO_ROLES/$id'] = {
        'empresaId': 'A',
        'usuarioId': 'persona',
        'rol': level,
      };

  test('jerarquía corresponde a las cuatro capacidades operativas', () {
    final visor = GdPermisos(GdRolCorrespondencia.visor);
    final operator = GdPermisos(GdRolCorrespondencia.operador);
    final classifier = GdPermisos(GdRolCorrespondencia.clasificador);
    final admin = GdPermisos(GdRolCorrespondencia.administrador);
    expect(visor.tieneAcceso, isTrue);
    expect(visor.puedeGestionarAsignado, isFalse);
    expect(operator.puedeGestionarAsignado, isTrue);
    expect(operator.puedeClasificar, isFalse);
    expect(classifier.puedeRadicar, isTrue);
    expect(classifier.puedeAdministrarFiltros, isFalse);
    expect(admin.puedeCerrarCualquiera, isTrue);
    expect(admin.puedeAdministrarTipos, isTrue);
    expect(GdPermisos.sinAcceso.tieneAcceso, isFalse);
    expect(GdPermisos.cargando.resueltos, isFalse);
  });
  test('empresa secundaria no hereda administrador raíz', () {
    expect(
      resolveCorrespondenceRole(user: user(), empresaId: 'B'),
      GdRolCorrespondencia.operador,
    );
    detail('B')['rolCorreo'] = '';
    expect(
      resolveCorrespondenceRole(user: user(), empresaId: 'B'),
      GdRolCorrespondencia.visor,
    );
  });
  test(
    'decisión explícita vacía o desconocida no recupera administrador general',
    () {
      for (final level in ['', 'inventado']) {
        detail()['rolCorreo'] = level;
        expect(
          resolveCorrespondenceRole(user: user(), empresaId: 'A'),
          GdRolCorrespondencia.visor,
        );
      }
    },
  );
  test(
    'sin decisiones conserva Operador por defecto y administrador general de empresa',
    () {
      user()['role'] = 'usuario';
      user().remove('rolCorreo');
      detail().remove('rolCorreo');
      expect(
        resolveCorrespondenceRole(user: user(), empresaId: 'A'),
        GdRolCorrespondencia.operador,
      );
      detail()['roleKey'] = 'administrador';
      expect(
        resolveCorrespondenceRole(user: user(), empresaId: 'A'),
        GdRolCorrespondencia.administrador,
      );
    },
  );
  test('tabla canónica manda sobre ficha y duplicado histórico', () async {
    assignment('visor');
    assignment('administrador', 'old');
    expect((await resolve()).rol, GdRolCorrespondencia.visor);
    expect(await service.rolesAsignados('A'), {
      'persona': GdRolCorrespondencia.visor,
    });
  });
  test(
    'respaldo reconoce asignación histórica por empresa y usuario',
    () async {
      assignment('clasificador', 'old');
      expect((await resolve()).rol, GdRolCorrespondencia.clasificador);
    },
  );
  test('ignora documento canónico con usuario o empresa incorrectos', () async {
    assignment('administrador');
    db.documents['TBL_CORREO_ROLES/A_persona']!['usuarioId'] = 'otro';
    expect((await resolve()).rol, GdRolCorrespondencia.operador);
  });
  test(
    'retirar app, membresía o habilitación impide acceso aunque la tabla diga administrador',
    () async {
      assignment('administrador');
      detail()['apps'] = <String>[];
      expect((await resolve()).tieneAcceso, isFalse);
      detail()['apps'] = ['correodashboard'];
      detail()['activo'] = false;
      expect((await resolve()).tieneAcceso, isFalse);
      detail()['activo'] = true;
      user()['empresas'] = ['B'];
      user()['empresaId'] = 'B';
      user()['empresasDetalle'].remove('A');
      expect((await resolve()).tieneAcceso, isFalse);
      expect(functions.calls, 0);
    },
  );
  test(
    'desarrollador conserva excepción; inactividad de empresa la revoca',
    () async {
      user()['role'] = 'desarrollador';
      detail()['apps'] = <String>[];
      expect((await resolve()).rol, GdRolCorrespondencia.administrador);
      detail()['activo'] = false;
      expect((await resolve()).tieneAcceso, isFalse);
    },
  );
  test(
    'respuesta de servidor prevalece y no pertenecer bloquea consulta',
    () async {
      assignment('administrador');
      functions.response = {'rol': 'visor'};
      expect((await resolve()).rol, GdRolCorrespondencia.visor);
      functions.response = {'rol': null, 'motivo': 'no_pertenece'};
      expect((await resolve()).tieneAcceso, isFalse);
    },
  );
  test(
    'denegación del servidor no activa respaldo con permisos más altos',
    () async {
      assignment('administrador');
      for (final code in ['permission-denied', 'unauthenticated']) {
        functions.deniedCode = code;
        expect((await resolve()).tieneAcceso, isFalse);
      }
    },
  );
  test(
    'observación actualiza nivel y retirada de acceso en pantalla abierta',
    () async {
      assignment('administrador');
      final received = <GdPermisos>[];
      final subscription = service
          .observar(empresaId: 'A', userId: 'persona')
          .listen(received.add);
      await drain();
      expect(received.last.rol, GdRolCorrespondencia.administrador);
      await db.collection('TBL_CORREO_ROLES').doc('A_persona').update({
        'rol': 'visor',
      });
      await drain();
      expect(received.last.rol, GdRolCorrespondencia.visor);
      await db.collection('TBL_USUARIOS').doc('persona').update({
        'empresasDetalle.A.apps': <String>[],
      });
      await drain();
      expect(received.last.tieneAcceso, isFalse);
      await subscription.cancel();
    },
  );
  test(
    'respuestas de permiso viejas no revierten una reducción vigente',
    () async {
      final delayed = _DelayedService(db);
      final received = <GdPermisos>[];
      final subscription = delayed
          .observar(empresaId: 'A', userId: 'persona')
          .listen(received.add);
      await drain();
      final old = [...delayed.requests];
      db.notifyDocument('TBL_USUARIOS/persona');
      await drain();
      delayed.requests.last.complete(
        const GdPermisos(GdRolCorrespondencia.visor),
      );
      await drain();
      for (final gate in old) {
        gate.complete(const GdPermisos(GdRolCorrespondencia.administrador));
      }
      await drain();
      expect(received.last.rol, GdRolCorrespondencia.visor);
      await subscription.cancel();
    },
  );
}
