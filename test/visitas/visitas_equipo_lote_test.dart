import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_models.dart';

/// Correcciones de Visitas del 25 sep 2026: ejecutar por secciones, qué
/// falta en cada una, plan de acción con responsable, formatos por cargo,
/// programar varias fechas, grupos y firmante del establecimiento.
void main() {
  VisitaFormatoItem item(
    String id,
    int orden,
    String seccion, {
    String parte = '',
    bool foto = false,
  }) => VisitaFormatoItem(
    id: id,
    orden: orden,
    seccion: seccion,
    texto: 'Pregunta $id',
    parte: parte,
    requiereEvidencia: foto,
  );

  VisitaProfesional visita({
    Map<String, VisitaRespuesta> respuestas = const {},
    Map<String, List<VisitaFilaTabla>> tablas = const {},
    String firmante = '',
    VisitaFirma? firmaEst,
    String estado = kVisitaEnCurso,
  }) => VisitaProfesional(
    id: 'v1',
    empresaId: 'capital',
    formatoId: 'f1',
    formatoNombre: 'Formato',
    areaId: 'EMP_nutricion',
    areaNombre: 'Nutrición',
    centroId: 'c1',
    centroNombre: 'Buen Pastor',
    profesionalId: 'prof',
    profesionalNombre: 'Profesional',
    asignadoPorId: 'jefe',
    asignadoPorNombre: 'Jefe',
    fechaProgramada: DateTime(2026, 9, 25),
    estado: estado,
    respuestas: respuestas,
    tablas: tablas,
    firmanteEstablecimientoId: firmante,
    firmaEstablecimiento: firmaEst,
  );

  group('pasosDeFormato', () {
    test('una página por sección, en el orden del formato', () {
      final f = VisitaFormato(
        empresaId: 'capital',
        areaId: 'a',
        areaNombre: 'A',
        nombre: 'F',
        items: [
          item('1', 1, 'Pisos'),
          item('2', 2, 'Pisos'),
          item('3', 3, 'Techos'),
        ],
      );
      final pasos = pasosDeFormato(f);
      expect(pasos.map((p) => p.titulo), ['Pisos', 'Techos']);
      expect(pasos.first.items.map((i) => i.id), ['1', '2']);
    });

    test('una sección de más de 20 preguntas se parte en tramos', () {
      final f = VisitaFormato(
        empresaId: 'capital',
        areaId: 'a',
        areaNombre: 'A',
        nombre: 'F',
        items: [for (var i = 1; i <= 45; i++) item('$i', i, 'Única')],
      );
      final pasos = pasosDeFormato(f);
      expect(pasos.map((p) => p.items.length), [20, 20, 5]);
      expect(pasos.map((p) => p.titulo), [
        'Única (1/3)',
        'Única (2/3)',
        'Única (3/3)',
      ]);
    });

    test('el formato SST: cada tabla es su propia página', () {
      final pasos = pasosDeFormato(formatoSstOficial('capital'));
      final tablas = pasos.where((p) => p.tabla != null).toList();
      expect(tablas, isNotEmpty);
      expect(tablas.every((p) => p.items.isEmpty), isTrue);
      // Ninguna página pasa de 20 preguntas.
      expect(pasos.every((p) => p.items.length <= 20), isTrue);
      // Y entre todas están todas las preguntas, una sola vez.
      final ids = [for (final p in pasos) ...p.items.map((i) => i.id)];
      expect(ids.toSet().length, formatoSstOficial('capital').items.length);
    });
  });

  group('qué falta en cada página', () {
    test('sin responder, no cumple sin observación o sin foto = pendiente', () {
      final sinFoto = item('x', 1, 's', foto: true);
      expect(itemPendiente(sinFoto, null), isTrue);
      expect(
        itemPendiente(sinFoto, const VisitaRespuesta(resultado: kItemCumple)),
        isFalse,
      );
      expect(
        itemPendiente(
          sinFoto,
          const VisitaRespuesta(resultado: kItemNoCumple, observacion: 'roto'),
        ),
        isTrue,
      );
    });

    test('pendientesDePaso cuenta preguntas y filas de tabla', () {
      final paso = VisitaPaso(items: [item('1', 1, 's'), item('2', 2, 's')]);
      final v = visita(
        respuestas: const {'1': VisitaRespuesta(resultado: kItemCumple)},
      );
      expect(pendientesDePaso(paso, v), 1);

      const tabla = VisitaFormatoTabla(
        id: 't',
        nombre: 'Extintores',
        camposEstado: [VisitaTablaCampo('e1', 'Manómetro')],
      );
      expect(pendientesDePaso(const VisitaPaso(tabla: tabla), visita()), 1);
      final completa = visita(
        tablas: {
          't': [
            const VisitaFilaTabla(id: 'f', estados: {'e1': kFilaBueno}),
          ],
        },
      );
      expect(pendientesDePaso(const VisitaPaso(tabla: tabla), completa), 0);
    });
  });

  group('plan de acción', () {
    test('la tarea va al responsable elegido, con su área', () {
      final f = VisitaFormato(
        empresaId: 'capital',
        areaId: 'EMP_nutricion',
        areaNombre: 'Nutrición',
        nombre: 'F',
        items: [item('1', 1, 's'), item('2', 2, 's')],
      );
      final v = visita(
        respuestas: const {
          '1': VisitaRespuesta(
            resultado: kItemNoCumple,
            observacion: 'Sin minuta',
            accion: 'Publicar la minuta',
            accionAreaId: 'EMP_mantenimiento',
            accionAreaNombre: 'Mantenimiento',
            accionResponsableId: 'ana',
            accionResponsableNombre: 'Ana',
          ),
          '2': VisitaRespuesta(resultado: kItemNoCumple, observacion: 'x'),
        },
      );
      final hs = hallazgosDeVisita(f, v.respuestas);
      final conPlan = destinatarioHallazgo(v, hs[0]);
      expect(conPlan.id, 'ana');
      expect(conPlan.areaId, 'EMP_mantenimiento');
      // Sin plan, como antes: al jefe que programó y con el área de la visita.
      final sinPlan = destinatarioHallazgo(v, hs[1]);
      expect(sinPlan.id, 'jefe');
      expect(sinPlan.areaId, 'EMP_nutricion');
      expect(descripcionTareaHallazgo(v, hs[0]), contains('Mantenimiento'));
    });

    test('la respuesta guarda y lee el plan completo', () {
      const r = VisitaRespuesta(
        resultado: kItemNoCumple,
        accion: 'Arreglar',
        accionAreaId: 'a1',
        accionAreaNombre: 'Área 1',
        accionResponsableId: 'p1',
        accionResponsableNombre: 'Pedro',
      );
      final leida = VisitaRespuesta.fromMap(r.toMap());
      expect(leida.accionAreaId, 'a1');
      expect(leida.accionResponsableNombre, 'Pedro');
    });
  });

  group('formatos por área y cargo', () {
    VisitaFormato formato(
      String id, {
      List<String> cargos = const [],
      bool pred = false,
      String estado = kFormatoVigente,
      String area = 'EMP_nutricion',
    }) => VisitaFormato(
      id: id,
      empresaId: 'capital',
      areaId: area,
      areaNombre: 'Nutrición',
      nombre: id,
      estado: estado,
      predeterminado: pred,
      cargos: cargos,
    );

    test('sin cargos aplica a todo el área; con cargos, solo a esos', () {
      expect(formatoAplicaACargo(formato('a'), 'Auxiliar'), isTrue);
      final f = formato('b', cargos: ['Nutricionista']);
      expect(formatoAplicaACargo(f, 'NUTRICIONISTA'), isTrue);
      expect(formatoAplicaACargo(f, 'Auxiliar'), isFalse);
    });

    test('propone el que nombra el cargo, luego el predeterminado', () {
      final lista = [
        formato('general', pred: true),
        formato('nutri', cargos: ['Nutricionista']),
        formato('borrador', estado: kFormatoBorrador, cargos: ['Auxiliar']),
      ];
      expect(
        formatoPropuesto(
          lista,
          areaId: 'EMP_nutricion',
          cargo: 'Nutricionista',
        )?.id,
        'nutri',
      );
      expect(
        formatoPropuesto(lista, areaId: 'EMP_nutricion', cargo: 'Auxiliar')?.id,
        'general',
      );
      expect(
        formatoPropuesto(
          lista,
          areaId: 'EMP_nutricion',
          cargo: 'Auxiliar',
          permitirBorrador: true,
        )?.id,
        'borrador',
      );
    });

    test('el formato guarda sus cargos', () {
      final f = formato('x', cargos: ['A', 'B']);
      expect(VisitaFormato.fromMap('x', f.toMap()).cargos, ['A', 'B']);
    });

    test('misma área con id de catálogo o con nombre', () {
      expect(mismaAreaVisitas('EMPRESA_002_nutricion', 'Nutrición'), isTrue);
      expect(
        mismaAreaVisitas('EMPRESA_002_nutricion', 'Mantenimiento'),
        isFalse,
      );
      expect(mismaAreaVisitas('', 'Nutrición'), isFalse);
    });
  });

  group('programar varias fechas', () {
    final hoy = DateTime(2026, 9, 25);

    test('marcar y desmarcar días en el calendario', () {
      var sel = alternarDia(<DateTime>{}, DateTime(2026, 9, 26, 15));
      sel = alternarDia(sel, DateTime(2026, 9, 27));
      expect(sel, {DateTime(2026, 9, 26), DateTime(2026, 9, 27)});
      sel = alternarDia(sel, DateTime(2026, 9, 26));
      expect(sel, {DateTime(2026, 9, 27)});
    });

    test('cada día necesita establecimiento y ninguno puede haber pasado', () {
      expect(validarProgramacion(const [], hoy: hoy), isNotEmpty);
      final errores = validarProgramacion([
        FilaProgramacion(fecha: DateTime(2026, 9, 24), centroId: 'c1'),
        FilaProgramacion(fecha: DateTime(2026, 9, 26)),
        FilaProgramacion(fecha: DateTime(2026, 9, 27), centroId: 'c1'),
        FilaProgramacion(fecha: DateTime(2026, 9, 27), centroId: 'c1'),
      ], hoy: hoy);
      expect(errores.length, 3);
      expect(
        validarProgramacion([
          FilaProgramacion(fecha: DateTime(2026, 9, 25), centroId: 'c1'),
          FilaProgramacion(fecha: DateTime(2026, 9, 26), centroId: 'c2'),
        ], hoy: hoy),
        isEmpty,
      );
    });
  });

  group('grupos', () {
    const grupos = [
      VisitaGrupo(
        id: 'g1',
        empresaId: 'capital',
        nombre: 'Norte',
        areaId: 'a',
        centroIds: ['c2', 'c3'],
        profesionalIds: ['prof'],
      ),
      VisitaGrupo(
        id: 'g2',
        empresaId: 'capital',
        nombre: 'Sur',
        areaId: 'a',
        centroIds: ['c9'],
      ),
    ];

    test('los establecimientos del grupo del profesional van primero', () {
      final delGrupo = centrosDelProfesional('prof', grupos);
      expect(delGrupo, {'c2', 'c3'});
      expect(ordenarPorGrupo(['c1', 'c2', 'c3', 'c4'], delGrupo, (c) => c), [
        'c2',
        'c3',
        'c1',
        'c4',
      ]);
    });

    test('un grupo necesita nombre y área', () {
      expect(
        validarGrupo(
          const VisitaGrupo(empresaId: 'capital', nombre: '', areaId: ''),
        ),
        hasLength(2),
      );
      expect(VisitaGrupo.fromMap('g1', grupos.first.toMap()).centroIds, [
        'c2',
        'c3',
      ]);
    });
  });

  group('firmante del establecimiento', () {
    test('solo el designado firma, con la visita en curso y sin firma', () {
      expect(
        visitasPuedeFirmarComoEstablecimiento(
          visita: visita(firmante: 'admin'),
          userId: 'admin',
        ),
        isTrue,
      );
      expect(
        visitasPuedeFirmarComoEstablecimiento(
          visita: visita(firmante: 'admin'),
          userId: 'otro',
        ),
        isFalse,
      );
      expect(
        visitasPuedeFirmarComoEstablecimiento(
          visita: visita(
            firmante: 'admin',
            firmaEst: const VisitaFirma(nombre: 'Admin', modo: 'dibujada'),
          ),
          userId: 'admin',
        ),
        isFalse,
      );
      expect(
        visitasPuedeFirmarComoEstablecimiento(
          visita: visita(firmante: 'admin', estado: kVisitaTerminada),
          userId: 'admin',
        ),
        isFalse,
      );
    });

    test('la firma guarda equipo y cuenta; el responsable, su cédula', () {
      final firma = VisitaFirma.fromMap(
        VisitaFirma(
          nombre: 'Admin',
          modo: kFirmaModoDibujada,
          dispositivo: 'App móvil · Android',
          firmadoPorId: 'admin',
          at: Timestamp.fromDate(DateTime(2026, 9, 25)),
        ).toMap(),
      );
      expect(firma.dispositivo, 'App móvil · Android');
      expect(firma.firmadoPorId, 'admin');
      final r = VisitaResponsable.fromMap(
        const VisitaResponsable(nombre: 'Admin', userId: 'admin').toMap(),
      );
      expect(r.userId, 'admin');
      final v = VisitaProfesional.fromMap(
        'v1',
        visita(firmante: 'admin').toMap(),
      );
      expect(v.firmanteEstablecimientoId, 'admin');
    });

    test('firmante y consulta no trabajan dentro de un área', () {
      expect(visitasRolRequiereArea(kVisitasRolFirmante), isFalse);
      expect(visitasRolRequiereArea(kVisitasRolConsulta), isFalse);
      expect(visitasRolRequiereArea(kVisitasRolProfesional), isTrue);
      expect(kVisitasRolesLabel.containsKey(kVisitasRolFirmante), isTrue);
    });
  });
}
