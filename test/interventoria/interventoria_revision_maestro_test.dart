import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_revision_maestro.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Maestro › Revisión (25 sep 2026): "cuáles son los cargos que sí existen,
/// cuáles no... y para esos mismos corregirlos o generar la asignación".
void main() {
  const adminA = InterventoriaUsuario(
    id: 'admin-a',
    nombre: 'Ana Admin',
    cargo: 'Administrador',
    centroId: 'A',
    areaId: '',
  );
  const director = InterventoriaUsuario(
    id: 'dir',
    nombre: 'Diego Director',
    cargo: 'Director de operaciones',
    centroId: 'OFICINA',
    areaId: '',
  );
  const noOperativo = InterventoriaUsuario(
    id: 'nutri',
    nombre: 'Nora Nutri',
    cargo: 'Nutricionista',
    centroId: 'OFICINA',
    areaId: '',
  );
  const activos = [adminA, director, noOperativo];
  // La nutricionista está activa pero marcada como no operativa.
  const asignables = [adminA, director];

  const centroA = CentroCostoRef(
    centroId: 'A',
    empresaId: 'emp',
    codigo: 'A',
    nombre: 'Sede A',
  );
  const centroB = CentroCostoRef(
    centroId: 'B',
    empresaId: 'emp',
    codigo: 'B',
    nombre: 'Sede B',
  );

  // Regla guardada con un cargo que no existe en ninguna parte.
  final reglas = <String, dynamic>{
    claveRegla(kActaInfraestructura, '1.1'): {
      'responsables': ['Cocinero jefe', 'Administrador'],
      'aprobadores': ['Director de operaciones'],
    },
    claveRegla(kActaInfraestructura, '1.2'): {
      'responsables': ['Nutricionista'],
      'aprobadores': ['Director de operaciones'],
    },
  };

  group('cargos del maestro', () {
    final revision = revisarCargosDelMaestro(
      reglas: reglas,
      cargosCatalogo: const [
        'Administrador',
        'Director de operaciones',
        'Nutricionista',
        'Coordinador de calidad',
      ],
      usuariosActivos: activos,
      usuariosAsignables: asignables,
    );
    RevisionCargoMaestro de(String cargo) =>
        revision.singleWhere((r) => r.cargo == cargo);

    test('el que no está en TBL_CARGOS ni lo tiene nadie: "No existe"', () {
      expect(de('Cocinero jefe').estado, EstadoCargoMaestro.noExiste);
      expect(de('Cocinero jefe').comoResponsable, ['Infraestructura 1.1']);
    });

    test('el que existe y tiene personas: "Existe", con quiénes', () {
      final admin = de('Administrador');
      expect(admin.estado, EstadoCargoMaestro.ok);
      expect(admin.personas.map((p) => p.id), ['admin-a']);
      // La matriz incluida de la regular también cuenta.
      expect(admin.comoResponsable, contains('Regular 2.14'));
      expect(de('Director de operaciones').comoAprobador, isNotEmpty);
    });

    test('responsable que solo tienen personas que no reciben tareas', () {
      expect(de('Nutricionista').estado, EstadoCargoMaestro.sinAsignables);
    });

    test('los problemas salen primero', () {
      expect(revision.first.estado, EstadoCargoMaestro.noExiste);
      final primerOk = revision.indexWhere(
        (r) => r.estado == EstadoCargoMaestro.ok,
      );
      expect(
        revision.skip(primerOk).every((r) => r.estado == EstadoCargoMaestro.ok),
        isTrue,
      );
    });
  });

  group('reemplazar un cargo en todo el maestro', () {
    test('cambia la regla guardada y no repite el cargo', () {
      final cambios = reglasConCargoReemplazado(
        reglas: reglas,
        cargoActual: 'Cocinero jefe',
        cargoNuevo: 'Administrador',
        actualizadoPor: 'daniel',
        actualizadoEn: 'ahora',
      );
      expect(cambios.keys, [claveRegla(kActaInfraestructura, '1.1')]);
      final regla = cambios.values.single;
      expect(regla['responsables'], ['Administrador']);
      expect(regla['responsable'], 'Administrador');
      expect(regla['aprobadores'], ['Director de operaciones']);
      expect(regla['tipoActa'], kActaInfraestructura);
      expect(regla['actualizadoPor'], 'daniel');
    });

    test('guarda como regla propia lo que venía de la matriz incluida', () {
      final cambios = reglasConCargoReemplazado(
        reglas: const {},
        cargoActual: 'administrador',
        cargoNuevo: 'Administrador tipo 1',
        actualizadoPor: 'daniel',
        actualizadoEn: 'ahora',
      );
      final regla = cambios[claveRegla(kActaRegular, '2.14')];
      expect(regla, isNotNull);
      expect(regla!['responsables'], ['Administrador tipo 1']);
      expect(regla['aprobadores'], ['Director de operaciones']);
    });

    test('sin cargo nuevo no cambia nada', () {
      expect(
        reglasConCargoReemplazado(
          reglas: reglas,
          cargoActual: 'Cocinero jefe',
          cargoNuevo: ' ',
          actualizadoPor: 'daniel',
          actualizadoEn: 'ahora',
        ),
        isEmpty,
      );
    });
  });

  group('por establecimiento', () {
    final sedes = revisarSedes(
      reglas: const {},
      centros: const [centroA, centroB],
      usuariosActivos: activos,
      usuariosAsignables: asignables,
    );
    GrupoReglaSede grupoAdmin(String centroId) => sedes
        .singleWhere((s) => s.centro.centroId == centroId)
        .grupos
        .singleWhere(
          (g) =>
              g.responsable.cargos.length == 1 &&
              g.responsable.cargos.single == 'Administrador' &&
              g.aprobador.cargos.single == 'Director de operaciones',
        );

    test(
      'en su sede el administrador responde; el director aprueba desde fuera',
      () {
        final g = grupoAdmin('A');
        expect(g.responsable.cobertura, CoberturaRol.enSede);
        expect(g.responsable.persona?.id, 'admin-a');
        expect(g.aprobador.cobertura, CoberturaRol.fueraDeSede);
        expect(g.bloquea, isFalse);
        expect(g.numerales, contains('Regular 2.14'));
      },
    );

    test(
      'una sede sin administrador propio se ve: la tarea sale de la sede',
      () {
        final g = grupoAdmin('B');
        expect(g.responsable.cobertura, CoberturaRol.fueraDeSede);
        expect(g.responsableFuera, isTrue);
      },
    );
  });

  group('hallazgos sin tarea', () {
    InterventoriaHallazgo hallazgo(
      String id, {
      String numeral = '2.14',
      String centro = 'A',
      String tareaId = '',
      String estado = 'activo',
      String tipoActa = kActaRegular,
    }) => InterventoriaHallazgo.fromMap(id, {
      'empresaId': 'emp',
      'centroCostoId': centro,
      'centroCostoNombre': 'Sede $centro',
      'numeralActa': numeral,
      'tipoActa': tipoActa,
      'estado': estado,
      'tareaId': tareaId,
      'fuente': 'acta',
    });

    test('cuenta los que se pueden asignar y por qué se quedan los demás', () {
      final prevision = preverAsignacionPendiente(
        hallazgos: [
          hallazgo('1'),
          hallazgo('2', centro: 'B'),
          hallazgo('3', numeral: ''),
          hallazgo('4', tareaId: 'ya-tiene'),
          hallazgo('5', estado: 'subsanado'),
          hallazgo('6', numeral: '1.1', tipoActa: kActaInfraestructura),
        ],
        reglas: const {},
        usuariosActivos: activos,
        usuariosAsignables: asignables,
      );
      // 4 y 5 no cuentan: ya tienen tarea o están subsanados.
      expect(prevision.total, 4);
      // La sede B no tiene administrador, pero la asignación real acepta al de
      // otra sede (solo el tablero en lote exige la misma sede).
      expect(prevision.asignables, 2);
      expect(prevision.porMotivo[MotivoSinAsignar.sinNumeral], 1);
      // Infraestructura no trae matriz: sin regla guardada no hay a quién.
      expect(prevision.porMotivo[MotivoSinAsignar.reglaIncompleta], 1);
      expect(prevision.cargosQueFaltan, {
        'Regla Infraestructura 1.1 sin cargos': 1,
      });
      expect(prevision.asignablesPorSede, {'Sede A': 1, 'Sede B': 1});
    });

    test('dice qué cargo detiene los hallazgos', () {
      final prevision = preverAsignacionPendiente(
        hallazgos: [
          hallazgo('1', numeral: '1.1', tipoActa: kActaInfraestructura),
        ],
        reglas: {
          claveRegla(kActaInfraestructura, '1.1'): {
            'responsables': ['Cocinero jefe'],
            'aprobadores': ['Director de operaciones'],
          },
        },
        usuariosActivos: activos,
        usuariosAsignables: asignables,
      );
      expect(prevision.asignables, 0);
      expect(prevision.porMotivo[MotivoSinAsignar.sinResponsable], 1);
      expect(prevision.cargosQueFaltan, {'Cocinero jefe': 1});
    });
  });

  // 26 sep 2026: "poder editar desde ahí, seleccionar a otra persona... más
  // grupal". Cambiar a la persona de una sede = cambiar su cobertura.
  group('cambiar quién responde en una sede', () {
    const bacom = CentroCostoRef(
      centroId: 'BAC',
      empresaId: 'emp',
      codigo: 'BAC',
      nombre: 'Bacom',
      grupo: 'G1',
    );
    const picota = CentroCostoRef(
      centroId: 'PIC',
      empresaId: 'emp',
      codigo: 'PIC',
      nombre: 'Picota',
      grupo: 'G1',
    );
    const combita = CentroCostoRef(
      centroId: 'COM',
      empresaId: 'emp',
      codigo: 'COM',
      nombre: 'Cómbita',
      grupo: 'G9',
    );
    final porGrupo = centrosPorGrupo(const [bacom, picota, combita]);
    const gineth = InterventoriaUsuario(
      id: 'gineth',
      nombre: 'Gineth',
      cargo: 'Coordinador de calidad',
      centroId: 'OFICINA',
      areaId: '',
    );
    const carlos = InterventoriaUsuario(
      id: 'carlos',
      nombre: 'Carlos',
      cargo: 'Coordinador de calidad',
      centroId: 'OFICINA',
      areaId: '',
    );
    const cargos = ['Coordinador de calidad'];

    test('los centros se agrupan por grupo', () {
      expect(porGrupo, {
        'G1': {'BAC', 'PIC'},
        'G9': {'COM'},
      });
    });

    test('sin cobertura, nadie responde "en la sede"', () {
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlos,
        alcance: AlcanceCobertura.sede,
        usuarios: const [gineth, carlos],
        porGrupo: porGrupo,
      );
      expect(plan.cambios.single.userId, 'carlos');
      expect(plan.cambios.single.agregarCentros, {'BAC'});
      expect(plan.quedaria?.id, 'carlos');
      expect(plan.quedaElegido, isTrue);
    });

    test('todo el grupo: un coordinador de calidad por grupo', () {
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlos,
        alcance: AlcanceCobertura.grupo,
        usuarios: const [gineth, carlos],
        porGrupo: porGrupo,
      );
      expect(plan.cambios.single.agregarGrupos, {'G1'});
      final conGrupo = aplicarCambioCobertura(
        carlos,
        plan.cambios.single,
        porGrupo,
      );
      expect(conGrupo.cubreCentro('BAC'), isTrue);
      expect(conGrupo.cubreCentro('PIC'), isTrue);
      expect(conGrupo.cubreCentro('COM'), isFalse);
    });

    test('a quien cubría la sede con el mismo cargo se le quita', () {
      final ginethEnBacom = gineth.copyWith(
        centrosAsignadosIds: {'BAC', 'COM'},
        centrosOperacionIds: {'BAC', 'COM'},
      );
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlos,
        alcance: AlcanceCobertura.sede,
        usuarios: [ginethEnBacom, carlos],
        porGrupo: porGrupo,
      );
      final quitar = plan.cambios.singleWhere((c) => c.userId == 'gineth');
      expect(quitar.quitarCentros, {'BAC'});
      expect(plan.quedaria?.id, 'carlos');
      final despues = aplicarCambioCobertura(ginethEnBacom, quitar, porGrupo);
      // Solo pierde Bacom; Cómbita la conserva.
      expect(despues.centrosOperacionIds, {'COM'});
      expect(despues.cubreCentro('COM'), isTrue);
    });

    test('si la cubre por su grupo, se avisa en vez de tocar el grupo', () {
      final ginethG1 = gineth.copyWith(
        grupos: {'G1'},
        centrosAsignadosIds: {'BAC', 'PIC'},
      );
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlos,
        alcance: AlcanceCobertura.sede,
        usuarios: [ginethG1, carlos],
        porGrupo: porGrupo,
      );
      expect(plan.cambios.map((c) => c.userId), ['carlos']);
      expect(plan.avisos.single, contains('grupo G1'));
    });

    test('sin quitar a los demás, la vista previa dice quién queda', () {
      final ginethEnBacom = gineth.copyWith(
        centrosAsignadosIds: {'BAC'},
        centrosOperacionIds: {'BAC'},
      );
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlos,
        alcance: AlcanceCobertura.sede,
        usuarios: [ginethEnBacom, carlos],
        porGrupo: porGrupo,
        quitarALosDemas: false,
      );
      // Las dos cubren Bacom con el mismo cargo; el desempate es por nombre
      // y gana Carlos, pero la vista previa lo dice en vez de suponerlo.
      expect(plan.quedaria?.delCentro, isTrue);
      expect(plan.cambios.map((c) => c.userId), ['carlos']);
    });

    test('quien ya cubre la sede no necesita cambios', () {
      final carlosEnBacom = carlos.copyWith(
        centrosAsignadosIds: {'BAC'},
        centrosOperacionIds: {'BAC'},
      );
      final plan = planearCambioEnSede(
        sede: bacom,
        cargos: cargos,
        elegido: carlosEnBacom,
        alcance: AlcanceCobertura.sede,
        usuarios: [gineth, carlosEnBacom],
        porGrupo: porGrupo,
      );
      expect(plan.cambios, isEmpty);
      expect(plan.quedaElegido, isTrue);
    });

    test('las reglas sin cargos se cuentan una vez, no por sede', () {
      final sinCargos = reglasSinCargos(const {});
      expect(sinCargos['Infraestructura'], greaterThan(0));
      final sedes = revisarSedes(
        reglas: const {},
        centros: const [bacom],
        usuariosActivos: const [gineth],
        usuariosAsignables: const [gineth],
      );
      expect(
        sedes.single.grupos.every(
          (g) =>
              g.responsable.cargos.isNotEmpty && g.aprobador.cargos.isNotEmpty,
        ),
        isTrue,
      );
    });
  });
}
