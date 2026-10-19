import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/notification_monitor_service.dart';
import 'package:todo/interventoria/interventoria_service.dart';

InterventoriaUsuario _persona(
  String id, {
  Set<String> cubre = const {},
  String centroId = '',
}) => InterventoriaUsuario(
  id: id,
  nombre: 'Persona $id',
  cargo: 'Administrador',
  centroId: centroId,
  areaId: '',
  centrosAsignadosIds: cubre,
);

AvisoMonitor _aviso({
  required String userId,
  String sedeId = 'guateque',
  String tipo = 'task_assigned',
  String modulo = 'interventoria',
  bool silenciosa = false,
  bool leida = false,
  String entrega = 'delivered',
}) => AvisoMonitor.fromMap({
  'id': '$userId-$sedeId-$tipo-$silenciosa',
  'userId': userId,
  'titulo': 'Hallazgo',
  'tipo': tipo,
  'modulo': modulo,
  'sedeId': sedeId,
  'sedeNombre': sedeId,
  'silenciosa': silenciosa,
  'leida': leida,
  'entrega': entrega,
  'creadaMs': 1000,
});

void main() {
  test('marca el aviso que llegó a quien no cubre la sede', () {
    final moniquira = _persona('1', cubre: {'moniquira'});
    expect(llegoFueraDeSede(_aviso(userId: '1'), moniquira), isTrue);
  });

  test('no acusa a quien sí cubre la sede ni a quien no se conoce', () {
    final guateque = _persona('2', cubre: {'guateque'});
    expect(llegoFueraDeSede(_aviso(userId: '2'), guateque), isFalse);
    expect(llegoFueraDeSede(_aviso(userId: '9'), null), isFalse);
  });

  test('el aviso silencioso del aprobador y otros tipos no cuentan', () {
    final otra = _persona('1', cubre: {'moniquira'});
    expect(
      llegoFueraDeSede(_aviso(userId: '1', silenciosa: true), otra),
      isFalse,
    );
    expect(
      llegoFueraDeSede(_aviso(userId: '1', tipo: 'interventoria_seguimiento'), otra),
      isFalse,
    );
    expect(
      llegoFueraDeSede(_aviso(userId: '1', modulo: 'compras'), otra),
      isFalse,
    );
  });

  test('sin cobertura propia vale el centro de costos administrativo', () {
    final admin = _persona('3', centroId: 'guateque');
    expect(llegoFueraDeSede(_aviso(userId: '3'), admin), isFalse);
  });

  test('el análisis agrupa por persona y por establecimiento', () {
    final usuarios = {
      '1': _persona('1', cubre: {'moniquira'}),
      '2': _persona('2', cubre: {'guateque'}),
    };
    final a = analizarMonitor([
      _aviso(userId: '1', sedeId: 'guateque'),
      _aviso(userId: '1', sedeId: 'ponal', leida: true),
      _aviso(userId: '2', sedeId: 'guateque', entrega: 'failed'),
      _aviso(userId: '2', sedeId: 'guateque', entrega: 'in_app_only'),
    ], usuarios);

    expect(a.total, 4);
    expect(a.sinLeer, 3);
    expect(a.entregados, 2);
    expect(a.soloApp, 1);
    expect(a.conProblema, 1);
    expect(a.fueraDeSede, 2);
    // Primero quien más avisos recibe de sedes ajenas.
    expect(a.personas.first.userId, '1');
    expect(a.personas.first.fueraDeSede, 2);
    final guateque = a.sedes.firstWhere((s) => s.sedeId == 'guateque');
    expect(guateque.personas.keys.toSet(), {'1', '2'});
    expect(guateque.personasFuera, {'1'});
  });

  test('un aviso sin sede queda en "Sin establecimiento"', () {
    final a = analizarMonitor([_aviso(userId: '1', sedeId: '')], const {});
    expect(a.sedes.single.sedeId, kSinSedeMonitor);
    expect(a.sedes.single.nombre, 'Sin establecimiento');
  });
}
