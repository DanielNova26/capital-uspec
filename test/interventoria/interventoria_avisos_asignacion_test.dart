import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_avisos_asignacion.dart';

/// 25 sep 2026: con la asignación automática "empezaron a llegar las
/// notificaciones a todo el mundo". En lote sale un aviso por persona: con
/// sonido al responsable, en silencio al aprobador.
void main() {
  InterventoriaTareaCreada tarea(
    String id, {
    String responsable = 'admin-sede',
    String aprobador = 'director',
    String sede = 'Ramiriquí',
  }) => InterventoriaTareaCreada(
    taskId: id,
    hallazgoId: 'h$id',
    empresaId: 'emp',
    centroCostoNombre: sede,
    responsableId: responsable,
    responsableNombre: 'Responsable',
    aprobadorId: aprobador,
    aprobadorNombre: 'Aprobador',
  );

  test('veinte hallazgos: un aviso al responsable y uno al aprobador', () {
    final avisos = avisosDeAsignacion([
      for (var i = 0; i < 20; i++) tarea('t$i'),
    ]);
    expect(avisos, hasLength(2));
    final responsable = avisos.singleWhere((a) => !a.paraAprobar);
    final aprobador = avisos.singleWhere((a) => a.paraAprobar);
    expect(responsable.destinatarioId, 'admin-sede');
    expect(responsable.cantidad, 20);
    expect(responsable.titulo, '20 hallazgos de Interventoría asignados');
    expect(responsable.silenciosa, isFalse);
    expect(aprobador.destinatarioId, 'director');
    expect(aprobador.silenciosa, isTrue);
    expect(aprobador.titulo, 'Aprobarás 20 hallazgos de Interventoría');
  });

  test('cada responsable recibe solo lo suyo', () {
    final avisos = avisosDeAsignacion([
      tarea('a', responsable: 'ana', sede: 'Sede A'),
      tarea('b', responsable: 'ana', sede: 'Sede B'),
      tarea('c', responsable: 'luis', sede: 'Sede C'),
    ]);
    final paraAna = avisos.singleWhere(
      (a) => a.destinatarioId == 'ana' && !a.paraAprobar,
    );
    final paraLuis = avisos.singleWhere(
      (a) => a.destinatarioId == 'luis' && !a.paraAprobar,
    );
    expect(paraAna.taskIds, ['a', 'b']);
    expect(paraAna.descripcion, contains('Sede A (1), Sede B (1)'));
    expect(paraLuis.titulo, 'Nuevo hallazgo de Interventoría asignado');
    expect(paraLuis.taskId, 'c');
    final paraDirector = avisos.singleWhere((a) => a.paraAprobar);
    expect(paraDirector.cantidad, 3);
  });

  test(
    'quien subsana y aprueba la misma tarea recibe solo el aviso que suena',
    () {
      final avisos = avisosDeAsignacion([
        tarea('x', responsable: 'ana', aprobador: 'ana'),
      ]);
      expect(avisos, hasLength(1));
      expect(avisos.single.paraAprobar, isFalse);
    },
  );

  test('una tarea repetida no se cuenta dos veces', () {
    final avisos = avisosDeAsignacion([tarea('x'), tarea('x'), tarea('')]);
    expect(avisos.map((a) => a.cantidad), everyElement(1));
  });

  test('la clave del aviso depende de las tareas, no del orden', () {
    final a = avisosDeAsignacion([tarea('1'), tarea('2')]).first;
    final b = avisosDeAsignacion([tarea('2'), tarea('1')]).first;
    final c = avisosDeAsignacion([tarea('1'), tarea('3')]).first;
    expect(a.claveIdempotencia, b.claveIdempotencia);
    expect(a.claveIdempotencia, isNot(c.claveIdempotencia));
    final aprobador = avisosDeAsignacion([
      tarea('1'),
      tarea('2'),
    ]).singleWhere((x) => x.paraAprobar);
    expect(aprobador.claveIdempotencia, isNot(a.claveIdempotencia));
  });

  test('el resumen de sedes ordena por cantidad y recorta', () {
    expect(
      resumenSedesAviso(['B', 'A', 'B', 'C', 'D', 'E', 'F']),
      'B (2), A (1), C (1), D (1) y 2 más',
    );
    expect(resumenSedesAviso(['', ' ']), 'Sin sede (2)');
  });
}
