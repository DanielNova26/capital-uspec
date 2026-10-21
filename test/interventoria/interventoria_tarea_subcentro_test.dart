import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  InterventoriaHallazgo hallazgo(String sub) => InterventoriaHallazgo(
    id: 'h',
    empresaId: 'empresa',
    centroCostoId: 'c',
    centroCostoNombre: 'Picota',
    subcentroId: sub.isEmpty ? '' : 'sur',
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
}
