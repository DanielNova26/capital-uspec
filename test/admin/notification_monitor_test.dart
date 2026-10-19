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
  candidatos();
  explicacion();
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

void candidatos() {
  test('los candidatos cubren la sede, reciben tareas y no son quien la tiene', () {
    final datos = DatosMonitor(
      avisos: const [],
      usuarios: {
        '1': _persona('1', cubre: {'moniquira'}),
        '2': _persona('2', cubre: {'guateque'}),
        '3': _persona('3', cubre: {'guateque'}),
        '4': _persona('4', cubre: {'guateque'}),
      },
      // El 3 está marcado como no operativo: no recibe tareas.
      asignablesIds: {'1', '2', '4'},
      truncado: false,
      dias: 7,
    );
    final aviso = _aviso(userId: '4');
    final ids = candidatosParaSede(aviso, datos).map((p) => p.id).toList();
    expect(ids, ['2']);
  });
}

void explicacion() {
  AvisoMonitor aviso(String user) => AvisoMonitor.fromMap({
    'id': 'x',
    'userId': user,
    'tipo': 'task_assigned',
    'modulo': 'interventoria',
    'sedeId': 'lamesa',
    'sedeNombre': 'La Mesa',
    'cargoResponsable': 'Coordinador de calidad',
    'numeral': '2.14',
    'creadaMs': 1000,
  });
  InterventoriaUsuario calidad(String id, Set<String> cubre) =>
      InterventoriaUsuario(
        id: id,
        nombre: 'Persona $id',
        cargo: 'Coordinador De Calidad',
        centroId: '',
        areaId: '',
        centrosAsignadosIds: cubre,
      );

  test('explica que nadie con el cargo cubre la sede', () {
    final datos = DatosMonitor(
      avisos: const [],
      usuarios: {'1': calidad('1', {'picota'})},
      asignablesIds: {'1'},
      centros: const {'picota': 'Picota'},
      truncado: false,
      dias: 7,
    );
    final texto = explicarAlerta(aviso('1'), datos);
    expect(texto, contains('Nadie con ese cargo cubre La Mesa'));
    expect(texto, contains('cubre Picota'));
  });

  test('explica cuando sí había titular en la sede', () {
    final datos = DatosMonitor(
      avisos: const [],
      usuarios: {
        '1': calidad('1', {'picota'}),
        '2': calidad('2', {'lamesa'}),
      },
      asignablesIds: {'1', '2'},
      truncado: false,
      dias: 7,
    );
    expect(
      explicarAlerta(aviso('1'), datos),
      contains('En La Mesa sí cubre Persona 2'),
    );
  });
}
