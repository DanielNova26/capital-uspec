import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_models.dart';

void main() {
  const tunja = VisitaUbicacion(
    empresaId: 'capital',
    centroId: 'tunja',
    centroNombre: 'Tunja',
    lat: 5.5353,
    lng: -73.3678,
    radioMetros: 150,
  );
  const tunjaAlta = VisitaUbicacion(
    empresaId: 'capital',
    centroId: 'tunja',
    centroNombre: 'Tunja',
    subcentroId: 'alta',
    subcentroNombre: 'Alta',
    lat: 5.5453,
    lng: -73.3678,
    radioMetros: 150,
  );
  const combita = VisitaUbicacion(
    empresaId: 'capital',
    centroId: 'combita',
    centroNombre: 'Cómbita',
    lat: 5.6343,
    lng: -73.3229,
    radioMetros: 150,
  );

  VisitaProfesional visita({
    String id = 'v',
    String centroId = 'tunja',
    String subcentroId = '',
    String estado = kVisitaProgramada,
    DateTime? fecha,
  }) => VisitaProfesional(
    id: id,
    empresaId: 'capital',
    formatoId: 'f',
    formatoNombre: 'SST',
    areaId: 'sst',
    areaNombre: 'SST',
    centroId: centroId,
    centroNombre: centroId,
    subcentroId: subcentroId,
    profesionalId: '111',
    profesionalNombre: 'Miguel',
    asignadoPorId: '222',
    asignadoPorNombre: 'Oscar',
    fechaProgramada: fecha ?? DateTime(2026, 9, 21),
    estado: estado,
    inicio: estado == kVisitaEnCurso ? VisitaMarca(at: Timestamp.now()) : null,
  );

  final ahora = DateTime(2026, 9, 21, 9);

  group('referenciaDeVisita', () {
    test('el subcentro con ubicación propia manda; si no, la del centro', () {
      expect(
        referenciaDeVisita(visita(subcentroId: 'alta'), [tunja, tunjaAlta]),
        same(tunjaAlta),
      );
      expect(
        referenciaDeVisita(visita(subcentroId: 'media'), [tunja, tunjaAlta]),
        same(tunja),
      );
      expect(referenciaDeVisita(visita(centroId: 'x'), [tunja]), isNull);
    });
  });

  group('resolverRegistroVisita', () {
    test('en el sitio con visita del día: lista para iniciar', () {
      final r = resolverRegistroVisita(
        lat: tunja.lat,
        lng: tunja.lng,
        ubicaciones: [tunja, combita],
        visitasDelProfesional: [visita()],
        ahora: ahora,
      );
      expect(r.enUnEstablecimiento, isTrue);
      expect(r.ubicacionActual, same(tunja));
      expect(r.listas.map((e) => e.visita.id), ['v']);
      expect(r.paraDespues, isEmpty);
    });

    test('en el sitio sin visita programada: nada que iniciar', () {
      // Es la regla de Oscar: "si llegó a Chocontá y no estaba programado,
      // no lo va a dejar entrar".
      final r = resolverRegistroVisita(
        lat: combita.lat,
        lng: combita.lng,
        ubicaciones: [tunja, combita],
        visitasDelProfesional: [visita()],
        ahora: ahora,
      );
      expect(r.ubicacionActual, same(combita));
      expect(r.listas, isEmpty);
      expect(r.paraDespues, isEmpty);
    });

    test('la visita de mañana en el sitio va aparte', () {
      final r = resolverRegistroVisita(
        lat: tunja.lat,
        lng: tunja.lng,
        ubicaciones: [tunja],
        visitasDelProfesional: [visita(fecha: DateTime(2026, 9, 22))],
        ahora: ahora,
      );
      expect(r.listas, isEmpty);
      expect(r.paraDespues, hasLength(1));
    });

    test('la visita en curso se retoma aunque la fecha haya pasado', () {
      final r = resolverRegistroVisita(
        lat: tunja.lat,
        lng: tunja.lng,
        ubicaciones: [tunja],
        visitasDelProfesional: [
          visita(estado: kVisitaEnCurso, fecha: DateTime(2026, 9, 10)),
        ],
        ahora: ahora,
      );
      expect(r.listas, hasLength(1));
    });

    test('fuera de todo radio: dice cuál es la más cercana', () {
      final r = resolverRegistroVisita(
        lat: 5.5400,
        lng: -73.3678,
        ubicaciones: [tunja, combita],
        visitasDelProfesional: [visita()],
        ahora: ahora,
      );
      expect(r.enUnEstablecimiento, isFalse);
      expect(r.masCercana, same(tunja));
      expect(r.distanciaMasCercana, closeTo(520, 30));
      expect(r.listas, isEmpty);
    });

    test('la precisión del GPS se descuenta como en el inicio', () {
      final r = resolverRegistroVisita(
        lat: 5.5370,
        lng: -73.3678,
        precisionMetros: 60,
        ubicaciones: [tunja],
        visitasDelProfesional: [visita()],
        ahora: ahora,
      );
      // ~190 m con ±60 m: puede estar adentro.
      expect(r.enUnEstablecimiento, isTrue);
      expect(r.listas, hasLength(1));
    });

    test('las terminadas y canceladas no cuentan', () {
      final r = resolverRegistroVisita(
        lat: tunja.lat,
        lng: tunja.lng,
        ubicaciones: [tunja],
        visitasDelProfesional: [
          visita(id: 'a', estado: kVisitaTerminada),
          visita(id: 'b', estado: kVisitaCancelada),
        ],
        ahora: ahora,
      );
      expect(r.listas, isEmpty);
    });
  });
}
