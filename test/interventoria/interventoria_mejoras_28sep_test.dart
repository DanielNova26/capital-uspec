import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Mejoras pedidas en la revisión de Interventoría del 28 sep 2026.
void main() {
  InterventoriaHallazgo hallazgo({
    String numeral = '3.1',
    String? tipoActa = kActaEstacionPolicia,
    String aprobadorId = '',
    String aprobadorNombre = '',
  }) => InterventoriaHallazgo(
    id: 'h1',
    empresaId: 'emp',
    centroCostoId: 'bordo',
    centroCostoNombre: 'Bordo',
    tipoActa: tipoActa,
    numeralActa: numeral,
    descripcion: 'El vehículo transportador cumple…',
    fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 23)),
    aprobadorId: aprobadorId,
    aprobadorNombre: aprobadorNombre,
    createdAt: Timestamp.fromDate(DateTime(2026, 9, 23)),
  );

  const miguel = InterventoriaUsuario(
    id: 'miguel',
    nombre: 'Miguel Romero',
    cargo: 'Director de operaciones',
    centroId: '',
    areaId: '',
  );
  const geisson = InterventoriaUsuario(
    id: 'geisson',
    nombre: 'Geisson Marenco',
    cargo: 'Supervisor de mantenimiento',
    centroId: 'bordo',
    areaId: '',
    jefeId: 'miguel',
  );
  const sinJefe = InterventoriaUsuario(
    id: 'alejandro',
    nombre: 'Alejandro',
    cargo: 'Administrador',
    centroId: 'bordo',
    areaId: '',
  );

  group('quién aprueba una asignación a mano', () {
    InterventoriaPersona persona(InterventoriaUsuario u) => InterventoriaPersona(
      id: u.id,
      nombre: u.nombre,
      cargo: u.cargo,
      cargoMatriz: '',
      delCentro: false,
    );

    test('sin regla en el maestro ya no falla: propone el jefe inmediato', () {
      // "Al asignar tarea a Miguel Romero me sale error… Bad state: La regla
      // no tiene un aprobador activo" (3.1 de un acta de policía).
      final propuesto = resolverAprobadorAsignacion(
        hallazgo: hallazgo(),
        responsableId: geisson.id,
        usuarios: const [miguel, geisson],
      );
      expect(propuesto.origen, OrigenAprobador.jefeInmediato);
      expect(propuesto.persona!.id, 'miguel');
      expect(cargoDelAprobador(propuesto), 'Director de operaciones');
    });

    test('sin regla ni jefe inmediato no inventa a nadie', () {
      final propuesto = resolverAprobadorAsignacion(
        hallazgo: hallazgo(),
        responsableId: sinJefe.id,
        usuarios: const [sinJefe, miguel],
      );
      expect(propuesto.persona, isNull);
      expect(propuesto.origen, OrigenAprobador.ninguno);
    });

    test('la persona elegida en pantalla manda sobre todo lo demás', () {
      final propuesto = resolverAprobadorAsignacion(
        elegido: persona(sinJefe),
        delMaestro: persona(miguel),
        hallazgo: hallazgo(aprobadorId: 'otro', aprobadorNombre: 'Otro'),
        responsableId: geisson.id,
        usuarios: const [miguel, geisson],
      );
      expect(propuesto.origen, OrigenAprobador.elegido);
      expect(propuesto.persona!.id, 'alejandro');
    });

    test('al reasignar se conserva el aprobador actual si se pide', () {
      final h = hallazgo(aprobadorId: 'ana', aprobadorNombre: 'Ana');
      final conservando = resolverAprobadorAsignacion(
        delMaestro: persona(miguel),
        hallazgo: h,
        preferirActual: true,
      );
      expect(conservando.origen, OrigenAprobador.actual);
      expect(conservando.persona!.nombre, 'Ana');
      // El servicio, sin preferencia, sigue la regla como siempre.
      final porRegla = resolverAprobadorAsignacion(
        delMaestro: persona(miguel),
        hallazgo: h,
      );
      expect(porRegla.origen, OrigenAprobador.maestro);
    });

    test('el cargo de la regla se conserva cuando el aprobador sale de ella', () {
      final propuesto = resolverAprobadorAsignacion(delMaestro: persona(miguel));
      expect(
        cargoDelAprobador(propuesto, cargoRegla: 'Director de operaciones'),
        'Director de operaciones',
      );
    });
  });

  group('el 3.1 que "no aparece" en el maestro', () {
    test('el acta regular no tiene 3.1; el de policía sí', () {
      expect(actasPropiasConNumeral('3.1'), contains(kActaEstacionPolicia));
      expect(responsabilidadDeNumeral('3.1'), isNull);
      expect(
        construirMaestroSubsanaciones(
          tipoActa: kActaRegular,
        ).any((f) => f.numeral == '3.1'),
        isFalse,
      );
      expect(
        construirMaestroSubsanaciones(
          tipoActa: kActaEstacionPolicia,
        ).any((f) => f.numeral == '3.1'),
        isTrue,
      );
    });

    test('el aviso nombra el maestro del acta del hallazgo', () {
      expect(
        nombreMaestroDeActa(kActaEstacionPolicia),
        'el maestro de Estación de policía',
      );
      expect(nombreMaestroDeActa(kActaSeguimiento), 'el maestro');
      expect(nombreMaestroDeActa(null), 'el maestro');
    });
  });

  group('Por revisar: días desde el cargue', () {
    test('el ejemplo de la reunión: cargada el 10/09, vista el 28/09', () {
      expect(
        diasDesdeCargue(DateTime(2026, 9, 10, 17, 30), DateTime(2026, 9, 28, 8)),
        18,
      );
    });

    test('el mismo día son cero días y una fecha futura no da negativo', () {
      expect(diasDesdeCargue(DateTime(2026, 9, 28, 7), DateTime(2026, 9, 28, 23)), 0);
      expect(diasDesdeCargue(DateTime(2026, 9, 29), DateTime(2026, 9, 28)), 0);
    });
  });

  group('Análisis', () {
    InterventoriaVisita visita(
      String id,
      String? tipo,
      DateTime fecha, {
      String centro = 'Bordo',
      double total = 90,
    }) => InterventoriaVisita(
      id: id,
      empresaId: 'emp',
      centroCostoId: centro.toLowerCase(),
      centroCostoCodigo: centro.toUpperCase(),
      centroCostoNombre: centro,
      fechaVisita: Timestamp.fromDate(fecha),
      fechaRegistro: Timestamp.fromDate(fecha),
      creadoPor: 'x',
      tipoActa: tipo,
      porcentajeGeneral: total,
      items: const {},
      createdAt: Timestamp.fromDate(fecha),
    );

    test('solo regulares: las mismas filas de siempre, sin títulos', () {
      final filas = filasMatrizAnalisis([
        visita('a', kActaRegular, DateTime(2026, 9, 1)),
        visita('b', kActaSeguimiento, DateTime(2026, 9, 2)),
      ]);
      expect(filas.any((f) => f.esTitulo), isFalse);
      expect(filas.length, kInterventoriaCategorias.length);
    });

    test('con actas de policía aparecen sus secciones, con su título', () {
      final regular = visita('a', kActaRegular, DateTime(2026, 9, 1));
      final policia = visita('p', kActaEstacionPolicia, DateTime(2026, 9, 2));
      final filas = filasMatrizAnalisis([regular, policia]);
      final titulos = filas.where((f) => f.esTitulo).map((f) => f.familia);
      expect(titulos, [kActaRegular, kActaEstacionPolicia]);
      final seccionesPolicia = filas.where(
        (f) => !f.esTitulo && f.familia == kActaEstacionPolicia,
      );
      expect(seccionesPolicia.length, kSeccionesActaEstacionPolicia.length);
      // La sección 1 de policía no se pinta en la columna de la regular.
      expect(seccionesPolicia.first.aplicaA(policia), isTrue);
      expect(seccionesPolicia.first.aplicaA(regular), isFalse);
    });

    test('el comparativo arranca por las actas más recientes', () {
      final puntos = compararUltimaActaPorEstablecimiento([
        visita('1', kActaRegular, DateTime(2026, 9, 1), centro: 'Acacias'),
        visita('2', kActaRegular, DateTime(2026, 9, 25), centro: 'Tunja'),
        visita('3', kActaRegular, DateTime(2026, 9, 20), centro: 'Bordo', total: 60),
      ]);
      expect(
        ordenarComparativo(
          puntos,
          OrdenComparativo.recientes,
        ).map((p) => p.centroCostoNombre),
        ['Tunja', 'Bordo', 'Acacias'],
      );
      expect(
        ordenarComparativo(
          puntos,
          OrdenComparativo.nombre,
        ).map((p) => p.centroCostoNombre),
        ['Acacias', 'Bordo', 'Tunja'],
      );
      expect(
        ordenarComparativo(
          puntos,
          OrdenComparativo.menorPuntaje,
        ).first.centroCostoNombre,
        'Bordo',
      );
    });
  });

  group('Concepto sanitario', () {
    final hoy = DateTime(2026, 9, 28);

    test('valida los cuatro datos del acta', () {
      String? validar({
        String centro = 'sogamoso',
        DateTime? fecha,
        double? puntaje = 92,
        String concepto = kConceptoFavorable,
      }) => validarConceptoSanitario(
        centroCostoId: centro,
        fecha: fecha ?? DateTime(2026, 9, 10),
        puntaje: puntaje,
        concepto: concepto,
        hoy: hoy,
      );
      expect(validar(), isNull);
      expect(validar(centro: ''), isNotNull);
      expect(validar(fecha: DateTime(2026, 9, 29)), isNotNull);
      expect(validar(puntaje: null), isNotNull);
      expect(validar(puntaje: 101), isNotNull);
      expect(validar(concepto: 'OK'), isNotNull);
    });

    test('el vigente de cada sede es el más reciente', () {
      InterventoriaConceptoSanitario c(String id, String centro, DateTime f) =>
          InterventoriaConceptoSanitario(
            id: id,
            empresaId: 'emp',
            centroCostoId: centro,
            centroCostoNombre: centro,
            fecha: f,
            puntaje: 90,
            concepto: kConceptoFavorable,
          );
      final vigentes = conceptoVigentePorEstablecimiento([
        c('viejo', 'sogamoso', DateTime(2026, 1, 10)),
        c('nuevo', 'sogamoso', DateTime(2026, 9, 10)),
        c('unico', 'tunja', DateTime(2026, 5, 1)),
      ]);
      expect(vigentes['sogamoso']!.id, 'nuevo');
      expect(vigentes['tunja']!.id, 'unico');
    });

    test('ida y vuelta por Firestore conserva los datos', () {
      final original = InterventoriaConceptoSanitario(
        empresaId: 'emp',
        centroCostoId: 'sogamoso',
        centroCostoNombre: 'Sogamoso',
        fecha: DateTime(2026, 9, 10),
        puntaje: 87.5,
        concepto: kConceptoFavorableRequerimientos,
        registradoPor: '123',
        registradoPorNombre: 'Kary',
      );
      final leido = InterventoriaConceptoSanitario.fromMap(
        'id1',
        original.toMap(),
      );
      expect(leido.centroCostoNombre, 'Sogamoso');
      expect(leido.fecha, DateTime(2026, 9, 10));
      expect(leido.puntaje, 87.5);
      expect(leido.concepto, kConceptoFavorableRequerimientos);
      expect(leido.acta, isNull);
      expect(
        etiquetaConceptoSanitario(leido.concepto),
        'Favorable con requerimientos',
      );
    });
  });
}
