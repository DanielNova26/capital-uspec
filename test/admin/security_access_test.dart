import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/security_admin_panel.dart';
import 'package:todo/admin/security_admin_service.dart';
import 'package:todo/services/device_descriptor.dart';
import 'package:todo/services/session_audit_service.dart';
import 'package:todo/talento_humano/zeus_export_service.dart';
import '../support/memory_firestore.dart';

SecurityUserStatus persona({
  int? lastLogin,
  Map<String, dynamic>? device,
  bool never = false,
}) => SecurityUserStatus.fromMap({
  'userDocId': 'u',
  'nombre': 'Ana',
  'active': true,
  'migrated': true,
  'lastLoginAt': ?lastLogin,
  'lastLoginDevice': ?device,
  'neverLoggedIn': never,
});

void main() {
  test('persona: último ingreso con su equipo, nueva y clave inicial', () {
    final u = SecurityUserStatus.fromMap({
      'userDocId': '1',
      'nombre': 'Ana',
      'active': true,
      'migrated': false,
      'lastLoginAt': DateTime(2026, 9, 28, 10).millisecondsSinceEpoch,
      'lastLoginDevice': {
        'tipo': 'celular',
        'marca': 'Samsung',
        'modelo': 'SM-A515F',
        'sistema': 'Android 14',
        'app': true,
      },
      'neverLoggedIn': false,
      'initialPassword': true,
      'createdAt': DateTime(2026, 9, 20).millisecondsSinceEpoch,
    });
    expect(u.hasLoggedIn, isTrue);
    expect(u.lastLoginDevice.esMovil, isTrue);
    expect(u.initialPassword, isTrue);
    expect(u.esNueva(DateTime(2026, 9, 29)), isTrue);
    expect(u.esNueva(DateTime(2026, 11, 29)), isFalse);
    // Sin campos nuevos (servidor anterior): valores seguros.
    final viejo = SecurityUserStatus.fromMap({'userDocId': '2'});
    expect(viejo.hasLoggedIn, isFalse);
    expect(viejo.neverLoggedIn, isFalse);
    expect(viejo.lastLoginDevice.tipo, TipoDispositivo.desconocido);
  });

  test('resumen: computador, celular por marca y sin detalle', () {
    final r = resumenDispositivos([
      persona(lastLogin: 1, device: {'tipo': 'computador'}),
      persona(lastLogin: 1, device: {'tipo': 'celular', 'marca': 'Samsung'}),
      persona(lastLogin: 1, device: {'tipo': 'celular', 'marca': 'Samsung'}),
      persona(lastLogin: 1, device: {'tipo': 'tablet', 'marca': 'Apple'}),
      persona(lastLogin: 1, device: {'tipo': 'celular'}),
      persona(lastLogin: 1),
      // Nunca entró: no cuenta en ningún equipo.
      persona(never: true, device: {'tipo': 'computador'}),
    ]);
    expect(r.computador, 1);
    expect(r.celular, 4);
    expect(r.sinDetalle, 1);
    expect(r.marcas.map((e) => '${e.key} ${e.value}'), [
      'Samsung 2',
      'Apple 1',
      'Otro 1',
    ]);
  });

  test('actividad: textos de la clave inicial y de personas nuevas', () {
    SecurityAuditEntry e(String action, {int? count, bool clave = false}) =>
        SecurityAuditEntry(
          id: 'x',
          action: action,
          actorUserDocId: 'a',
          targetUserDocId: 'b',
          createdAt: null,
          count: count,
          initialPassword: clave,
        );
    expect(
      auditLabel(e('initial_password_bulk', count: 14)),
      'Asignó la clave inicial a 14 persona(s) que nunca habían entrado',
    );
    expect(
      auditLabel(e('user_created', clave: true)),
      'Persona nueva, con clave inicial 123456',
    );
    expect(auditLabel(e('user_created')), 'Persona nueva');
    expect(auditLabel(e('otra')), 'otra');
    expect(
      SecurityAuditEntry.fromMap({
        'action': 'initial_password_bulk',
        'count': 3,
      }).count,
      3,
    );
  });

  test('ingresos: origen legible y fechas relativas', () {
    final s = SecuritySession.fromMap({
      'userDocId': '1',
      'nombre': 'Ana',
      'source': 'biometria',
      'loginAt': DateTime(2026, 9, 29, 8, 5).millisecondsSinceEpoch,
      'device': {'tipo': 'computador', 'sistema': 'Windows'},
    });
    expect(s.sourceLabel, 'Huella o rostro');
    expect(s.device.tipo, TipoDispositivo.computador);
    final ahora = DateTime(2026, 9, 29, 12);
    expect(haceCuanto(DateTime(2026, 9, 29, 8, 5), ahora), 'Hoy 08:05');
    expect(haceCuanto(DateTime(2026, 9, 28, 22, 1), ahora), 'Ayer 22:01');
    expect(haceCuanto(DateTime(2026, 9, 25), ahora), 'Hace 4 días');
    expect(haceCuanto(DateTime(2026, 8, 1), ahora), '01/08/26');
  });

  test('al entrar se guarda el equipo en el ingreso y en la ficha', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    db.documents['TBL_USUARIOS/100'] = {
      'cedula': '100',
      'nombres': 'Ana',
      'empresaId': 'A',
    };
    await SessionAuditService(
      db: db,
      lectorDispositivo: () async => dispositivoAndroid(
        fabricante: 'samsung',
        modelo: 'SM-A515F',
        version: '14',
      ),
    ).recordLogin(
      userId: '100',
      empresaId: 'A',
      userData: db.documents['TBL_USUARIOS/100']!,
      source: 'password',
    );
    final sesion = db.documents.entries
        .firstWhere((e) => e.key.startsWith('TBL_LOGIN_SESIONES/'))
        .value;
    expect(sesion['userId'], '100');
    expect(sesion['dispositivo']['marca'], 'Samsung');
    expect(
      sesion['dispositivo']['descripcion'],
      'Celular Samsung SM-A515F · Android 14 · App',
    );
    final user = db.documents['TBL_USUARIOS/100']!;
    expect(user['lastLoginDevice']['tipo'], 'celular');
    expect(user['lastLoginAt'], isA<Timestamp>());
  });

  test('si el equipo no se puede leer, el ingreso se registra igual', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    db.documents['TBL_USUARIOS/100'] = {'cedula': '100'};
    await SessionAuditService(
      db: db,
      lectorDispositivo: () async => throw StateError('sin plugin'),
    ).recordLogin(
      userId: '100',
      empresaId: 'A',
      userData: const {'cedula': '100'},
      source: 'sesion_guardada',
    );
    final sesion = db.documents.entries
        .firstWhere((e) => e.key.startsWith('TBL_LOGIN_SESIONES/'))
        .value;
    expect(sesion['dispositivo']['tipo'], 'desconocido');
  });

  group('alta de personas', () {
    Future<bool> alta(MemoryFirestore db, {bool soloNuevo = true}) =>
        ZeusExportService(db: db).createBasicUser(
          empresaId: 'A',
          cedula: '200',
          primerNombre: 'Luis',
          segundoNombre: '',
          primerApellido: 'Gómez',
          segundoApellido: '',
          correo: '',
          area: '',
          cargo: '',
          centroCostos: '',
          soloNuevo: soloNuevo,
          creadoPor: '101',
        );

    test('nueva: clave inicial y quién la creó', () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      expect(await alta(db), isTrue);
      final user = db.documents['TBL_USUARIOS/200']!;
      expect(user['password'], '123456');
      expect(user['needsPasswordChange'], isTrue);
      expect(user['creadoPor'], '101');
    });

    test('quien ya entró conserva su clave al activarla de nuevo', () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      db.documents['TBL_USUARIOS/200'] = {
        'cedula': '200',
        'authVersion': 2,
        'needsPasswordChange': false,
      };
      expect(await alta(db, soloNuevo: false), isFalse);
      final user = db.documents['TBL_USUARIOS/200']!;
      expect(user.containsKey('password'), isFalse);
      expect(user['needsPasswordChange'], isFalse);
      expect(user.containsKey('creadoPor'), isFalse);
    });
  });
}
