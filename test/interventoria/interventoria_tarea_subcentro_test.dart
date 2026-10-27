import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  InterventoriaHallazgo hallazgo(String sub, {String? subId}) =>
      InterventoriaHallazgo(
        id: 'h',
        empresaId: 'empresa',
        visitaId: 'acta',
        centroCostoId: 'c',
        centroCostoNombre: 'Picota',
        subcentroId: subId ?? (sub.isEmpty ? '' : 'sur'),
        subcentroNombre: sub,
        numeroHallazgo: '8.18',
        descripcion: 'Control de plagas',
        fechaHallazgo: Timestamp.fromDate(DateTime(2026, 10, 21)),
        createdAt: Timestamp.fromDate(DateTime(2026, 10, 21)),
      );
  test('tarea enviada incluye subcentro en título, descripción y datos', () {
    final contexto = contextoTareaInterventoria(hallazgo('Sur'));
    expect(contexto.titulo, 'Picota — Sur Obs.8.18: Control de plagas');
    expect(contexto.ubicacion, 'Centro de costo: Picota\nSubcentro: Sur\n');
    expect(contexto.campos['subcentroId'], 'sur');
    expect(contexto.campos['subcentroNombre'], 'Sur');
  });
  test('sin subcentro conserva ubicación sin inventar uno', () {
    final contexto = contextoTareaInterventoria(hallazgo(''));
    expect(contexto.titulo, 'Picota Obs.8.18: Control de plagas');
    expect(contexto.ubicacion, 'Centro de costo: Picota\n');
    expect(contexto.campos['subcentroId'], isEmpty);
  });
  test('no repite el centro cuando forma parte del nombre del subcentro', () {
    expect(
      contextoTareaInterventoria(hallazgo('Picota Sur')).titulo,
      'Picota — Sur Obs.8.18: Control de plagas',
    );
  });
  InterventoriaVisita acta({
    String id = 'acta',
    String empresa = 'empresa',
    String centro = 'c',
    String subId = 'sur',
    String sub = 'Sur',
  }) => InterventoriaVisita.fromMap(id, {
    'empresaId': empresa,
    'centroCostoId': centro,
    'centroCostoNombre': 'Picota',
    'subcentroId': subId,
    'subcentroNombre': sub,
  });

  test('recupera del acta el subcentro ausente en el hallazgo histórico', () {
    final h = hallazgo('');
    final contexto = contextoTareaInterventoria(h, visita: acta());
    expect(contexto.titulo, 'Picota — Sur Obs.8.18: Control de plagas');
    expect(contexto.ubicacion, 'Centro de costo: Picota\nSubcentro: Sur\n');
    expect(contexto.campos['subcentroId'], 'sur');
    expect(contexto.campos['subcentroNombre'], 'Sur');
    expect(h.subcentroNombre, isEmpty); // No escribe el histórico.
  });

  test('completa nombre o id sin mezclar subcentros', () {
    expect(
      contextoTareaInterventoria(
        hallazgo('', subId: 'sur'),
        visita: acta(),
      ).campos['subcentroNombre'],
      'Sur',
    );
    expect(
      contextoTareaInterventoria(
        hallazgo('Picota Sur', subId: ''),
        visita: acta(),
      ).campos['subcentroId'],
      'sur',
    );
    expect(
      () => contextoTareaInterventoria(
        hallazgo('', subId: 'norte'),
        visita: acta(),
      ),
      throwsStateError,
    );
    expect(
      () => contextoTareaInterventoria(
        hallazgo('Norte', subId: ''),
        visita: acta(),
      ),
      throwsStateError,
    );
  });

  test('rechaza acta de otra empresa, centro o vínculo', () {
    for (final v in [
      acta(empresa: 'otra'),
      acta(centro: 'otro'),
      acta(id: 'otra'),
    ]) {
      expect(
        () => contextoTareaInterventoria(hallazgo(''), visita: v),
        throwsStateError,
      );
    }
  });

  test('acta del centro completo no inventa subcentro', () {
    final contexto = contextoTareaInterventoria(
      hallazgo(''),
      visita: acta(subId: '', sub: ''),
    );
    expect(contexto.ubicacion, 'Centro de costo: Picota\n');
    expect(contexto.campos['subcentroId'], isEmpty);
  });

  test('no envía una tarea cuyo subcentro sigue sin nombre', () {
    expect(
      () => contextoTareaInterventoria(hallazgo('', subId: 'sur')),
      throwsStateError,
    );
    expect(
      () => contextoTareaInterventoria(hallazgo(''), visita: acta(sub: '')),
      throwsStateError,
    );
  });
  test(
    'no une id y nombre si el acta no permite verificar su correspondencia',
    () {
      expect(
        () => contextoTareaInterventoria(
          hallazgo('', subId: 'norte'),
          visita: acta(subId: ''),
        ),
        throwsStateError,
      );
      expect(
        () => contextoTareaInterventoria(
          hallazgo('Norte', subId: ''),
          visita: acta(sub: ''),
        ),
        throwsStateError,
      );
    },
  );
}
