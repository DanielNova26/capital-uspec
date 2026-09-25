import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

InterventoriaVisita _visita({
  required String id,
  required String centroId,
  required String centroNombre,
  required DateTime fecha,
  required double total,
  double? categoria,
  bool categoriaNoEvaluada = false,
  String creadoPor = 'usuario',
  String faseActa = 'completa',
  String devolucionMotivo = '',
  String correccionResponsableId = '',
}) {
  final items = defaultInterventoriaItems();
  final categoriaKey = kInterventoriaCategorias.first.key;
  items[categoriaKey] = items[categoriaKey]!.copyWith(
    valor: categoria,
    noEvaluado: categoriaNoEvaluada,
    clearValor: categoria == null,
  );
  return InterventoriaVisita(
    id: id,
    empresaId: 'empresa',
    centroCostoId: centroId,
    centroCostoCodigo: centroId.toUpperCase(),
    centroCostoNombre: centroNombre,
    fechaVisita: Timestamp.fromDate(fecha),
    fechaRegistro: Timestamp.fromDate(fecha),
    creadoPor: creadoPor,
    porcentajeGeneral: total,
    items: items,
    faseActa: faseActa,
    devolucionMotivo: devolucionMotivo,
    correccionResponsableId: correccionResponsableId,
    createdAt: Timestamp.fromDate(fecha),
  );
}

