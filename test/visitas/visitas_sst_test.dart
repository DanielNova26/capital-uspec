import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_models.dart';

/// Lo que llegó el 17 sep 2026: formato SST oficial (tres hojas), maestro
/// de ubicaciones con radio, firmas obligatorias y reprogramación.
void main() {
  final sst = formatoSstOficial('capital');

  VisitaProfesional visita({
    Map<String, VisitaRespuesta> respuestas = const {},
    Map<String, List<VisitaFilaTabla>> tablas = const {},
    String estado = kVisitaEnCurso,
    bool iniciada = true,
    VisitaResponsable responsable = const VisitaResponsable(nombre: 'Ana'),
    VisitaFirma? firmaPro,
    VisitaFirma? firmaEst,
    String profesionalId = '111',
  }) => VisitaProfesional(
    id: 'v',
    empresaId: 'capital',
    formatoId: sst.id,
    formatoNombre: sst.nombre,
    areaId: sst.areaId,
    areaNombre: sst.areaNombre,
    centroId: 'tunja',
    centroNombre: 'Tunja',
    profesionalId: profesionalId,
    profesionalNombre: 'Miguel',
    asignadoPorId: '222',
    asignadoPorNombre: 'Oscar',
    fechaProgramada: DateTime(2026, 9, 17),
    estado: estado,
    inicio: iniciada ? VisitaMarca(at: Timestamp.now()) : null,
    respuestas: respuestas,
    tablas: tablas,
    responsableEstablecimiento: responsable,
    firmaProfesional: firmaPro,
    firmaEstablecimiento: firmaEst,
  );

  const firma = VisitaFirma(nombre: 'X', modo: kFirmaModoDibujada);
  const cumple = VisitaRespuesta(resultado: kItemCumple);

  /// Todo cumple, extintor en buen estado, encabezado y firmas: cierra.
  Map<String, VisitaRespuesta> todoCumple() => {
    for (final it in sst.items) it.id: cumple,
  };
  final extintor = sst.tabla(kTablaExtintores)!;
  VisitaFilaTabla filaBuena({String id = 'f1'}) => VisitaFilaTabla(
    id: id,
    campos: const {'ubicacion': 'Cocina', 'tipo': 'ABC'},
    estados: {for (final c in extintor.camposEstado) c.id: kFilaBueno},
  );

  group('formato SST oficial', () {
    test('es válido, vigente y trae las tres hojas con sus ítems', () {
      expect(validarFormato(sst), isEmpty);
      expect(sst.estado, kFormatoVigente);
      expect(sst.partes.map((p) => p.codigo), [
        kParteSstDiagnostico,
        kParteSstExtintores,
        kParteSstBotiquin,
      ]);
      expect(sst.itemsDeParte(kParteSstDiagnostico).length, 77);
      expect(sst.itemsDeParte(kParteSstExtintores), isEmpty);
      expect(sst.tablasDeParte(kParteSstExtintores).single.id, kTablaExtintores);
      expect(sst.itemsDeParte(kParteSstBotiquin).length, 4 + 25 + 3);
      expect(extintor.camposEstado.length, 13);
      expect(extintor.camposTexto.length, 6);
    });

    test('los ids son únicos y estables entre generaciones', () {
      final ids = sst.items.map((i) => i.id).toSet();
      expect(ids.length, sst.items.length);
      expect(ids, contains('sst02_01'));
      expect(ids, contains('sst01_e25'));
      expect(formatoSstOficial('otra').items.map((i) => i.id), ids);
    });

    test('el diagnóstico califica 1/0/NA; botiquín sí/no y elementos', () {
      final diag = sst.itemsDeParte(kParteSstDiagnostico);
      expect(diag.every((i) => i.tipo == kItemTipoCalificacion), isTrue);
      final bot = sst.itemsDeParte(kParteSstBotiquin);
      expect(bot.where((i) => i.tipo == kItemTipoSiNo).length, 7);
      expect(bot.where((i) => i.esElemento).length, 25);
      expect(bot.firstWhere((i) => i.id == 'sst01_e01').unidad, '1 Unidad');
      expect(resultadosPermitidos(kItemTipoSiNo), isNot(contains(kItemNoAplica)));
    });

    test('sobrevive al viaje por Firestore con partes, tablas y tipos', () {
      final back = VisitaFormato.fromMap(sst.id, sst.toMap());
      expect(back.partes.length, 3);
      expect(back.tablas.single.camposEstado.length, 13);
      expect(
        back.items.firstWhere((i) => i.id == 'sst01_e01').tipo,
        kItemTipoElemento,
      );
      expect(back.items.firstWhere((i) => i.id == 'sst02_01').parte, kParteSstDiagnostico);
    });
  });

  group('ubicación', () {
    const ref = VisitaUbicacion(
      empresaId: 'capital',
      centroId: 'tunja',
      centroNombre: 'Tunja',
      lat: 5.5353,
      lng: -73.3678,
      radioMetros: 150,
    );

    test('haversine: dos puntos a ~1 km', () {
      final d = distanciaMetros(5.5353, -73.3678, 5.5443, -73.3678);
      expect(d, closeTo(1000, 15));
      expect(distanciaMetros(1, 1, 1, 1), 0);
    });

    test('sin GPS no se inicia, con motivo claro', () {
      final r = verificarUbicacionInicio(referencia: ref, lat: null, lng: null);
      expect(r.permitido, isFalse);
      expect(r.motivo, contains('GPS'));
    });

    test('sin referencia en el maestro no se inicia', () {
      final r = verificarUbicacionInicio(referencia: null, lat: 5.5, lng: -73.3);
      expect(r.permitido, isFalse);
      expect(r.motivo, contains('maestro'));
    });

    test('dentro del radio sí; fuera no y dice la distancia', () {
      final dentro = verificarUbicacionInicio(
        referencia: ref,
        lat: 5.5360,
        lng: -73.3678,
      );
      expect(dentro.permitido, isTrue);
      expect(dentro.distancia, closeTo(78, 5));

      final fuera = verificarUbicacionInicio(
        referencia: ref,
        lat: 5.5400,
        lng: -73.3678,
      );
      expect(fuera.permitido, isFalse);
      expect(fuera.motivo, contains('m de Tunja'));
      expect(fuera.motivo, contains('150 m'));
    });

    test('la precisión del GPS se descuenta, hasta 100 m', () {
      // 200 m del punto con ±60 m: 140 ≤ 150 → pasa.
      final r = verificarUbicacionInicio(
        referencia: ref,
        lat: 5.5371,
        lng: -73.3678,
        precisionMetros: 60,
      );
      expect(r.permitido, isTrue);
      // Con ±500 solo se descuentan 100: 200 − 100 = 100 pasa, pero a 300 no.
      final lejos = verificarUbicacionInicio(
        referencia: ref,
        lat: 5.5380,
        lng: -73.3678,
        precisionMetros: 500,
      );
      expect(lejos.permitido, isFalse);
    });

    test('docId con y sin subcentro', () {
      expect(VisitaUbicacion.docId('e', 'c', ''), 'e_c');
      expect(VisitaUbicacion.docId('e', 'c', 'alta'), 'e_c__alta');
    });
  });

  group('cierre con tablas, encabezado y firmas', () {
    test('todo en orden cierra', () {
      final v = visita(
        respuestas: todoCumple(),
        tablas: {
          kTablaExtintores: [filaBuena()],
        },
        firmaPro: firma,
        firmaEst: firma,
      );
      expect(validarCierreVisita(sst, v), isEmpty);
    });

    test('faltan las dos firmas, el responsable y la tabla vacía', () {
      final v = visita(
        respuestas: todoCumple(),
        responsable: const VisitaResponsable(),
      );
      final e = validarCierreVisita(sst, v);
      expect(e.any((x) => x.contains('firma de quien realiza')), isTrue);
      expect(e.any((x) => x.contains('firma del responsable')), isTrue);
      expect(e.any((x) => x.contains('nombre del responsable')), isTrue);
      expect(e.any((x) => x.contains('Extintores: no hay')), isTrue);
    });

    test('un extintor con estado sin marcar o Malo sin novedad no cierra', () {
      final incompleta = filaBuena().copyWith(
        estados: {for (final c in extintor.camposEstado.skip(1)) c.id: kFilaBueno},
      );
      final malaSinObs = filaBuena(id: 'f2').copyWith(
        estados: {
          for (final c in extintor.camposEstado) c.id: kFilaBueno,
          'sello': kFilaMalo,
        },
      );
      final v = visita(
        respuestas: todoCumple(),
        tablas: {
          kTablaExtintores: [incompleta, malaSinObs],
        },
        firmaPro: firma,
        firmaEst: firma,
      );
      final e = validarCierreVisita(sst, v);
      expect(e.any((x) => x.contains('Extintor 1: falta')), isTrue);
      expect(e.any((x) => x.contains('Extintor 2 tiene novedad')), isTrue);
    });

    test('un NA en un ítem sí/no no se admite', () {
      final r = todoCumple();
      r['sst01_c1'] = const VisitaRespuesta(resultado: kItemNoAplica);
      final v = visita(
        respuestas: r,
        tablas: {
          kTablaExtintores: [filaBuena()],
        },
        firmaPro: firma,
        firmaEst: firma,
      );
      expect(
        validarCierreVisita(sst, v).any((x) => x.contains('no admite')),
        isTrue,
      );
    });
  });

  group('hallazgos y resumen', () {
    test('las filas en M o NC son hallazgos junto con los "no cumple"', () {
      final r = todoCumple();
      r['sst02_01'] = const VisitaRespuesta(
        resultado: kItemNoCumple,
        observacion: 'Pasillo con cajas',
        accion: 'Despejar',
      );
      final fila = filaBuena().copyWith(
        estados: {
          for (final c in extintor.camposEstado) c.id: kFilaBueno,
          'sello': kFilaNoCuenta,
          'presionManometro': kFilaMalo,
        },
        observacion: 'Sin sello y aguja en rojo',
      );
      final h = hallazgosDeVisita(
        sst,
        r,
        tablas: {
          kTablaExtintores: [fila],
        },
      );
      expect(h.length, 2);
      expect(h.first.clave, 'sst02_01');
      expect(h.first.accion, 'Despejar');
      expect(h.last.clave, 'extintores:f1');
      expect(h.last.elemento, 'Extintor Cocina');
      expect(h.last.novedad, contains('Sello de Garantía: No cuenta'));
      expect(h.last.novedad, contains('aguja en rojo'));
      expect(hallazgosDe(visita(respuestas: r, tablas: {kTablaExtintores: [fila]})), 2);
    });

    test('resumen por parte: NA no resta y el % es sobre lo evaluado', () {
      final r = todoCumple();
      r['sst02_01'] = const VisitaRespuesta(resultado: kItemNoAplica);
      r['sst02_02'] = const VisitaRespuesta(resultado: kItemNoCumple, observacion: 'x');
      final diag = resumenDeVisita(sst, r, parte: kParteSstDiagnostico);
      expect(diag.total, 77);
      expect(diag.noAplica, 1);
      expect(diag.noCumple, 1);
      expect(diag.porcentaje, (75 * 100 / 76).round());
      final bot = resumenDeVisita(sst, r, parte: kParteSstBotiquin);
      expect(bot.porcentaje, 100);
    });
  });

  group('reprogramar', () {
    test('solo el jefe reprograma; el profesional ni la suya (18 sep 2026)', () {
      final propia = visita(estado: kVisitaProgramada, iniciada: false);
      final ajena = visita(
        estado: kVisitaProgramada,
        iniciada: false,
        profesionalId: '999',
      );
      expect(
        visitasPuedeReprogramar(rol: kVisitasRolJefe, visita: ajena, userId: '222'),
        isTrue,
      );
      expect(
        visitasPuedeReprogramar(rol: kVisitasRolProfesional, visita: propia, userId: '111'),
        isFalse,
        reason: 'el cronograma lo corrige únicamente la dirección',
      );
      expect(
        visitasPuedeReprogramar(rol: kVisitasRolProfesional, visita: ajena, userId: '111'),
        isFalse,
      );
      expect(
        visitasPuedeReprogramar(rol: kVisitasRolConsulta, visita: propia, userId: '111'),
        isFalse,
      );
      expect(
        visitasPuedeReprogramar(rol: kVisitasRolJefe, visita: visita(), userId: '222'),
        isFalse,
        reason: 'en curso no se mueve',
      );
    });

    test('el maestro de ubicaciones es solo de Desarrollo', () {
      expect(visitasPuedeGestionarUbicaciones(esDesarrollador: true), isTrue);
      expect(visitasPuedeGestionarUbicaciones(esDesarrollador: false), isFalse);
    });
  });

  group('serialización de lo nuevo', () {
    test('firmas, tablas, encabezado y reprogramaciones van y vuelven', () {
      final v = visita(
        tablas: {
          kTablaExtintores: [filaBuena()],
        },
        firmaPro: VisitaFirma(
          nombre: 'Miguel',
          cargo: 'SST',
          modo: kFirmaModoGuardada,
          blob: Uint8List.fromList([1, 2, 3]),
        ),
        responsable: const VisitaResponsable(nombre: 'Ana', cargo: 'Admin'),
      );
      final map = v.toMap();
      map['reprogramaciones'] = [
        VisitaReprogramacion(
          de: DateTime(2026, 9, 17),
          a: DateTime(2026, 9, 20),
          motivo: 'Lluvia',
          porId: '111',
          porNombre: 'Miguel',
        ).toMap(),
      ];
      final back = VisitaProfesional.fromMap('v', map);
      expect(back.filasDe(kTablaExtintores).single.campos['ubicacion'], 'Cocina');
      expect(back.firmaProfesional!.blob, [1, 2, 3]);
      expect(back.firmaProfesional!.modo, kFirmaModoGuardada);
      expect(back.firmaEstablecimiento, isNull);
      expect(back.firmada, isFalse);
      expect(back.responsableEstablecimiento.cargo, 'Admin');
      expect(back.reprogramaciones.single.a, DateTime(2026, 9, 20));
      expect(back.reprogramaciones.single.motivo, 'Lluvia');
    });

    test('la marca guarda distancia y si estaba dentro del radio', () {
      final m = VisitaMarca.fromMap(
        VisitaMarca(
          at: Timestamp.now(),
          lat: 1,
          lng: 1,
          distanciaMetros: 42.4,
          dentroDelRadio: true,
        ).toMap(),
      );
      expect(m.distanciaMetros, 42.4);
      expect(m.dentroDelRadio, isTrue);
    });
  });
}
