import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  const supervisor = InterventoriaUsuario(
    id: 'supervisor',
    nombre: 'Supervisor de la sede',
    cargo: 'Supervisor De Calidad',
    centroId: 'picota',
    areaId: 'calidad',
    jefeId: 'coordinador',
  );
  const coordinador = InterventoriaUsuario(
    id: 'coordinador',
    nombre: 'Jefe directo del supervisor',
    cargo: 'Coordinador de calidad',
    centroId: 'picota',
    areaId: 'calidad',
  );
  const directora = InterventoriaUsuario(
    id: 'directora',
    nombre: 'Directora corporativa',
    cargo: 'Directora de Calidad',
    centroId: 'oficina',
    areaId: 'calidad',
    cubreTodas: true,
  );

  test('la sede no hace que el supervisor sustituya a la directora', () {
    for (final usuarios in [
      [supervisor, coordinador, directora],
      [directora, coordinador, supervisor],
    ]) {
      final aprobador = resolverPrimerCargoQueResuelva(
        ['Director de calidad'],
        'picota',
        usuarios,
      );
      expect(aprobador?.id, directora.id);
      expect(aprobador?.delCentro, isTrue);
      expect(
        cargoDelAprobador(
          AprobadorPropuesto(aprobador, OrigenAprobador.maestro),
        ),
        'Directora de Calidad',
      );
    }
  });

  test('sin director la regla queda sin resolver para revisión manual', () {
    expect(
      resolverPrimerCargoQueResuelva(
        ['Director de calidad'],
        'picota',
        [supervisor, coordinador],
      ),
      isNull,
    );
  });

  test('una elección manual sin regla propone el jefe del responsable', () {
    final propuesta = resolverAprobadorAsignacion(
      responsableId: supervisor.id,
      usuarios: [supervisor, coordinador],
    );
    expect(propuesta.persona?.id, coordinador.id);
    expect(propuesta.origen, OrigenAprobador.jefeInmediato);
    expect(cargoDelAprobador(propuesta), coordinador.cargo);
  });

  test('el maestro sigue teniendo prioridad sobre el jefe directo', () {
    final propuesta = resolverAprobadorAsignacion(
      delMaestro: resolverCargoUnico('Director de calidad', 'picota', [
        supervisor,
        coordinador,
        directora,
      ]),
      responsableId: supervisor.id,
      usuarios: [supervisor, coordinador, directora],
    );
    expect(propuesta.persona?.id, directora.id);
    expect(propuesta.origen, OrigenAprobador.maestro);
  });

  for (final cargo in [
    'Supervisor de calidad',
    'Coordinadora de calidad',
    'Analista de calidad',
    'Subdirector de calidad',
  ]) {
    test('$cargo no equivale a director de calidad', () {
      expect(afinidadCargo('Director de calidad', cargo), isNull);
    });
  }

  test('elegir un supervisor manualmente conserva su cargo real', () {
    const persona = InterventoriaPersona(
      id: 'supervisor',
      nombre: 'Supervisor de la sede',
      cargo: 'Supervisor de Calidad',
      cargoMatriz: 'Director de calidad',
      delCentro: true,
    );
    for (final origen in [OrigenAprobador.elegido, OrigenAprobador.maestro]) {
      expect(
        cargoDelAprobador(AprobadorPropuesto(persona, origen)),
        'Supervisor de Calidad',
      );
    }
  });

  test('sin cargo personal no inventa el cargo del maestro', () {
    const persona = InterventoriaPersona(
      id: 'persona',
      nombre: 'Persona sin cargo registrado',
      cargo: '',
      cargoMatriz: 'Director de calidad',
      delCentro: true,
    );
    expect(
      cargoDelAprobador(
        const AprobadorPropuesto(persona, OrigenAprobador.elegido),
      ),
      isEmpty,
    );
  });
}