void main() {
  group('edición de acta devuelta', () {
    final devuelta = _visita(
      id: 'acta-1',
      centroId: 'ubate',
      centroNombre: 'Ubaté',
      fecha: DateTime(2026, 9, 11),
      total: 80,
      creadoPor: 'registrador-1',
      faseActa: kFaseActaDevuelta,
      devolucionMotivo: 'Corregir los puntajes de almacenamiento',
      correccionResponsableId: 'administrador-1',
    );

    test('la puede corregir quien la subió o quien recibió la tarea', () {
      expect(
        puedeEditarActaDevuelta(visita: devuelta, userId: 'registrador-1'),
        isTrue,
      );
      expect(
        puedeEditarActaDevuelta(visita: devuelta, userId: 'administrador-1'),
        isTrue,
      );
      expect(
        puedeEditarActaDevuelta(visita: devuelta, userId: 'otro'),
        isFalse,
      );
    });

    test('reconoce devoluciones creadas por la versión anterior', () {
      final legado = _visita(
        id: 'acta-legado',
        centroId: 'ubate',
        centroNombre: 'Ubaté',
        fecha: DateTime(2026, 9, 10),
        total: 70,
        faseActa: 'puntajes',
        devolucionMotivo: 'Falta corregir el PDF adjunto',
      );
      expect(esActaDevueltaParaCorreccion(legado), isTrue);
    });

    test('la acción obligatoria pertenece solo al responsable explícito', () {
      expect(
        actasPendientesCorreccionDeUsuario([devuelta], 'administrador-1'),
        hasLength(1),
      );
      expect(
        actasPendientesCorreccionDeUsuario([devuelta], 'registrador-1'),
        isEmpty,
      );
    });

    test('una devolución histórica sin responsable obliga al registrador', () {
      final legado = _visita(
        id: 'acta-legado',
        centroId: 'ubate',
        centroNombre: 'Ubaté',
        fecha: DateTime(2026, 9, 10),
        total: 70,
        creadoPor: 'registrador-1',
        faseActa: kFaseActaDevuelta,
        devolucionMotivo: 'Corregir el soporte',
      );
      expect(actasPendientesCorreccionDeUsuario([legado], 'registrador-1'), [
        legado,
      ]);
    });

    test('ordena primero la corrección más antigua', () {
      final antigua = _visita(
        id: 'antigua',
        centroId: 'a',
        centroNombre: 'A',
        fecha: DateTime(2026, 9, 1),
        total: 70,
        faseActa: kFaseActaDevuelta,
        devolucionMotivo: 'Corregir soporte antiguo',
        correccionResponsableId: 'administrador-1',
      );
      expect(
        actasPendientesCorreccionDeUsuario([
          devuelta,
          antigua,
        ], 'administrador-1').map((v) => v.id),
        ['antigua', 'acta-1'],
      );
    });
  });

  group('corrección por quien registró el acta', () {
    InterventoriaVisita acta({
      String faseActa = 'puntajes',
      String creadoPor = 'registrador-1',
      String devolucionMotivo = '',
    }) => _visita(
      id: 'acta-2',
      centroId: 'ubate',
      centroNombre: 'Ubaté',
      fecha: DateTime(2026, 9, 15),
      total: 85,
      creadoPor: creadoPor,
      faseActa: faseActa,
      devolucionMotivo: devolucionMotivo,
    );

    test('la propia, sin revisar, se corrige directo', () {
      expect(
        puedeCorregirActaPropia(visita: acta(), userId: 'registrador-1'),
        isTrue,
      );
      expect(
        puedeSolicitarCorreccionActa(visita: acta(), userId: 'registrador-1'),
        isFalse,
      );
    });

    test('la de otra persona se solicita, aunque esté sin revisar', () {
      expect(puedeCorregirActaPropia(visita: acta(), userId: 'otro'), isFalse);
      expect(
        puedeSolicitarCorreccionActa(visita: acta(), userId: 'otro'),
        isTrue,
      );
    });

    test('la ya revisada se solicita, incluso la propia', () {
      final completa = acta(faseActa: 'completa');
      expect(
        puedeCorregirActaPropia(visita: completa, userId: 'registrador-1'),
        isFalse,
      );
      expect(
        puedeSolicitarCorreccionActa(visita: completa, userId: 'registrador-1'),
        isTrue,
      );
    });

    test(
      'una ya devuelta no ofrece ninguno de los dos: ya tiene "Corregir"',
      () {
        final devuelta = acta(
          faseActa: kFaseActaDevuelta,
          devolucionMotivo: 'La fecha de la visita está mal',
        );
        expect(
          puedeCorregirActaPropia(visita: devuelta, userId: 'registrador-1'),
          isFalse,
        );
        expect(
          puedeSolicitarCorreccionActa(
            visita: devuelta,
            userId: 'registrador-1',
          ),
          isFalse,
        );
      },
    );

    test('sin usuario no se corrige nada', () {
      expect(puedeCorregirActaPropia(visita: acta(), userId: ''), isFalse);
    });
  });

  test('solo el aprobador asignado puede resolver una subsanación', () {
    final hallazgo = InterventoriaHallazgo(
      empresaId: 'empresa',
      centroCostoId: 'centro',
      centroCostoNombre: 'Centro',
      descripcion: 'Hallazgo',
      fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 2)),
      aprobadorId: 'calidad-1',
      createdAt: Timestamp.fromDate(DateTime(2026, 9, 2)),
    );

    expect(puedeAprobarHallazgo(hallazgo, 'calidad-1'), isTrue);
    expect(puedeAprobarHallazgo(hallazgo, 'desarrollador'), isFalse);
  });

  test('la bandeja de asignación excluye lo ya subsanado', () {
    InterventoriaHallazgo hallazgo(String estado) => InterventoriaHallazgo(
      empresaId: 'empresa',
      centroCostoId: 'centro',
      centroCostoNombre: 'Centro',
      descripcion: 'Hallazgo',
      estado: estado,
      fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 2)),
      createdAt: Timestamp.fromDate(DateTime(2026, 9, 2)),
    );

    expect(debeAparecerEnTableroAsignacion(hallazgo('activo')), isTrue);
    expect(
      debeAparecerEnTableroAsignacion(hallazgo('pendiente_aprobacion')),
      isTrue,
    );
    expect(debeAparecerEnTableroAsignacion(hallazgo('subsanado')), isFalse);
  });

  group('catálogo de establecimientos', () {
    test('lee G1/G9 de los datos sin inferirlo desde el nombre', () {
      final g1 = CentroCostoRef.fromMap('a', {
        'nombre': 'Pasto',
        'grupo': 'Grupo 1',
      });
      final g9 = CentroCostoRef.fromMap('b', {
        'nombre': 'Ipiales',
        'codigo': 'CC-G09-014',
      });
      final sinGrupo = CentroCostoRef.fromMap('c', {
        'nombre': 'Establecimiento G1 solo en el nombre',
      });

      expect(g1.grupo, 'G1');
      expect(g9.grupo, 'G9');
      expect(sinGrupo.grupo, isEmpty);
    });

    test('agrupa G1 y G9 y ordena alfabéticamente cada grupo', () {
      const centros = [
        CentroCostoRef(
          centroId: '3',
          empresaId: 'e',
          codigo: '',
          nombre: 'Tunja',
          grupo: 'G9',
        ),
        CentroCostoRef(
          centroId: '2',
          empresaId: 'e',
          codigo: '',
          nombre: 'Bordo',
          grupo: 'G1',
        ),
        CentroCostoRef(
          centroId: '1',
          empresaId: 'e',
          codigo: '',
          nombre: 'Buen Pastor',
          grupo: 'G1',
        ),
        CentroCostoRef(
          centroId: '4',
          empresaId: 'e',
          codigo: '',
          nombre: 'Ipiales',
          grupo: 'G9',
        ),
      ];

      final grupos = agruparCentrosCosto(centros);

      expect(grupos.map((grupo) => grupo.grupo), ['G1', 'G9']);
      expect(grupos.first.centros.map((centro) => centro.nombre), [
        'Bordo',
        'Buen Pastor',
      ]);
      expect(grupos.last.centros.map((centro) => centro.nombre), [
        'Ipiales',
        'Tunja',
      ]);
    });
  });

  group('acta PDF obligatoria', () {
    test('acepta un PDF o imágenes que serán convertidas a PDF', () {
      expect(puedeGenerarActaPdf(['application/pdf']), isTrue);
      expect(puedeGenerarActaPdf(['image/jpeg']), isTrue);
      expect(puedeGenerarActaPdf(['text/plain']), isFalse);
      expect(puedeGenerarActaPdf(const []), isFalse);
    });

    test('la visita persistida debe contener un adjunto PDF', () {
      final pdf = InterventoriaAdjunto(
        url: 'https://example.test/acta.pdf',
        nombre: 'acta.pdf',
        path: 'acta.pdf',
        contentType: 'application/pdf',
        origen: 'web',
        fechaSubida: Timestamp.fromDate(DateTime(2026, 9, 2)),
      );

      expect(contieneActaPdf([pdf]), isTrue);
      expect(contieneActaPdf(const []), isFalse);
    });
  });

  group('calcularPorcentajeGeneral', () {
    test('ignora categorias no evaluadas', () {
      final items = defaultInterventoriaItems();
      final keys = kInterventoriaCategorias.map((c) => c.key).toList();

      items[keys[0]] = items[keys[0]]!.copyWith(valor: 100);
      items[keys[1]] = items[keys[1]]!.copyWith(valor: 80);
      items[keys[2]] = items[keys[2]]!.copyWith(
        noEvaluado: true,
        clearValor: true,
      );

      expect(calcularPorcentajeGeneral(items), 90);
    });

    test('retorna cero cuando no hay categorias evaluadas', () {
      final items = defaultInterventoriaItems().map(
        (key, value) =>
            MapEntry(key, value.copyWith(noEvaluado: true, clearValor: true)),
      );

      expect(calcularPorcentajeGeneral(items), 0);
    });
  });

  group('comparativo de última acta por establecimiento', () {
    test('conserva solo la visita más reciente de cada establecimiento', () {
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'a-vieja',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
        ),
        _visita(
          id: 'b',
          centroId: 'b',
          centroNombre: 'Beta',
          fecha: DateTime(2026, 8, 3),
          total: 82,
        ),
        _visita(
          id: 'a-nueva',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
        ),
      ]);

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.centroCostoNombre), ['Alfa', 'Beta']);
      expect(rows.first.visitaId, 'a-nueva');
      expect(rows.first.valor, 91);
    });

    test('no sustituye una categoría sin dato por una visita anterior', () {
      final categoriaKey = kInterventoriaCategorias.first.key;
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'anterior',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
          categoria: 88,
        ),
        _visita(
          id: 'ultima',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
          categoriaNoEvaluada: true,
        ),
      ], categoriaKey: categoriaKey);

      expect(rows.single.visitaId, 'ultima');
      expect(rows.single.valor, isNull);
    });
  });
}
