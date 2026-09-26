import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_informe_pdf.dart';
import 'package:todo/visitas/visitas_marca_agua.dart';
import 'package:todo/visitas/visitas_models.dart';

/// 26 sep 2026: formatos como Google Forms (tipos de formulario, tablas con
/// escala y filas fijas), Gerencia con el alcance de Desarrollo, evidencias
/// adicionales, consolidado por fechas con colores y el informe con
/// encabezado SST y anexos.
void main() {
  const formulario = VisitaFormato(
    id: 'f1',
    empresaId: 'e',
    areaId: 'calidad',
    areaNombre: 'Calidad',
    nombre: 'Visita de calidad',
    estado: kFormatoVigente,
    codigo: 'F-UT-CAL-01',
    items: [
      VisitaFormatoItem(
        id: 'q1',
        orden: 1,
        seccion: 'Recepción',
        texto: 'Nombre de quien recibe',
        tipo: kItemTipoTexto,
      ),
      VisitaFormatoItem(
        id: 'q2',
        orden: 2,
        seccion: 'Recepción',
        texto: 'Comensales',
        tipo: kItemTipoNumero,
      ),
      VisitaFormatoItem(
        id: 'q3',
        orden: 3,
        seccion: 'Cocina',
        texto: 'Estado general',
        tipo: kItemTipoOpcion,
        opciones: ['Bueno', 'Malo'],
      ),
      VisitaFormatoItem(
        id: 'q4',
        orden: 4,
        seccion: 'Cocina',
        texto: 'Fecha del último fumigado',
        tipo: kItemTipoFecha,
        obligatoria: false,
      ),
      VisitaFormatoItem(
        id: 'q5',
        orden: 5,
        seccion: 'Cocina',
        texto: '¿Pisos limpios?',
        requiereEvidencia: true,
      ),
    ],
    tablas: [
      VisitaFormatoTabla(
        id: 'areas',
        nombre: 'Áreas del establecimiento',
        etiquetaFila: 'Área',
        camposEstado: [
          VisitaTablaCampo('e1', 'Limpieza'),
          VisitaTablaCampo('e2', 'Orden'),
        ],
        escala: kEscalaCumple,
        filasFijas: ['Cocina', 'Bodega'],
      ),
    ],
  );

  VisitaProfesional visita({
    Map<String, VisitaRespuesta> respuestas = const {},
    Map<String, List<VisitaFilaTabla>> tablas = const {},
    String estado = kVisitaEnCurso,
    String areaId = 'calidad',
    String areaNombre = 'Calidad',
    String centroId = 'c1',
    String centroNombre = 'Buen Pastor',
    DateTime? fecha,
    int? cumplimiento,
    List<VisitaEvidencia> adicionales = const [],
  }) => VisitaProfesional(
    id: 'v1',
    empresaId: 'e',
    formatoId: formulario.id,
    formatoNombre: formulario.nombre,
    formatoAsignado: formulario,
    areaId: areaId,
    areaNombre: areaNombre,
    centroId: centroId,
    centroNombre: centroNombre,
    profesionalId: 'p1',
    profesionalNombre: 'Laura Gómez',
    asignadoPorId: 'j1',
    asignadoPorNombre: 'Jefe',
    fechaProgramada: fecha ?? DateTime(2026, 9, 20),
    estado: estado,
    inicio: VisitaMarca(
      at: Timestamp.fromDate(DateTime(2026, 9, 20, 8, 30)),
      lat: 4.6,
      lng: -74.1,
      distanciaMetros: 12,
      dentroDelRadio: true,
    ),
    respuestas: respuestas,
    tablas: tablas,
    responsableEstablecimiento: const VisitaResponsable(
      nombre: 'Ana Ruiz',
      cargo: 'Administradora',
    ),
    cargoProfesional: 'Profesional de calidad',
    ciudad: 'Bogotá',
    observacionGeneral: 'Todo en orden salvo la bodega.',
    cumplimiento: cumplimiento,
    evidenciasAdicionales: adicionales,
  );

  final completas = {
    'q1': const VisitaRespuesta(valor: 'Pedro'),
    'q2': const VisitaRespuesta(valor: '120'),
    'q3': const VisitaRespuesta(valor: 'Bueno'),
    'q5': const VisitaRespuesta(resultado: kItemCumple),
  };
  final filasBien = {
    'areas': [
      VisitaFilaTabla(
        id: idFilaFija(0),
        estados: const {'e1': kFilaCumple, 'e2': kFilaCumple},
      ),
      VisitaFilaTabla(
        id: idFilaFija(1),
        estados: const {'e1': kFilaNoCumple, 'e2': kFilaCumple},
        observacion: 'Cajas en el piso',
      ),
    ],
  };

  group('Gerencia ve y hace lo mismo que Desarrollo', () {
    test(
      'todo acceso, programa, formatos, equipo, consolidado y ubicaciones',
      () {
        expect(
          visitasTodoAcceso(rol: kVisitasRolGerencia, esDesarrollador: false),
          isTrue,
        );
        expect(
          visitasTodoAcceso(rol: kVisitasRolJefe, esDesarrollador: false),
          isFalse,
        );
        expect(visitasPuedeProgramar(kVisitasRolGerencia), isTrue);
        expect(visitasPuedeGestionarFormatos(kVisitasRolGerencia), isTrue);
        expect(visitasPuedeGestionarEquipo(kVisitasRolGerencia), isTrue);
        expect(visitasPuedeVerConsolidado(kVisitasRolGerencia), isTrue);
        expect(
          visitasPuedeReprogramar(
            rol: kVisitasRolGerencia,
            visita: visita(estado: kVisitaProgramada),
            userId: 'g',
          ),
          isTrue,
        );
        expect(visitasRolRequiereArea(kVisitasRolGerencia), isFalse);
      },
    );

    test('ubicaciones: Desarrollo y Gerencia; jefe y profesional no', () {
      expect(visitasPuedeGestionarUbicaciones(esDesarrollador: true), isTrue);
      expect(
        visitasPuedeGestionarUbicaciones(
          esDesarrollador: false,
          rol: kVisitasRolGerencia,
        ),
        isTrue,
      );
      for (final r in [kVisitasRolJefe, kVisitasRolProfesional]) {
        expect(
          visitasPuedeGestionarUbicaciones(esDesarrollador: false, rol: r),
          isFalse,
        );
      }
    });

    test('Gerencia no ejecuta visitas: eso sigue siendo del profesional', () {
      expect(
        visitasPuedeEjecutar(
          rol: kVisitasRolGerencia,
          visita: visita(),
          userId: 'p1',
        ),
        isFalse,
      );
    });
  });

  group('preguntas de formulario', () {
    test('no califican: el % solo cuenta las que califican', () {
      final r = resumenDeVisita(formulario, completas);
      expect(r.total, 1);
      expect(r.porcentaje, 100);
    });

    test('obligatorias sin dato, número y opción inválidos no cierran', () {
      final e = validarCierreVisita(
        formulario,
        visita(
          respuestas: {
            'q2': const VisitaRespuesta(valor: 'muchos'),
            'q3': const VisitaRespuesta(valor: 'Regular'),
            'q5': const VisitaRespuesta(resultado: kItemCumple),
          },
          tablas: filasBien,
        ),
        exigirFirmas: false,
      );
      expect(e, contains('Ítem 1 sin responder: Nombre de quien recibe'));
      expect(e, contains('Ítem 2: "muchos" no es un número.'));
      expect(e, contains('Ítem 3: "Regular" no es una de las opciones.'));
      // La fecha es opcional.
      expect(e.any((x) => x.startsWith('Ítem 4')), isFalse);
    });

    test('completo cierra y no genera hallazgos de las de formulario', () {
      final v = visita(respuestas: completas, tablas: filasBien);
      expect(validarCierreVisita(formulario, v, exigirFirmas: false), isEmpty);
      final h = hallazgosDeVisita(formulario, v.respuestas, tablas: v.tablas);
      expect(h.map((x) => x.elemento), ['Área Bodega']);
    });

    test('pendiente: vacía obligatoria sí, opcional no, número mal sí', () {
      final items = {for (final i in formulario.items) i.id: i};
      expect(itemPendiente(items['q1']!, null), isTrue);
      expect(itemPendiente(items['q4']!, null), isFalse);
      expect(
        itemPendiente(items['q2']!, const VisitaRespuesta(valor: '3,5')),
        isFalse,
      );
      expect(
        itemPendiente(items['q2']!, const VisitaRespuesta(valor: 'x')),
        isTrue,
      );
    });

    test('los campos nuevos no ensucian los formatos viejos', () {
      // Las reglas comparan formatoAsignado.items con los guardados campo por
      // campo: un formato viejo debe volver a salir igual.
      final viejo = {
        'id': 'a',
        'orden': 1,
        'seccion': 'S',
        'texto': 'T',
        'requiereEvidencia': false,
        'tipo': kItemTipoCalificacion,
        'parte': '',
        'unidad': '',
      };
      expect(VisitaFormatoItem.fromMap(viejo).toMap(), viejo);
      final sst = formatoSstOficial('e');
      for (final t in sst.tablas) {
        expect(t.toMap().containsKey('escala'), isFalse);
        expect(t.toMap().containsKey('filasFijas'), isFalse);
      }
      for (final it in sst.items) {
        expect(it.toMap().keys.toSet(), viejo.keys.toSet());
      }
    });

    test('ida y vuelta de un formato con todo lo nuevo', () {
      final f = VisitaFormato.fromMap('f1', formulario.toMap());
      expect(f.items[2].opciones, ['Bueno', 'Malo']);
      expect(f.items[3].obligatoria, isFalse);
      expect(f.tablas.single.escala, kEscalaCumple);
      expect(f.tablas.single.filasFijas, ['Cocina', 'Bodega']);
      expect(f.codigo, 'F-UT-CAL-01');
      expect(validarFormato(f), isEmpty);
    });

    test('una lista sin opciones no es un formato válido', () {
      final f = formulario.copyWith(
        items: const [
          VisitaFormatoItem(
            id: 'x',
            orden: 1,
            texto: 'Elige',
            tipo: kItemTipoOpcion,
          ),
        ],
      );
      expect(validarFormato(f).join(), contains('dos opciones'));
    });
  });

  group('tablas con escala y filas fijas', () {
    final t = formulario.tablas.single;

    test('las filas fijas salen aunque no se hayan llenado', () {
      final filas = filasParaTabla(t, const []);
      expect(filas.map((f) => f.titulo(t)), ['Cocina', 'Bodega']);
      expect(pendientesDeTabla(t, const []), 2);
      final e = validarCierreVisita(
        formulario,
        visita(respuestas: completas),
        exigirFirmas: false,
      );
      expect(e, contains('Cocina: falta "Limpieza".'));
      expect(e.any((x) => x.contains('no hay ninguna fila')), isFalse);
    });

    test('la escala manda: un código de otra escala no vale', () {
      final f = VisitaFilaTabla(
        id: idFilaFija(0),
        estados: const {'e1': kFilaBueno, 'e2': kFilaCumple},
      );
      expect(filaTablaPendiente(t, f), isTrue);
      expect(estadoCorto(kEscalaCumple, kFilaNoCumple), 'NC');
      expect(filaEstadoEsHallazgo(kFilaNoCumple), isTrue);
      expect(filaEstadoEsHallazgo(kFilaNo), isTrue);
      expect(filaEstadoEsHallazgo(kFilaNoAplica), isFalse);
      expect(leyendaEscala(kEscalaSiNo), 'Sí: Sí · No: No');
    });
  });

  group('encabezado del informe', () {
    test('sin partes, una hoja con el código del documento', () {
      final h = formulario.hojasInforme.single;
      expect(h.codigo, 'F-UT-CAL-01');
      expect(h.nombre, 'VISITA DE CALIDAD');
      expect(formulario.sistemaEncabezado, 'SISTEMA DE GESTIÓN · CALIDAD');
      expect(formatoSstOficial('e').hojasInforme.map((p) => p.codigo), [
        kParteSstDiagnostico,
        kParteSstExtintores,
        kParteSstBotiquin,
      ]);
    });

    test('el cargo del profesional sale de la ficha o del rol', () {
      expect(
        cargoProfesionalDeActa('Nutricionista', 'Nutrición'),
        'Nutricionista',
      );
      expect(
        cargoProfesionalDeActa('', 'Nutrición'),
        'Profesional de Nutrición',
      );
    });

    test('la marca de agua dice qué, dónde, cuándo y quién', () {
      final l = lineasMarcaVisita(
        v: visita(),
        detalle: 'Ítem 5',
        ahora: DateTime(2026, 9, 20, 9, 5),
      );
      expect(l.first, 'VISITA CALIDAD · Buen Pastor');
      expect(l[1], '20/09/2026 09:05 · Ítem 5');
      expect(l[2], 'Profesional: Laura Gómez');
      expect(l[3], contains('a 12 m del establecimiento'));
    });
  });

  group('evidencias adicionales', () {
    test('se guardan con su descripción y la marca', () {
      final v = visita(
        adicionales: const [
          VisitaEvidencia(
            url: 'u',
            path: 'p',
            nombre: 'n.jpg',
            descripcion: 'Fachada',
            conMarca: true,
          ),
        ],
      );
      final r = VisitaProfesional.fromMap('v1', v.toMap());
      expect(r.evidenciasAdicionales.single.descripcion, 'Fachada');
      expect(r.evidenciasAdicionales.single.conMarca, isTrue);
    });
  });

  group('consolidado por fechas y por área', () {
    final nutricion = [
      for (var d = 1; d <= 3; d++)
        visita(
          estado: kVisitaTerminada,
          areaId: 'nutricion',
          areaNombre: 'Nutrición',
          fecha: DateTime(2026, 9, d),
          cumplimiento: 80,
        ),
    ];
    final calidad = [
      visita(
        estado: kVisitaTerminada,
        fecha: DateTime(2026, 9, 10),
        cumplimiento: 100,
      ),
      visita(estado: kVisitaProgramada, fecha: DateTime(2026, 9, 28)),
    ];

    test('el rango incluye los dos extremos', () {
      final v = visita(fecha: DateTime(2026, 9, 10, 15));
      expect(
        visitaEnRango(v, DateTime(2026, 9, 10), DateTime(2026, 9, 10)),
        isTrue,
      );
      expect(
        visitaEnRango(v, DateTime(2026, 9, 11), DateTime(2026, 9, 30)),
        isFalse,
      );
    });

    test('una línea por área y un establecimiento por área al combinar', () {
      final c = consolidarMes([...nutricion, ...calidad], separarPorArea: true);
      expect(c.porArea.map((a) => a.nombre), ['Calidad', 'Nutrición']);
      expect(c.porArea.first.terminadas, 1);
      expect(c.porArea.first.programadas, 1);
      expect(c.porArea.last.promedio, 80);
      // El mismo establecimiento visitado por dos áreas: dos filas.
      expect(c.porEstablecimiento, hasLength(2));
      expect(c.porEstablecimiento.first.areaNombre, 'Nutrición');
      final sinSeparar = consolidarMes([...nutricion, ...calidad]);
      expect(sinSeparar.porEstablecimiento, hasLength(1));
    });

    test('el color de un área no cambia al filtrar', () {
      final i = indiceColorAreas(['calidad', 'nutricion', 'sst']);
      expect(colorAreaVisitas(i, 'nutricion'), kPaletaAreasVisitas[1]);
      expect(colorAreaVisitas(i, 'sst'), kPaletaAreasVisitas[2]);
    });
  });

  group('filtros de Mis visitas', () {
    final lista = [
      visita(estado: kVisitaProgramada, fecha: DateTime(2026, 9, 1)),
      visita(
        estado: kVisitaTerminada,
        fecha: DateTime(2026, 9, 15),
        centroId: 'c2',
        centroNombre: 'Chocontá',
      ),
    ];

    test('vencidas, texto sin tildes, rango y establecimiento', () {
      final ahora = DateTime(2026, 9, 20);
      expect(
        filtrarVisitas(lista, estado: kVisitaVencidaFiltro, ahora: ahora),
        hasLength(1),
      );
      expect(
        filtrarVisitas(lista, texto: 'choconta', ahora: ahora),
        hasLength(1),
      );
      expect(
        filtrarVisitas(
          lista,
          desde: DateTime(2026, 9, 10),
          hasta: DateTime(2026, 9, 15),
          ahora: ahora,
        ).single.centroNombre,
        'Chocontá',
      );
      expect(
        filtrarVisitas(lista, establecimiento: 'c1', ahora: ahora),
        hasLength(1),
      );
    });
  });

  group('informes PDF', () {
    Uint8List foto() =>
        Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 40)));

    test('la visita sale con hojas, observaciones, firmas y anexos', () async {
      final v = VisitaProfesional.fromMap('v1', {
        ...visita(
          estado: kVisitaTerminada,
          respuestas: {
            ...completas,
            'q5': const VisitaRespuesta(
              resultado: kItemNoCumple,
              observacion: 'Grasa bajo la estufa — revisar “ya”',
              evidencias: [
                VisitaEvidencia(url: '', path: 'a', nombre: 'a.jpg'),
              ],
            ),
          },
          tablas: filasBien,
          adicionales: const [
            VisitaEvidencia(
              url: '',
              path: 'b',
              nombre: 'b.jpg',
              descripcion: 'Fachada',
            ),
          ],
        ).toMap(),
      });
      var pedidas = 0;
      final bytes = await generarInformeVisita(
        v: v,
        formato: formulario,
        empresaNombre: 'Capital',
        cargarImagen: (e) async {
          pedidas++;
          return foto();
        },
      );
      expect(pedidas, 2);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('el formato SST sigue saliendo con sus tres hojas', () async {
      final sst = formatoSstOficial('e');
      final v = VisitaProfesional.fromMap('v2', {
        ...visita(estado: kVisitaTerminada).toMap(),
        'formatoId': sst.id,
        'formatoAsignado': sst.toMap(),
      });
      final bytes = await generarInformeVisita(
        v: v,
        formato: sst,
        empresaNombre: 'Capital',
        conAnexos: false,
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('el consolidado combinado con actas', () async {
      final visitas = [
        visita(
          estado: kVisitaTerminada,
          respuestas: completas,
          tablas: filasBien,
          cumplimiento: 100,
        ),
        visita(
          estado: kVisitaTerminada,
          areaId: 'nutricion',
          areaNombre: 'Nutrición',
          respuestas: completas,
          cumplimiento: 50,
        ),
      ];
      final c = consolidarMes(visitas, separarPorArea: true);
      final bytes = await generarConsolidadoVisitas(
        c: c,
        titulo: 'Calidad, Nutrición',
        desde: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 30),
        empresaNombre: 'Capital',
        visitas: visitas,
        colorAreas: indiceColorAreas(['calidad', 'nutricion']),
        incluirActas: true,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
